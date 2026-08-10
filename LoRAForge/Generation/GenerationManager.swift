import Foundation
import SwiftUI
import Combine
import DrawThingsQueue
import DrawThingsClient
import DTConfigBridge

/// App-level generation manager. One DrawThingsQueue, one FIFO, routing results
/// to the correct project and entry via a persistent request map.
@Observable
final class GenerationManager {
    // MARK: - Server

    var serverAddress: String {
        didSet { UserDefaults.standard.set(serverAddress, forKey: "dtServerAddress") }
    }
    var useTLS: Bool {
        didSet { UserDefaults.standard.set(useTLS, forKey: "dtUseTLS") }
    }
    var isConnected: Bool { queue != nil }

    // MARK: - Queue

    private(set) var queue: DrawThingsQueue?
    private var resultTask: Task<Void, Never>?
    private var eventCancellable: AnyCancellable?

    // MARK: - Routing

    /// Maps request UUID → (projectID, entryID, provenance data).
    /// Persisted alongside QueueStorage.
    private(set) var requestMap: [UUID: RequestMapping] = [:]

    /// Open documents registered for direct ingestion.
    var openDocuments: [UUID: LoRAForgeDocument] = [:]

    /// Staged results for projects that were closed when results arrived.
    private(set) var stagedResults: [StagedResult] = []

    // MARK: - Init

    init() {
        self.serverAddress = UserDefaults.standard.string(forKey: "dtServerAddress") ?? "localhost:7859"
        self.useTLS = UserDefaults.standard.object(forKey: "dtUseTLS") != nil
            ? UserDefaults.standard.bool(forKey: "dtUseTLS")
            : true
        loadRequestMap()
        loadStagedResults()
    }

    // MARK: - Connection

    func connect() {
        do {
            let q = try DrawThingsQueue(address: serverAddress, useTLS: useTLS)
            queue = q
            startIngesting()
        } catch {
            print("Failed to connect to Draw Things: \(error)")
        }
    }

    func disconnect() {
        resultTask?.cancel()
        resultTask = nil
        eventCancellable = nil
        queue = nil
    }

    // MARK: - Enqueue

    func enqueue(
        entry: DatasetEntry,
        in document: LoRAForgeDocument,
        count: Int = 1
    ) {
        guard let queue else { return }

        let settings = entry.generationSettings

        for _ in 0..<count {
            let seed: Int64
            if settings.useCustomSeed {
                seed = settings.customSeed
            } else {
                seed = Int64(UInt32.random(in: 0...UInt32.max))
            }

            var config = DrawThingsConfiguration()
            // Apply user's config JSON if valid
            if let parsed = parseConfig(settings.configurationJSON) {
                config = parsed
            }
            config.seed = seed
            config.batchSize = 1

            let request = queue.enqueue(
                prompt: settings.prompt,
                negativePrompt: settings.negativePrompt,
                configuration: config,
                name: entry.name
            )

            let mapping = RequestMapping(
                requestID: request.id,
                projectID: document.metadata.id,
                entryID: entry.id,
                seed: seed,
                prompt: settings.prompt,
                negativePrompt: settings.negativePrompt,
                configurationJSON: settings.configurationJSON
            )
            requestMap[request.id] = mapping
            saveRequestMap()
        }
    }

    // MARK: - Document Registration

    func registerDocument(_ doc: LoRAForgeDocument) {
        openDocuments[doc.metadata.id] = doc
        ingestStagedResults(for: doc)
    }

    func unregisterDocument(_ doc: LoRAForgeDocument) {
        openDocuments.removeValue(forKey: doc.metadata.id)
    }

    /// Pending requests for a specific project.
    func pendingRequests(for projectID: UUID) -> [RequestMapping] {
        requestMap.values.filter { $0.projectID == projectID }
    }

    // MARK: - Result Ingestion

    private func startIngesting() {
        guard let queue else { return }

        resultTask = Task { [weak self] in
            for await result in queue.results {
                await self?.handleResult(result)
            }
        }
    }

    private func handleResult(_ result: GenerationResult) {
        guard let mapping = requestMap[result.id] else { return }

        guard let image = result.images.first else {
            requestMap.removeValue(forKey: result.id)
            saveRequestMap()
            return
        }

        let imageData = platformImagePNGData(image)
        let provenance = ImageProvenance(
            prompt: mapping.prompt,
            negativePrompt: mapping.negativePrompt,
            seed: mapping.seed,
            configurationJSON: mapping.configurationJSON,
            referenceImageIDs: []
        )

        if let doc = openDocuments[mapping.projectID] {
            ingestIntoDocument(doc, entryID: mapping.entryID, imageData: imageData, provenance: provenance)
        } else {
            stageResult(mapping: mapping, imageData: imageData, provenance: provenance)
        }

        requestMap.removeValue(forKey: result.id)
        saveRequestMap()
    }

    private func ingestIntoDocument(
        _ doc: LoRAForgeDocument, entryID: UUID,
        imageData: Data, provenance: ImageProvenance
    ) {
        let filename = "\(UUID().uuidString).png"
        doc.imagesWrapper.addRegularFile(withContents: imageData, preferredFilename: filename)

        if let idx = doc.entries.firstIndex(where: { $0.id == entryID }) {
            let entryImage = EntryImage(rank: .candidate, filename: filename, provenance: provenance)
            doc.entries[idx].images.append(entryImage)
        }
    }

    // MARK: - Staging

    private func stageResult(mapping: RequestMapping, imageData: Data, provenance: ImageProvenance) {
        let staged = StagedResult(
            id: UUID(),
            projectID: mapping.projectID,
            entryID: mapping.entryID,
            imageData: imageData,
            provenance: provenance,
            receivedAt: Date()
        )
        stagedResults.append(staged)
        saveStagedResults()
    }

    private func ingestStagedResults(for doc: LoRAForgeDocument) {
        let matching = stagedResults.filter { $0.projectID == doc.metadata.id }
        guard !matching.isEmpty else { return }

        for staged in matching {
            ingestIntoDocument(doc, entryID: staged.entryID,
                               imageData: staged.imageData, provenance: staged.provenance)
        }

        stagedResults.removeAll { $0.projectID == doc.metadata.id }
        saveStagedResults()
    }

    // MARK: - Config Parsing

    private func parseConfig(_ json: String) -> DrawThingsConfiguration? {
        guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              json != "{\n}" else {
            return nil
        }
        return ConfigurationInterop.configuration(from: json)
    }

    // MARK: - Platform Image

    private func platformImagePNGData(_ image: Any) -> Data {
        #if os(macOS)
        guard let nsImage = image as? NSImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return Data() }
        return rep.representation(using: .png, properties: [:]) ?? Data()
        #else
        guard let uiImage = image as? UIImage else { return Data() }
        return uiImage.pngData() ?? Data()
        #endif
    }

    // MARK: - Persistence

    private var mapURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LoRAForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("request-map.json")
    }

    private var stagedURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LoRAForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("staged-results.json")
    }

    private func saveRequestMap() {
        let data = try? JSONEncoder().encode(Array(requestMap.values))
        try? data?.write(to: mapURL)
    }

    private func loadRequestMap() {
        guard let data = try? Data(contentsOf: mapURL),
              let mappings = try? JSONDecoder().decode([RequestMapping].self, from: data) else { return }
        requestMap = Dictionary(mappings.map { ($0.requestID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func saveStagedResults() {
        let data = try? JSONEncoder().encode(stagedResults)
        try? data?.write(to: stagedURL)
    }

    private func loadStagedResults() {
        guard let data = try? Data(contentsOf: stagedURL),
              let results = try? JSONDecoder().decode([StagedResult].self, from: data) else { return }
        stagedResults = results
    }
}

// MARK: - Types

struct RequestMapping: Codable, Sendable, Identifiable {
    let requestID: UUID
    let projectID: UUID
    let entryID: UUID
    let seed: Int64
    let prompt: String
    let negativePrompt: String
    let configurationJSON: String
    var id: UUID { requestID }
}

struct StagedResult: Codable, Sendable, Identifiable {
    let id: UUID
    let projectID: UUID
    let entryID: UUID
    let imageData: Data
    let provenance: ImageProvenance
    let receivedAt: Date
}
