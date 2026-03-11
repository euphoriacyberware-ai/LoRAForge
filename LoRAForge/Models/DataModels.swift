import Foundation

// MARK: - Project (project.json root)

struct Project: Codable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var generationConnectionID: UUID?
    var captionConnectionID: UUID?
    var baseConfigurationJSON: String
    var sourceImages: [SourceImage]
    var prompts: [Prompt]
}

// MARK: - Source Image

struct SourceImage: Codable, Identifiable, Sendable {
    var id: UUID
    var filename: String
    var label: String?
}

// MARK: - Prompt

struct Prompt: Codable, Identifiable, Sendable {
    var id: UUID
    var order: Int
    var text: String
    var sourceImageIDs: [UUID]
    var generateCount: Int
    var configurationOverrideJSON: String?
    var generatedImages: [GeneratedImage]
}

// MARK: - Generated Image

struct GeneratedImage: Codable, Identifiable, Sendable {
    var id: UUID
    var filename: String
    var rank: ImageRank
    var caption: String?
    var generatedAt: Date
    var seed: Int?
}

// MARK: - Image Rank

enum ImageRank: String, Codable, CaseIterable, Sendable {
    case candidate
    case shortlisted
    case final_
    case discarded
}

// MARK: - Server Connection (stored in App Support)

struct ServerConnection: Codable, Identifiable {
    var id: UUID
    var name: String
    var type: ConnectionType
    var host: String
    var port: Int
    var modelName: String?
    var captionPrompt: String?
}

// MARK: - Connection Type

enum ConnectionType: String, Codable {
    case drawThings
    case ollama
}

// MARK: - Template (stored in App Support)

struct Template: Codable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var prompts: [TemplatePrompt]
}

// MARK: - Template Prompt

struct TemplatePrompt: Codable, Identifiable {
    var id: UUID
    var order: Int
    var text: String
    var sourceSlotIndex: Int?
    var generateCount: Int
}
