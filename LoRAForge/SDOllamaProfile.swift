import Foundation
import SwiftData

/// The API a captioning profile talks to.
nonisolated enum CaptionAPIType: String, CaseIterable, Identifiable, Sendable {
    /// Ollama's own `/api/generate`.
    case ollama
    /// OpenAI-compatible `/chat/completions`: Local Code, LM Studio and similar servers.
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: "Ollama"
        case .openAICompatible: "OpenAI-compatible (Local Code, LM Studio…)"
        }
    }

    var shortName: String {
        switch self {
        case .ollama: "Ollama"
        case .openAICompatible: "OpenAI-compatible"
        }
    }

    /// The endpoint a new profile of this type starts with.
    var defaultEndpoint: String {
        switch self {
        case .ollama: "http://localhost:11434"
        case .openAICompatible: "http://127.0.0.1:11435/v1"
        }
    }
}

/// A named captioning profile: where to send the image, which model, and the instruction.
///
/// Named `SDOllamaProfile` from before profiles had an API type; renaming the model would
/// change the store schema. New properties need default values so existing stores migrate:
/// the app deletes a store it can't open, and that store also holds the tag library.
@Model
final class SDOllamaProfile {
    var id: UUID
    var name: String
    var endpoint: String
    var model: String
    var instruction: String
    /// A `CaptionAPIType` raw value. Profiles made before API types existed are Ollama.
    var apiType: String = CaptionAPIType.ollama.rawValue
    /// OpenAI-compatible only: ask the server not to reason before answering.
    var disablesReasoning: Bool = true

    init(name: String, endpoint: String, model: String, instruction: String,
         apiType: CaptionAPIType = .ollama, disablesReasoning: Bool = true) {
        self.id = UUID()
        self.name = name
        self.endpoint = endpoint
        self.model = model
        self.instruction = instruction
        self.apiType = apiType.rawValue
        self.disablesReasoning = disablesReasoning
    }

    var api: CaptionAPIType {
        get { CaptionAPIType(rawValue: apiType) ?? .ollama }
        set { apiType = newValue.rawValue }
    }
}

@Observable
final class OllamaRepository {
    @ObservationIgnored private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allProfiles() throws -> [SDOllamaProfile] {
        let descriptor = FetchDescriptor<SDOllamaProfile>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func addProfile(name: String, endpoint: String, model: String, instruction: String,
                    apiType: CaptionAPIType = .ollama, disablesReasoning: Bool = true) throws -> SDOllamaProfile {
        let profile = SDOllamaProfile(
            name: name, endpoint: endpoint, model: model, instruction: instruction,
            apiType: apiType, disablesReasoning: disablesReasoning
        )
        modelContext.insert(profile)
        try modelContext.save()
        return profile
    }

    func updateProfile(_ profile: SDOllamaProfile) throws {
        try modelContext.save()
    }

    func deleteProfile(_ profile: SDOllamaProfile) throws {
        modelContext.delete(profile)
        try modelContext.save()
    }
}
