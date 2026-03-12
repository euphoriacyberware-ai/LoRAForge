import Foundation
import AppKit
import Combine

@MainActor
final class CaptionService: ObservableObject {

    @Published var captioningImageIDs: Set<UUID> = []

    func caption(
        imageID: UUID,
        imageURL: URL,
        connection: ServerConnection,
        document: LoRAForgeDocument,
        promptIndex: Int,
        imageIndex: Int
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
                document.project.prompts[promptIndex].generatedImages[imageIndex].caption = caption
                document.updateChangeCount(.changeDone)
            } catch {
                if !Task.isCancelled {
                    Swift.print("Caption error for \(imageID): \(error)")
                }
            }
        }
    }

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
