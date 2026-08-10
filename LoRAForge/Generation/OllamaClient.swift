import Foundation

struct OllamaProfile: Sendable, Identifiable {
    let id: UUID
    var name: String
    var endpoint: String
    var model: String
    var instruction: String

    init(id: UUID = UUID(), name: String, endpoint: String = "http://localhost:11434",
         model: String = "llava", instruction: String = "") {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.model = model
        self.instruction = instruction
    }
}

struct OllamaClient: Sendable {

    /// Send an image to an Ollama vision model and get a caption back.
    func caption(
        imageData: Data,
        profile: OllamaProfile
    ) async throws -> String {
        let base64Image = imageData.base64EncodedString()

        let url = URL(string: "\(profile.endpoint)/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": profile.model,
            "prompt": profile.instruction,
            "images": [base64Image],
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OllamaError.serverError(statusCode: httpResponse.statusCode, body: body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw OllamaError.invalidJSON
        }

        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum OllamaError: Error, LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int, body: String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from Ollama server."
        case .serverError(let code, let body): "Ollama error \(code): \(body.prefix(200))"
        case .invalidJSON: "Could not parse Ollama response."
        }
    }
}
