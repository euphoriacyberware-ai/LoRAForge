import Foundation
import SwiftData

@Model
final class SDOllamaProfile {
    var id: UUID
    var name: String
    var endpoint: String
    var model: String
    var instruction: String

    init(name: String, endpoint: String, model: String, instruction: String) {
        self.id = UUID()
        self.name = name
        self.endpoint = endpoint
        self.model = model
        self.instruction = instruction
    }
}

@Observable
final class OllamaRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allProfiles() throws -> [SDOllamaProfile] {
        let descriptor = FetchDescriptor<SDOllamaProfile>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func addProfile(name: String, endpoint: String, model: String, instruction: String) throws -> SDOllamaProfile {
        let profile = SDOllamaProfile(
            name: name, endpoint: endpoint, model: model, instruction: instruction
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
