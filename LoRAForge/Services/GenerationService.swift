import Foundation
import SwiftUI
import AppKit
import Combine
import DrawThingsClient
import GRPC

@MainActor
final class GenerationService: ObservableObject {

    @Published var isRunning = false
    @Published var currentPromptID: UUID?
    @Published var currentImageIndex = 0
    @Published var totalImages = 0
    @Published var statusMessage = ""
    @Published var generationStage: String?

    private var generationTask: Task<Void, Never>?
    private var client: DrawThingsClient?

    var progressFraction: Double {
        guard totalImages > 0 else { return 0 }
        return Double(currentImageIndex) / Double(totalImages)
    }

    // MARK: - Run

    func run(document: LoRAForgeDocument, runAll: Bool) {
        guard !isRunning else { return }

        generationTask = Task {
            await performGeneration(document: document, runAll: runAll)
        }
    }

    // MARK: - Stop

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        isRunning = false
        currentPromptID = nil
        generationStage = nil
        statusMessage = "Stopped"
    }

    // MARK: - Generation Loop

    private func performGeneration(document: LoRAForgeDocument, runAll: Bool) async {
        isRunning = true
        statusMessage = ""
        generationStage = nil
        currentImageIndex = 0

        defer {
            isRunning = false
            currentPromptID = nil
            generationStage = nil
            client = nil
        }

        // Resolve connection
        guard let connectionID = document.project.generationConnectionID,
              let connection = ConnectionManager.shared.connection(for: connectionID) else {
            statusMessage = "No server selected"
            return
        }

        // Create client
        let dtClient: DrawThingsClient
        do {
            dtClient = try DrawThingsClient(address: "\(connection.host):\(connection.port)")
        } catch {
            statusMessage = "Failed to create client: \(error.localizedDescription)"
            return
        }
        self.client = dtClient

        // Connect
        DrawThingsClientLogger.minimumLevel = .debug
        statusMessage = "Connecting to \(connection.name)…"
        Swift.print("Attempting gRPC connection to \(connection.host):\(connection.port) (plaintext)…")
        await dtClient.connect()

        guard dtClient.isConnected else {
            let error = dtClient.lastError
            let errorDetail = error?.localizedDescription ?? "Unknown error"
            let fullError = error.map { String(describing: $0) } ?? "nil"
            Swift.print("DrawThingsClient connection failed: \(fullError)")
            if let poolError = error as? GRPCConnectionPoolError {
                Swift.print("  Pool error code: \(poolError.code)")
                Swift.print("  Underlying error: \(String(describing: poolError.underlyingError))")
            }
            statusMessage = "Failed to connect: \(errorDetail)"
            return
        }

        // Determine prompts to process
        let promptsToProcess: [Prompt]
        if runAll {
            promptsToProcess = document.project.prompts
        } else {
            promptsToProcess = document.project.prompts.filter { prompt in
                !prompt.generatedImages.contains(where: { $0.rank == .final_ })
            }
        }

        guard !promptsToProcess.isEmpty else {
            statusMessage = "No prompts to process"
            return
        }

        // Calculate total image count
        totalImages = promptsToProcess.reduce(0) { $0 + $1.generateCount }
        currentImageIndex = 0

        statusMessage = "Generating…"

        for prompt in promptsToProcess {
            guard !Task.isCancelled else { break }

            currentPromptID = prompt.id

            guard let promptIndex = document.project.prompts.firstIndex(where: { $0.id == prompt.id }) else {
                continue
            }

            // Parse configuration
            let configJSON = prompt.configurationOverrideJSON ?? document.project.baseConfigurationJSON
            let parsed = ConfigurationMapper.parse(fromJSON: configJSON)

            // Load first source image (if any)
            let sourceImage: NSImage? = loadSourceImage(prompt: prompt, document: document)

            // Generate images one at a time
            for i in 0..<prompt.generateCount {
                guard !Task.isCancelled else { break }

                let promptNumber = (document.project.prompts.firstIndex(where: { $0.id == prompt.id }) ?? 0) + 1
                statusMessage = "Prompt \(promptNumber): image \(i + 1)/\(prompt.generateCount)"

                do {
                    let images = try await dtClient.generateImage(
                        prompt: prompt.text,
                        negativePrompt: parsed.negativePrompt,
                        configuration: parsed.configuration,
                        image: sourceImage
                    )

                    // Save each returned image
                    for nsImage in images {
                        try saveGeneratedImage(
                            nsImage,
                            promptID: prompt.id,
                            promptIndex: promptIndex,
                            document: document
                        )
                    }

                    currentImageIndex += 1

                    // Update stage from client progress
                    if let progress = dtClient.currentProgress {
                        generationStage = progress.stage.description
                    }

                } catch {
                    if Task.isCancelled { break }
                    Swift.print("Generation error for prompt \(prompt.id): \(error)")
                    statusMessage = "Error: \(error.localizedDescription)"
                    // Continue to next image rather than aborting the whole run
                    currentImageIndex += 1
                }
            }

            // Persist after each prompt completes
            document.updateChangeCount(.changeDone)
            document.autosave(withImplicitCancellability: false) { error in
                if let error {
                    Swift.print("Autosave error: \(error)")
                }
            }
        }

        if Task.isCancelled {
            statusMessage = "Generation stopped"
        } else {
            statusMessage = "Generation complete (\(currentImageIndex) images)"
        }
        generationStage = nil
    }

    // MARK: - Helpers

    private func loadSourceImage(prompt: Prompt, document: LoRAForgeDocument) -> NSImage? {
        guard let firstImageID = prompt.sourceImageIDs.first,
              let source = document.project.sourceImages.first(where: { $0.id == firstImageID }),
              let url = document.sourceImageURL(for: source) else {
            return nil
        }
        return NSImage(contentsOf: url)
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
