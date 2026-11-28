import Testing
import Foundation
import ImageIO
@testable import LoRAForge

@MainActor
struct CaptionClientTests {

    private func settings(_ api: CaptionAPIType, endpoint: String = "http://127.0.0.1:11435/v1",
                          model: String = "", reasoningOff: Bool = true) -> CaptionRequestSettings {
        CaptionRequestSettings(api: api, endpoint: endpoint, model: model, disablesReasoning: reasoningOff)
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Trigger

    @Test func triggerIsSubstituted() throws {
        let text = try CaptionInstruction.resolve("TRIGGER: {trigger}\nStart with {trigger}.", trigger: "KayleeQX")
        #expect(text == "TRIGGER: KayleeQX\nStart with KayleeQX.")
    }

    @Test func missingTriggerThrowsOnlyWhenUsed() throws {
        #expect(throws: CaptionError.missingTrigger) {
            try CaptionInstruction.resolve("Start with {trigger}.", trigger: nil)
        }
        #expect(throws: CaptionError.missingTrigger) {
            try CaptionInstruction.resolve("Start with {trigger}.", trigger: "")
        }
        #expect(try CaptionInstruction.resolve("Describe this image.", trigger: nil) == "Describe this image.")
    }

    // MARK: - URLs

    @Test func endpointJoinsWithOrWithoutSlash() throws {
        let a = try CaptionClient.url("http://127.0.0.1:11435/v1", appending: "chat/completions", api: .openAICompatible)
        let b = try CaptionClient.url("http://127.0.0.1:11435/v1/", appending: "chat/completions", api: .openAICompatible)
        #expect(a.absoluteString == "http://127.0.0.1:11435/v1/chat/completions")
        #expect(a == b)
    }

    @Test func invalidEndpointThrows() {
        #expect(throws: CaptionError.self) {
            try CaptionClient.url("not a url", appending: "api/generate", api: .ollama)
        }
    }

    // MARK: - OpenAI-compatible

    @Test func chatRequestShape() throws {
        let request = try CaptionClient.chatRequest(
            settings: settings(.openAICompatible), instruction: "Caption rules",
            image: Data([1, 2, 3]), mimeType: "image/jpeg"
        )
        #expect(request.url?.absoluteString == "http://127.0.0.1:11435/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        let body = try json(request)
        #expect(body["reasoning_effort"] as? String == "none")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == "Caption rules")
        let parts = try #require(messages[1]["content"] as? [[String: Any]])
        let imageURL = try #require((parts[1]["image_url"] as? [String: Any])?["url"] as? String)
        #expect(imageURL == "data:image/jpeg;base64,AQID")
    }

    @Test func reasoningLeftOnOmitsTheField() throws {
        let request = try CaptionClient.chatRequest(
            settings: settings(.openAICompatible, reasoningOff: false), instruction: "x",
            image: Data([1]), mimeType: "image/png"
        )
        #expect(try json(request)["reasoning_effort"] == nil)
    }

    @Test func chatResponseUsesContentNotReasoning() throws {
        let data = Data(#"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","reasoning_content":"thinking...","content":"  KayleeQX, a woman.  "}}]}"#.utf8)
        #expect(try CaptionClient.parseChat(data) == "KayleeQX, a woman.")
    }

    @Test func emptyContentAfterLengthIsTheReasoningError() {
        let data = Data(#"{"choices":[{"finish_reason":"length","message":{"reasoning_content":"still thinking","content":""}}]}"#.utf8)
        #expect(throws: CaptionError.ranOutWhileReasoning) { try CaptionClient.parseChat(data) }
    }

    @Test func malformedChatResponseThrows() {
        #expect(throws: CaptionError.invalidResponse(.openAICompatible)) {
            try CaptionClient.parseChat(Data("nope".utf8))
        }
    }

    // MARK: - Ollama

    @Test func ollamaRequestIsUnchanged() throws {
        let request = try CaptionClient.ollamaRequest(
            settings: settings(.ollama, endpoint: "http://localhost:11434", model: "llava"),
            instruction: "Describe this image.", imageData: Data([1, 2, 3])
        )
        #expect(request.url?.absoluteString == "http://localhost:11434/api/generate")
        let body = try json(request)
        #expect(body["model"] as? String == "llava")
        #expect(body["prompt"] as? String == "Describe this image.")
        #expect(body["images"] as? [String] == ["AQID"])
        #expect(body["stream"] as? Bool == false)
        #expect(try CaptionClient.parseOllama(Data(#"{"response":" A caption. "}"#.utf8)) == "A caption.")
    }

    // MARK: - Image

    @Test func downscaleLimitsTheLongSide() throws {
        // A 2048×1024 PNG made with ImageIO.
        let width = 2048, height = 1024
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let png = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        let result = try #require(CaptionClient.downscaled(png as Data, maxPixelSize: 1024))
        #expect(result.mimeType == "image/jpeg")
        let source = try #require(CGImageSourceCreateWithData(result.data as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 1024)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 512)
    }
}
