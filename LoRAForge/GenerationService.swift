import Foundation
import Combine
import DrawThingsQueue
import DrawThingsClient
import DTConfigBridge
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
final class GenerationService {
    static func enableDebugLogging() {
        DrawThingsClientLogger.minimumLevel = .debug
    }
    private(set) var isConnected = false
    private(set) var isPaused = false
    private(set) var lastError: String?
    private(set) var pendingCount = 0
    private(set) var isProcessing = false
    private(set) var currentRequest: GenerationRequest?
    private(set) var currentProgress: GenerationProgress?
    private(set) var pendingRequests: [GenerationRequest] = []

    var serverAddress: String {
        didSet { UserDefaults.standard.set(serverAddress, forKey: "dtServerAddress") }
    }
    var useTLS: Bool {
        didSet { UserDefaults.standard.set(useTLS, forKey: "dtUseTLS") }
    }
    var sharedSecret: String {
        didSet { UserDefaults.standard.set(sharedSecret, forKey: "dtSharedSecret") }
    }

    private var queue: DrawThingsQueue?
    private var requestMap: [UUID: RequestTarget] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var resultTask: Task<Void, Never>?
    private weak var library: LibraryManager?

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

    func connect() {
        disconnect()
        let secret = sharedSecret.isEmpty ? nil : sharedSecret
        do {
            // Test the connection first with an echo call
            let service = try DrawThingsService(address: serverAddress, useTLS: useTLS)
            let q = DrawThingsQueue(service: service, sharedSecret: secret)
            queue = q
            observeQueue(q)
            startIngestion(q)

            // Verify connectivity asynchronously
            Task {
                do {
                    _ = try await service.echo()
                    isConnected = true
                    lastError = nil
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
        cancellables.removeAll()
        queue = nil
        isConnected = false
        isPaused = false
        pendingCount = 0
        isProcessing = false
        currentRequest = nil
        currentProgress = nil
        pendingRequests = []
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
        let actualSeed = seed ?? Int64(Int.random(in: 0...Int(UInt32.max)))
        config.seed = actualSeed
        config.batchSize = 1
        config.batchCount = 1

        // Build moodboard hints from reference images
        var hints: [HintProto] = []
        if !referenceImageData.isEmpty {
            let builder = HintBuilder()
            builder.addMoodboardImages(referenceImageData, weight: 1.0)
            hints = builder.build()
        }

        let request = queue.enqueue(
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
        queue?.cancel(id: id)
    }

    func clearPending() {
        guard let queue else { return }
        for request in queue.pendingRequests {
            queue.cancel(id: request.id)
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

    // MARK: - Observation

    private func observeQueue(_ q: DrawThingsQueue) {
        q.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isPaused = $0 }
            .store(in: &cancellables)

        q.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastError = $0 }
            .store(in: &cancellables)

        q.$pendingRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.pendingCount = $0.count
                self?.pendingRequests = $0
            }
            .store(in: &cancellables)

        q.$isProcessing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isProcessing = $0 }
            .store(in: &cancellables)

        q.$currentRequest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currentRequest = $0 }
            .store(in: &cancellables)

        q.$currentProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currentProgress = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Result Ingestion (stream-driven, not polling)

    private func startIngestion(_ q: DrawThingsQueue) {
        resultTask = Task { [weak self] in
            for await result in q.results {
                await self?.ingest(result)
            }
        }
    }

    @MainActor
    private func ingest(_ result: GenerationResult) {
        guard let target = requestMap.removeValue(forKey: result.id) else { return }
        saveRequestMap()

        guard let library, let image = result.images.first else { return }

        // Write image to the target project's bundle
        guard let bundleURL = library.bundleURL(for: target.projectID) else {
            // Orphan — project deleted or moved
            return
        }

        let imagesDir = bundleURL.appending(path: "images")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).png"
        let destURL = imagesDir.appending(path: filename)

        // Write image data
        #if os(macOS)
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: destURL)
        }
        #else
        if let data = image.pngData() {
            try? data.write(to: destURL)
        }
        #endif

        // Build provenance
        let provenance = ImageProvenance(
            prompt: result.request.prompt,
            negativePrompt: result.request.negativePrompt,
            seed: result.request.configuration.seed ?? 0,
            configJSON: target.configJSON,
            referenceImageIDs: target.referenceImageIDs
        )

        let imageDoc = ImageDocument(filename: filename, provenance: provenance)

        // Load the project, add the image, save, and notify UI
        if var doc = try? library.loadDocument(id: target.projectID) {
            if let entryIdx = doc.entries.firstIndex(where: { $0.id == target.entryID }) {
                doc.entries[entryIdx].images.append(imageDoc)
                library.updateDocumentExternally(doc)
                try? library.saveImmediately(id: target.projectID)
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
