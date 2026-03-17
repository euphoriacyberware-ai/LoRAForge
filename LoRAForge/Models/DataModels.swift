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

// MARK: - Configuration Preset (stored in App Support)

struct ConfigurationPreset: Codable, Identifiable {
    var id: UUID
    var name: String
    var json: String
    var createdAt: Date
}

// MARK: - Template (stored in App Support)

struct Template: Codable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var prompts: [TemplatePrompt]
}

// MARK: - Template Export Envelope

struct TemplateExportEnvelope: Codable {
    static let currentVersion = 1
    var version: Int
    var template: Template

    init(version: Int, template: Template) {
        self.version = version
        self.template = template
    }

    // Custom coding to exclude UUIDs from the exported JSON

    private enum CodingKeys: String, CodingKey {
        case version, template
    }

    private enum TemplateCodingKeys: String, CodingKey {
        case name, createdAt, prompts
    }

    private enum PromptCodingKeys: String, CodingKey {
        case order, text, sourceSlotIndex, generateCount
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        var templateContainer = container.nestedContainer(keyedBy: TemplateCodingKeys.self, forKey: .template)
        try templateContainer.encode(template.name, forKey: .name)
        try templateContainer.encode(template.createdAt, forKey: .createdAt)
        var promptsContainer = templateContainer.nestedUnkeyedContainer(forKey: .prompts)
        for prompt in template.prompts {
            var promptContainer = promptsContainer.nestedContainer(keyedBy: PromptCodingKeys.self)
            try promptContainer.encode(prompt.order, forKey: .order)
            try promptContainer.encode(prompt.text, forKey: .text)
            try promptContainer.encodeIfPresent(prompt.sourceSlotIndex, forKey: .sourceSlotIndex)
            try promptContainer.encode(prompt.generateCount, forKey: .generateCount)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let templateContainer = try container.nestedContainer(keyedBy: TemplateCodingKeys.self, forKey: .template)
        let name = try templateContainer.decode(String.self, forKey: .name)
        let createdAt = try templateContainer.decode(Date.self, forKey: .createdAt)
        var promptsContainer = try templateContainer.nestedUnkeyedContainer(forKey: .prompts)
        var prompts: [TemplatePrompt] = []
        while !promptsContainer.isAtEnd {
            let promptContainer = try promptsContainer.nestedContainer(keyedBy: PromptCodingKeys.self)
            prompts.append(TemplatePrompt(
                id: UUID(),
                order: try promptContainer.decode(Int.self, forKey: .order),
                text: try promptContainer.decode(String.self, forKey: .text),
                sourceSlotIndex: try promptContainer.decodeIfPresent(Int.self, forKey: .sourceSlotIndex),
                generateCount: try promptContainer.decode(Int.self, forKey: .generateCount)
            ))
        }
        template = Template(id: UUID(), name: name, createdAt: createdAt, prompts: prompts)
    }
}

// MARK: - Template Prompt

struct TemplatePrompt: Codable, Identifiable {
    var id: UUID
    var order: Int
    var text: String
    var sourceSlotIndex: Int?
    var generateCount: Int
}
