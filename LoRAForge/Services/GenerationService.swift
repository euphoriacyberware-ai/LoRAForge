import Foundation
import SwiftUI
import AppKit
import Combine
import DrawThingsClient
import DrawThingsQueue

@MainActor
final class GenerationService: ObservableObject {

    @Published var isRunning = false
    @Published var currentPromptID: UUID?
    @Published var currentImageIndex = 0
    @Published var totalImages = 0
    @Published var statusMessage = ""
    @Published var generationStage: String?
    @Published var previewImage: NSImage?

    private var generationTask: Task<Void, Never>?
    private(set) var queue: DrawThingsQueue?
    private(set) var requestMappings: [UUID: RequestMapping] = [:]
    private var completedPerPrompt: [UUID: Int] = [:]

    struct RequestMapping {
        let promptID: UUID
        let promptIndex: Int
        let imageNumber: Int        // 0-based within generateCount
        let promptDisplayNumber: Int // 1-based for status message
        let totalForPrompt: Int     // prompt.generateCount
        let promptText: String
    }

    var progressFraction: Double {
        guard totalImages > 0 else { return 0 }
        return Double(currentImageIndex) / Double(totalImages)
    }

    // MARK: - Run

    func run(document: LoRAForgeDocument, runAll: Bool) {
        if isRunning, let queue {
            enqueuePrompts(document: document, runAll: runAll, onlyPromptID: nil, into: queue)
            return
        }
        guard !isRunning else { return }

        generationTask = Task {
            await performGeneration(document: document, runAll: runAll, onlyPromptID: nil)
        }
    }

    func runSingle(document: LoRAForgeDocument, promptID: UUID) {
        if isRunning, let queue {
            enqueuePrompts(document: document, runAll: true, onlyPromptID: promptID, into: queue)
            return
        }
        guard !isRunning else { return }

        generationTask = Task {
            await performGeneration(document: document, runAll: true, onlyPromptID: promptID)
        }
    }

    // MARK: - Stop

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        queue?.cancelAll()
        isRunning = false
        currentPromptID = nil
        generationStage = nil
        previewImage = nil
        statusMessage = "Stopped"
    }

    func cancelRequest(id: UUID) {
        queue?.cancel(id: id)
        requestMappings.removeValue(forKey: id)
    }

    // MARK: - Enqueue into existing queue

    private func enqueuePrompts(document: LoRAForgeDocument, runAll: Bool, onlyPromptID: UUID?, into dtQueue: DrawThingsQueue) {
        let promptsToProcess: [Prompt]
        if let onlyPromptID {
            promptsToProcess = document.project.prompts.filter { $0.id == onlyPromptID }
        } else if runAll {
            promptsToProcess = document.project.prompts
        } else {
            promptsToProcess = document.project.prompts.filter { prompt in
                !prompt.generatedImages.contains(where: { $0.rank == .final_ })
            }
        }

        guard !promptsToProcess.isEmpty else { return }

        let addedCount = promptsToProcess.reduce(0) { $0 + $1.generateCount }
        totalImages += addedCount

        for prompt in promptsToProcess {
            guard let promptIndex = document.project.prompts.firstIndex(where: { $0.id == prompt.id }) else {
                continue
            }

            let configJSON = prompt.configurationOverrideJSON ?? document.project.baseConfigurationJSON
            let parsed = ConfigurationMapper.parse(fromJSON: configJSON)
            let hints = buildHints(prompt: prompt, document: document)
            let promptDisplayNumber = (document.project.prompts.firstIndex(where: { $0.id == prompt.id }) ?? 0) + 1

            for i in 0..<prompt.generateCount {
                let name = "Prompt \(promptDisplayNumber) — image \(i + 1)/\(prompt.generateCount)"
                let request = dtQueue.enqueue(
                    prompt: prompt.text,
                    negativePrompt: parsed.negativePrompt,
                    configuration: parsed.configuration,
                    hints: hints,
                    name: name
                )

                requestMappings[request.id] = RequestMapping(
                    promptID: prompt.id,
                    promptIndex: promptIndex,
                    imageNumber: i,
                    promptDisplayNumber: promptDisplayNumber,
                    totalForPrompt: prompt.generateCount,
                    promptText: prompt.text
                )
            }

            if completedPerPrompt[prompt.id] == nil {
                completedPerPrompt[prompt.id] = 0
            }
        }
    }

    // MARK: - Generation Loop

    private func performGeneration(document: LoRAForgeDocument, runAll: Bool, onlyPromptID: UUID?) async {
        isRunning = true
        statusMessage = ""
        generationStage = nil
        previewImage = nil
        currentImageIndex = 0
        requestMappings = [:]
        completedPerPrompt = [:]

        defer {
            isRunning = false
            currentPromptID = nil
            generationStage = nil
            previewImage = nil
            queue = nil
        }

        // Resolve connection
        guard let connectionID = document.project.generationConnectionID,
              let connection = ConnectionManager.shared.connection(for: connectionID) else {
            statusMessage = "No server selected"
            return
        }

        // Create queue
        let dtQueue: DrawThingsQueue
        do {
            dtQueue = try DrawThingsQueue(address: "\(connection.host):\(connection.port)", sharedSecret: connection.sharedSecret)
        } catch {
            statusMessage = "Failed to create queue: \(error.localizedDescription)"
            return
        }
        self.queue = dtQueue

        // Determine prompts to process
        let promptsToProcess: [Prompt]
        if let onlyPromptID {
            promptsToProcess = document.project.prompts.filter { $0.id == onlyPromptID }
        } else if runAll {
            promptsToProcess = document.project.prompts
        } else {
            promptsToProcess = document.project.prompts.filter { prompt in
                let hasFinal = prompt.generatedImages.contains(where: { $0.rank == .final_ })
                if hasFinal {
                    Swift.print("Skipping prompt \(prompt.order + 1) — has final image")
                }
                return !hasFinal
            }
        }

        Swift.print("Run (runAll=\(runAll)): \(promptsToProcess.count)/\(document.project.prompts.count) prompts to process")

        guard !promptsToProcess.isEmpty else {
            statusMessage = "No prompts to process"
            return
        }

        // Calculate total image count
        totalImages = promptsToProcess.reduce(0) { $0 + $1.generateCount }
        currentImageIndex = 0

        statusMessage = "Generating…"

        // Phase 1: Enqueue all requests
        for prompt in promptsToProcess {
            guard !Task.isCancelled else { break }

            guard let promptIndex = document.project.prompts.firstIndex(where: { $0.id == prompt.id }) else {
                continue
            }

            let configJSON = prompt.configurationOverrideJSON ?? document.project.baseConfigurationJSON
            let parsed = ConfigurationMapper.parse(fromJSON: configJSON)
            let hints = buildHints(prompt: prompt, document: document)

            let promptDisplayNumber = (document.project.prompts.firstIndex(where: { $0.id == prompt.id }) ?? 0) + 1

            for i in 0..<prompt.generateCount {
                let name = "Prompt \(promptDisplayNumber) — image \(i + 1)/\(prompt.generateCount)"
                let request = dtQueue.enqueue(
                    prompt: prompt.text,
                    negativePrompt: parsed.negativePrompt,
                    configuration: parsed.configuration,
                    hints: hints,
                    name: name
                )

                requestMappings[request.id] = RequestMapping(
                    promptID: prompt.id,
                    promptIndex: promptIndex,
                    imageNumber: i,
                    promptDisplayNumber: promptDisplayNumber,
                    totalForPrompt: prompt.generateCount,
                    promptText: prompt.text
                )
            }

            completedPerPrompt[prompt.id] = 0
        }

        // Phase 2: Observe progress via Combine
        var progressCancellable: AnyCancellable?
        var innerCancellable: AnyCancellable?

        progressCancellable = dtQueue.$currentProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self else { return }
                innerCancellable?.cancel()
                if let progress {
                    self.generationStage = "Waiting for server…"
                    self.previewImage = nil
                    innerCancellable = progress.objectWillChange
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self, weak progress] _ in
                            guard let self, let progress else { return }
                            self.generationStage = progress.stage.description
                            self.previewImage = progress.previewImage
                        }
                } else {
                    self.generationStage = nil
                    self.previewImage = nil
                }
            }

        defer {
            progressCancellable?.cancel()
            innerCancellable?.cancel()
        }

        for await result in dtQueue.results {
            guard !Task.isCancelled else { break }

            guard let mapping = requestMappings[result.id] else {
                continue
            }

            currentPromptID = mapping.promptID
            statusMessage = "Prompt \(mapping.promptDisplayNumber): image \(mapping.imageNumber + 1)/\(mapping.totalForPrompt)"

            for nsImage in result.images {
                do {
                    try saveGeneratedImage(
                        nsImage,
                        promptID: mapping.promptID,
                        promptIndex: mapping.promptIndex,
                        document: document
                    )
                } catch {
                    Swift.print("Save error for prompt \(mapping.promptID): \(error)")
                }
            }

            currentImageIndex += 1
            completedPerPrompt[mapping.promptID, default: 0] += 1
            requestMappings.removeValue(forKey: result.id)

            // Autosave when all images for a prompt complete
            if completedPerPrompt[mapping.promptID] == mapping.totalForPrompt {
                document.updateChangeCount(.changeDone)
                document.autosave(withImplicitCancellability: false) { error in
                    if let error {
                        Swift.print("Autosave error: \(error)")
                    }
                }
            }

            // Break when all requests are done
            if requestMappings.isEmpty {
                break
            }
        }

        // Report any incomplete mappings as failures
        if !requestMappings.isEmpty {
            let incompleteCount = requestMappings.count
            Swift.print("\(incompleteCount) request(s) did not complete")
        }

        if Task.isCancelled {
            statusMessage = "Generation stopped"
        } else {
            statusMessage = "Generation complete (\(currentImageIndex) images)"
        }
        generationStage = nil
        previewImage = nil
    }

    // MARK: - Helpers

    private func buildHints(prompt: Prompt, document: LoRAForgeDocument) -> [HintProto] {
        var tensors: [TensorAndWeight] = []
        for sourceID in prompt.sourceImageIDs {
            guard let source = document.project.sourceImages.first(where: { $0.id == sourceID }),
                  let url = document.sourceImageURL(for: source),
                  let nsImage = NSImage(contentsOf: url),
                  let tensorData = try? ImageHelpers.imageToDTTensor(nsImage) else {
                continue
            }
            var tw = TensorAndWeight()
            tw.tensor = tensorData
            tw.weight = 1.0
            tensors.append(tw)
        }
        guard !tensors.isEmpty else { return [] }
        var hint = HintProto()
        hint.hintType = "shuffle"
        hint.tensors = tensors
        return [hint]
    }

    private func saveGeneratedImage(
        _ nsImage: NSImage,
        promptID: UUID,
        promptIndex: Int,
        document: LoRAForgeDocument
    ) throws {
        guard let packageURL = document.fileURL else { return }

        let imageID = UUID()
        let filename = "\(imageID.uuidString).png"
        let promptDir = packageURL
            .appendingPathComponent("generated")
            .appendingPathComponent(promptID.uuidString)

        try FileManager.default.createDirectory(at: promptDir, withIntermediateDirectories: true)

        // Convert NSImage → PNG data
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            Swift.print("Failed to convert image to PNG")
            return
        }

        try pngData.write(to: promptDir.appendingPathComponent(filename))

        let generated = GeneratedImage(
            id: imageID,
            filename: filename,
            rank: .candidate,
            caption: nil,
            generatedAt: Date(),
            seed: nil
        )

        document.project.prompts[promptIndex].generatedImages.append(generated)
    }
}
