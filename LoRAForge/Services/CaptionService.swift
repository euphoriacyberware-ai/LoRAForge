import Foundation
import AppKit
import Combine

@MainActor
final class CaptionService: ObservableObject {

    @Published var captioningImageIDs: Set<UUID> = []
    @Published var isBulkCaptioning = false
    @Published var bulkProgress = 0
    @Published var bulkTotal = 0
    @Published var bulkStatusMessage = ""

    private var bulkTask: Task<Void, Never>?

    // MARK: - Single Image Caption

    func caption(
        imageID: UUID,
        imageURL: URL,
        connection: ServerConnection,
        document: LoRAForgeDocument,
        promptID: UUID
    ) {
        guard !captioningImageIDs.contains(imageID) else { return }
        captioningImageIDs.insert(imageID)

        Task {
            defer { captioningImageIDs.remove(imageID) }

            do {
                let caption = try await requestCaption(
                    imageURL: imageURL,
                    connection: connection
                )
                guard let pIdx = document.project.prompts.firstIndex(where: { $0.id == promptID }),
                      let iIdx = document.project.prompts[pIdx].generatedImages.firstIndex(where: { $0.id == imageID }) else {
                    return
                }
                document.project.prompts[pIdx].generatedImages[iIdx].caption = caption
                document.updateChangeCount(.changeDone)
            } catch {
                if !Task.isCancelled {
                    Swift.print("Caption error for \(imageID): \(error)")
                }
            }
        }
    }

    // MARK: - Bulk Caption All Uncaptioned

    func captionAll(document: LoRAForgeDocument) {
        guard !isBulkCaptioning else { return }
        guard let connID = document.project.captionConnectionID,
              let connection = ConnectionManager.shared.connection(for: connID) else {
            bulkStatusMessage = "No caption server selected"
            return
        }

        bulkTask = Task {
            await performBulkCaption(document: document, connection: connection)
        }
    }

    func stopBulkCaption() {
        bulkTask?.cancel()
        bulkTask = nil
        isBulkCaptioning = false
        bulkStatusMessage = "Captioning stopped"
    }

    private func performBulkCaption(document: LoRAForgeDocument, connection: ServerConnection) async {
        isBulkCaptioning = true
        bulkProgress = 0
        bulkStatusMessage = ""

        defer {
            isBulkCaptioning = false
            bulkTask = nil
        }

        // Collect all uncaptioned, non-discarded images by ID
        var targets: [(promptID: UUID, imageID: UUID)] = []
        for prompt in document.project.prompts {
            for image in prompt.generatedImages {
                if image.rank != .discarded && image.caption == nil {
                    targets.append((prompt.id, image.id))
                }
            }
        }

        guard !targets.isEmpty else {
            bulkStatusMessage = "No uncaptioned images"
            return
        }

        bulkTotal = targets.count

        for (index, target) in targets.enumerated() {
            guard !Task.isCancelled else { break }

            bulkProgress = index + 1
            bulkStatusMessage = "Captioning \(bulkProgress) / \(bulkTotal)"

            // Re-verify the image still exists and needs captioning
            guard let pIdx = document.project.prompts.firstIndex(where: { $0.id == target.promptID }),
                  let iIdx = document.project.prompts[pIdx].generatedImages.firstIndex(where: { $0.id == target.imageID }),
                  document.project.prompts[pIdx].generatedImages[iIdx].caption == nil else {
                continue
            }

            let image = document.project.prompts[pIdx].generatedImages[iIdx]
            guard let url = document.generatedImageURL(promptID: target.promptID, image: image) else {
                continue
            }

            do {
                let caption = try await requestCaption(imageURL: url, connection: connection)
                // Re-resolve indices in case array changed during async call
                if let pIdx2 = document.project.prompts.firstIndex(where: { $0.id == target.promptID }),
                   let iIdx2 = document.project.prompts[pIdx2].generatedImages.firstIndex(where: { $0.id == target.imageID }) {
                    document.project.prompts[pIdx2].generatedImages[iIdx2].caption = caption
                    document.updateChangeCount(.changeDone)
                }

                // Autosave periodically
                if bulkProgress % 5 == 0 || bulkProgress == bulkTotal {
                    document.autosave(withImplicitCancellability: false) { _ in }
                }
            } catch {
                if Task.isCancelled { break }
                Swift.print("Bulk caption error for image \(target.imageID): \(error)")
            }
        }

        if Task.isCancelled {
            bulkStatusMessage = "Captioning stopped at \(bulkProgress) / \(bulkTotal)"
        } else {
            bulkStatusMessage = "Captioning complete (\(bulkTotal) images)"
        }
    }

    // MARK: - Ollama API

    private func requestCaption(
        imageURL: URL,
        connection: ServerConnection
    ) async throws -> String {
        guard let imageData = try? Data(contentsOf: imageURL) else {
            throw CaptionError.imageNotFound
        }

        let base64Image = imageData.base64EncodedString()
        let model = connection.modelName ?? "llava"
        let prompt = connection.captionPrompt ?? "Describe this image in detail for LoRA training captioning:"

        let requestBody: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "images": [base64Image],
            "stream": false
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        let url = URL(string: "http://\(connection.host):\(connection.port)/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CaptionError.serverError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let caption = json["response"] as? String else {
            throw CaptionError.invalidResponse
        }

        return caption.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CaptionError: LocalizedError {
        case imageNotFound
        case serverError
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .imageNotFound: "Image file not found"
            case .serverError: "Server returned an error"
            case .invalidResponse: "Invalid response from server"
            }
        }
    }
}
