import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The settings a caption request needs, copied out of a profile so requests can be built
/// and tested without SwiftData.
nonisolated struct CaptionRequestSettings: Sendable {
    var api: CaptionAPIType
    var endpoint: String
    var model: String
    var disablesReasoning: Bool
}

/// Sends an image and an instruction to a captioning server and returns the caption text.
nonisolated enum CaptionClient {

    static func caption(settings: CaptionRequestSettings, instruction: String, imageData: Data) async throws -> String {
        let request: URLRequest
        switch settings.api {
        case .ollama:
            request = try ollamaRequest(settings: settings, instruction: instruction, imageData: imageData)
        case .openAICompatible:
            let image = downscaled(imageData, maxPixelSize: 1024) ?? (imageData, "image/png")
            request = try chatRequest(settings: settings, instruction: instruction, image: image.data, mimeType: image.mimeType)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CaptionError.invalidResponse(settings.api)
        }
        guard http.statusCode == 200 else {
            throw CaptionError.serverError(settings.api, http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        switch settings.api {
        case .ollama: return try parseOllama(data)
        case .openAICompatible: return try parseChat(data)
        }
    }

    // MARK: - URLs

    /// `base` joined with `path`, tolerating a trailing slash on the base.
    static func url(_ base: String, appending path: String, api: CaptionAPIType) throws -> URL {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = trimmed.hasSuffix("/") ? trimmed + path : trimmed + "/" + path
        guard let url = URL(string: joined), url.scheme != nil, url.host() != nil else {
            throw CaptionError.invalidEndpoint(api, base)
        }
        return url
    }

    // MARK: - Ollama (/api/generate)

    struct OllamaBody: Encodable {
        let model: String
        let prompt: String
        let images: [String]
        let stream: Bool
    }

    static func ollamaRequest(settings: CaptionRequestSettings, instruction: String, imageData: Data) throws -> URLRequest {
        var request = URLRequest(url: try url(settings.endpoint, appending: "api/generate", api: .ollama))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaBody(
            model: settings.model, prompt: instruction,
            images: [imageData.base64EncodedString()], stream: false
        ))
        request.timeoutInterval = 120
        return request
    }

    static func parseOllama(_ data: Data) throws -> String {
        struct Response: Decodable { let response: String }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw CaptionError.invalidResponse(.ollama)
        }
        return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OpenAI-compatible (/chat/completions)

    /// The instruction is the system message; the image goes in the user message as a data URL.
    static func chatBody(settings: CaptionRequestSettings, instruction: String, image: Data, mimeType: String) -> [String: Any] {
        var body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 2000,
            "stream": false,
            "messages": [
                ["role": "system", "content": instruction],
                ["role": "user", "content": [
                    ["type": "text", "text": "Caption this image."],
                    ["type": "image_url", "image_url": ["url": "data:\(mimeType);base64,\(image.base64EncodedString())"]],
                ]],
            ],
        ]
        if settings.disablesReasoning {
            body["reasoning_effort"] = "none"
        }
        return body
    }

    static func chatRequest(settings: CaptionRequestSettings, instruction: String, image: Data, mimeType: String) throws -> URLRequest {
        var request = URLRequest(url: try url(settings.endpoint, appending: "chat/completions", api: .openAICompatible))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: chatBody(
            settings: settings, instruction: instruction, image: image, mimeType: mimeType
        ))
        // Local Code answers one request at a time, and the user's own chats go first.
        request.timeoutInterval = 300
        return request
    }

    /// The answer from `choices[0].message.content`; reasoning text is ignored.
    static func parseChat(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
                let finish_reason: String?
            }
            let choices: [Choice]
        }
        guard let choice = (try? JSONDecoder().decode(Response.self, from: data))?.choices.first else {
            throw CaptionError.invalidResponse(.openAICompatible)
        }
        let text = (choice.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw choice.finish_reason == "length" ? CaptionError.ranOutWhileReasoning : CaptionError.emptyCaption
        }
        return text
    }

    // MARK: - Image

    /// The image scaled so its long side is at most `maxPixelSize`, as JPEG. Nil when the data
    /// can't be read as an image.
    static func downscaled(_ data: Data, maxPixelSize: Int) -> (data: Data, mimeType: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (output as Data, "image/jpeg")
    }
}

nonisolated enum CaptionError: Error, LocalizedError, Equatable {
    case invalidEndpoint(CaptionAPIType, String)
    case invalidResponse(CaptionAPIType)
    case serverError(CaptionAPIType, Int, String)
    case ranOutWhileReasoning
    case emptyCaption
    case missingTrigger

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let api, let endpoint):
            "Invalid \(api.shortName) endpoint: \(endpoint)"
        case .invalidResponse(let api):
            "The \(api.shortName) server sent a response LoRAForge couldn't read."
        case .serverError(let api, let code, let body):
            "\(api.shortName) server error \(code): \(body)"
        case .ranOutWhileReasoning:
            "The model ran out of tokens while reasoning and returned no caption. Turn on \"Turn off reasoning\" in the profile."
        case .emptyCaption:
            "The model returned an empty caption."
        case .missingTrigger:
            "Assign a Subject tag first — this profile's instruction uses {trigger}."
        }
    }
}

/// Fills placeholders in a profile's instruction before it is sent.
nonisolated enum CaptionInstruction {
    static let triggerPlaceholder = "{trigger}"

    /// Replaces `{trigger}` with the entry's trigger. Throws when the instruction uses the
    /// placeholder and the entry has no trigger.
    static func resolve(_ text: String, trigger: String?) throws -> String {
        guard text.contains(triggerPlaceholder) else { return text }
        guard let trigger, !trigger.isEmpty else { throw CaptionError.missingTrigger }
        return text.replacingOccurrences(of: triggerPlaceholder, with: trigger)
    }
}
