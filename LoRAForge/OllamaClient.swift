import Foundation

enum OllamaClient {

    struct Request: Encodable {
        let model: String
        let prompt: String
        let images: [String] // base64-encoded
        let stream: Bool
    }

    struct Response: Decodable {
        let response: String
    }

    static func generate(
        endpoint: String,
        model: String,
        instruction: String,
        imageData: Data
    ) async throws -> String {
        let base64 = imageData.base64EncodedString()
        let body = Request(
            model: model,
            prompt: instruction,
            images: [base64],
            stream: false
        )

        let urlString = endpoint.hasSuffix("/")
            ? "\(endpoint)api/generate"
            : "\(endpoint)/api/generate"
        guard let url = URL(string: urlString) else {
            throw OllamaError.invalidEndpoint(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OllamaError.serverError(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum OllamaError: Error, LocalizedError {
    case invalidEndpoint(String)
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let ep): return "Invalid Ollama endpoint: \(ep)"
        case .invalidResponse: return "Invalid response from Ollama server."
        case .serverError(let code, let body): return "Ollama error \(code): \(body)"
        }
    }
}
