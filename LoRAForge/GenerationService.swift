import Foundation
import CoreGraphics
import DrawThingsQueue
import DrawThingsClient
import DTConfigBridge

@Observable
final class GenerationService {
    static func enableDebugLogging() {
        DTLogger.shared.minimumLevel = .debug
    }
    private(set) var isConnected = false
    private(set) var lastError: String?
    private(set) var serverCatalog: ServerCatalog = .unavailable

    // Queue state is read straight from the @Observable GenerationQueue, so views
    // track it without a mirroring layer.
    var isPaused: Bool { queue?.isPaused ?? false }
    var isProcessing: Bool { queue?.isProcessing ?? false }
    var pendingJobs: [QueueJob] { queue?.pending ?? [] }
    var pendingCount: Int { pendingJobs.count }
    var currentJob: QueueJob? { queue?.current }
    var currentProgress: GenerationProgress? { queue?.progress }
    var currentPreview: CGImage? { queue?.preview }

    var serverAddress: String {
        didSet { UserDefaults.standard.set(serverAddress, forKey: "dtServerAddress") }
    }
    var useTLS: Bool {
        didSet { UserDefaults.standard.set(useTLS, forKey: "dtUseTLS") }
    }
    var sharedSecret: String {
        didSet { UserDefaults.standard.set(sharedSecret, forKey: "dtSharedSecret") }
    }

    private var queue: GenerationQueue?
    @ObservationIgnored private var requestMap: [UUID: RequestTarget] = [:]
    @ObservationIgnored private var resultTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private weak var library: LibraryManager?

    struct RequestTarget: Codable {
        let projectID: UUID
        let entryID: UUID
        var configJSON: String?
        var referenceImageIDs: [UUID]?

        init(projectID: UUID, entryID: UUID, configJSON: String? = nil, referenceImageIDs: [UUID]? = nil) {
            self.projectID = projectID
            self.entryID = entryID
            self.configJSON = configJSON
            self.referenceImageIDs = referenceImageIDs
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            projectID = try c.decode(UUID.self, forKey: .projectID)
            entryID = try c.decode(UUID.self, forKey: .entryID)
            configJSON = try c.decodeIfPresent(String.self, forKey: .configJSON)
            referenceImageIDs = try c.decodeIfPresent([UUID].self, forKey: .referenceImageIDs)
        }
    }

    init(library: LibraryManager) {
        self.library = library
        self.serverAddress = UserDefaults.standard.string(forKey: "dtServerAddress") ?? "localhost:7859"
        self.useTLS = UserDefaults.standard.object(forKey: "dtUseTLS") as? Bool ?? true
        self.sharedSecret = UserDefaults.standard.string(forKey: "dtSharedSecret") ?? ""
        loadRequestMap()
    }

    // MARK: - Connection

    func applyProfile(_ profile: SDConnectionProfile) {
        serverAddress = profile.address
        useTLS = profile.useTLS
        sharedSecret = profile.sharedSecret
        connect()
    }

    func connect() {
        disconnect()
        let options = ConnectionOptions(
            security: useTLS ? .tls() : .plaintext,
            sharedSecret: sharedSecret.isEmpty ? nil : sharedSecret
        )
        do {
            let service = try DrawThingsService(address: serverAddress, options: options)
            let q = GenerationQueue(service: service)
            queue = q
            // Subscribe before anything can be enqueued: the queue's streams only
            // deliver values sent after the subscription is made.
            startIngestion(q.results)
            observeEvents(q.events)

            // Verify connectivity asynchronously
            Task {
                do {
                    let reply = try await service.echo()
                    serverCatalog = ServerCatalog(reply: reply)
                    isConnected = true
                    lastError = nil
                } catch DrawThingsError.unauthenticated {
                    // v2 throws instead of returning a reply with sharedSecretMissing set.
                    serverCatalog = .sharedSecretMissing
                    isConnected = true
                    lastError = "Server requires a shared secret"
                } catch {
                    lastError = "Connection test failed: \(error.localizedDescription)"
                    isConnected = false
                }
            }
        } catch {
            lastError = "Connection failed: \(error.localizedDescription)"
            isConnected = false
        }
    }

    func disconnect() {
        resultTask?.cancel()
        resultTask = nil
        eventTask?.cancel()
        eventTask = nil
        if let queue {
            // Unfinished jobs are discarded with the queue; drop their routing entries.
            let unfinished = queue.jobs.filter { !$0.status.isFinished }.map(\.id)
            if !unfinished.isEmpty {
                unfinished.forEach { requestMap.removeValue(forKey: $0) }
                saveRequestMap()
            }
            queue.cancelAll()
            let service = queue.service
            Task { await service.shutdown() }
        }
        queue = nil
        isConnected = false
        serverCatalog = .unavailable
    }

    // MARK: - Enqueue

    func generate(
        prompt: String,
        negativePrompt: String,
        seed: Int64?,
        configJSON: String,
        projectConfigJSON: String?,
        projectID: UUID,
        entryID: UUID,
        referenceImageData: [Data] = [],
        referenceImageIDs: [UUID] = []
    ) {
        guard let queue else {
            lastError = "Not connected to Draw Things server"
            return
        }

        // Entry config is authoritative (inherited from project default at creation).
        // Fall back through project → app → library default only for legacy entries
        // with empty config.
        var config: DrawThingsConfiguration
        if !configJSON.trimmingCharacters(in: .whitespaces).isEmpty,
           let parsed = ConfigurationInterop.configuration(from: configJSON) {
            config = parsed
        } else if let json = projectConfigJSON, !json.trimmingCharacters(in: .whitespaces).isEmpty,
                  let parsed = ConfigurationInterop.configuration(from: json) {
            config = parsed
        } else if let defaultJSON = UserDefaults.standard.string(forKey: "defaultGenerationConfig"),
                  !defaultJSON.trimmingCharacters(in: .whitespaces).isEmpty,
                  let parsed = ConfigurationInterop.configuration(from: defaultJSON) {
            config = parsed
        } else {
            config = DrawThingsConfiguration()
        }

        // App owns seed and batch size — override regardless of config
        // Draw Things seeds are 32-bit; stored Int64 seeds keep their low 32 bits,
        // as the 1.x client did when encoding.
        config.seed = seed.map { UInt32(truncatingIfNeeded: $0) } ?? UInt32.random(in: 0...UInt32.max)
        config.batchSize = 1
        config.batchCount = 1

        // Build moodboard hints from reference images
        var hints: [HintProto] = []
        if !referenceImageData.isEmpty {
            var builder = HintBuilder()
            builder.addMoodboardImages(referenceImageData, weight: 1.0)
            do {
                hints = try builder.build()
            } catch {
                lastError = "Reference images could not be read: \(error.localizedDescription)"
                return
            }
        }

        let request = GenerationRequest(
            prompt: prompt,
            negativePrompt: negativePrompt,
            configuration: config,
            hints: hints
        )

        // Serialize the final config (after seed/batch overrides) for provenance
        let finalConfigJSON = ConfigurationInterop.text(from: config, style: .nonDefaultOnly)

        requestMap[request.id] = RequestTarget(
            projectID: projectID,
            entryID: entryID,
            configJSON: finalConfigJSON,
            referenceImageIDs: referenceImageIDs.isEmpty ? nil : referenceImageIDs
        )
        saveRequestMap()
        queue.enqueue(request)
    }

    func pendingRequestCount(for projectID: UUID) -> Int {
        requestMap.values.filter { $0.projectID == projectID }.count
    }

    // MARK: - Queue Control

    func togglePause() {
        guard let queue else { return }
        if isPaused {
            queue.resume()
        } else {
            queue.pause()
        }
    }

    func cancelRequest(id: UUID) {
        queue?.cancel(id)
    }

    func clearPending() {
        guard let queue else { return }
        for job in queue.pending {
            queue.cancel(job.id)
        }
    }

    /// Entry name for a queued request, looked up from the request map and library.
    func entryName(for requestID: UUID) -> String? {
        guard let target = requestMap[requestID],
              let library,
              let doc = try? library.loadDocument(id: target.projectID),
              let entry = doc.entries.first(where: { $0.id == target.entryID })
        else { return nil }
        return entry.name
    }

    // MARK: - Queue Events

    private func observeEvents(_ events: AsyncStream<QueueEvent>) {
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .failed(let job):
                    // Failed and cancelled jobs never produce a result, so their
                    // routing entries would otherwise stay in the map.
                    releaseTarget(for: job.id)
                    lastError = "Generation failed: \(job.error?.localizedDescription ?? "unknown error")"
                case .cancelled(let job):
                    releaseTarget(for: job.id)
                case .paused(let reason):
                    if let reason { lastError = reason }
                default:
                    break
                }
            }
        }
    }

    private func releaseTarget(for id: UUID) {
        if requestMap.removeValue(forKey: id) != nil {
            saveRequestMap()
        }
    }

    // MARK: - Result Ingestion (stream-driven, not polling)

    private func startIngestion(_ results: AsyncStream<GenerationResult>) {
        resultTask = Task { [weak self] in
            for await result in results {
                guard let self else { return }

                // 1. Claim target on main (observable mutation)
                guard let target = requestMap.removeValue(forKey: result.id) else { continue }
                saveRequestMap()

                guard let library = self.library, let image = result.images.first else { continue }
                guard let bundleURL = library.bundleURL(for: target.projectID) else { continue }

                // 2. Heavy work off main: image conversion + file I/O
                let filename = UUID().uuidString + ".png"
                let imageDoc = await Task.detached {
                    let imagesDir = bundleURL.appending(path: "images")
                    try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

                    let destURL = imagesDir.appending(path: filename)

                    if let png = try? ImageHelpers.pngData(for: image) {
                        try? png.write(to: destURL)
                    }

                    let provenance = ImageProvenance(
                        prompt: result.request.prompt,
                        negativePrompt: result.request.negativePrompt,
                        seed: Int64(result.request.configuration.seed ?? 0),
                        configJSON: target.configJSON,
                        referenceImageIDs: target.referenceImageIDs
                    )
                    return ImageDocument(filename: filename, provenance: provenance)
                }.value

                // 3. Update document on main (observable), save off main
                if var doc = try? library.loadDocument(id: target.projectID) {
                    if let entryIdx = doc.entries.firstIndex(where: { $0.id == target.entryID }) {
                        doc.entries[entryIdx].images.append(imageDoc)
                        library.updateDocumentExternally(doc)
                    }
                }

                // Save on a detached task to avoid blocking ingestion
                Task.detached {
                    try? library.saveImmediately(id: target.projectID)
                }
            }
        }
    }

    // MARK: - Request Map Persistence

    private var requestMapURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "LoRAForge Library")
            .appending(path: "request-map.json")
    }

    private func saveRequestMap() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(requestMap) {
            try? data.write(to: requestMapURL, options: .atomic)
        }
    }

    private func loadRequestMap() {
        guard let data = try? Data(contentsOf: requestMapURL) else { return }
        requestMap = (try? JSONDecoder().decode([UUID: RequestTarget].self, from: data)) ?? [:]
    }
}
