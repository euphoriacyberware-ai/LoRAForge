import Foundation
import SwiftData

protocol OllamaProfileRepository {
    func allProfiles() throws -> [OllamaProfile]
    func save(_ profile: OllamaProfile) throws
    func delete(name: String) throws
}

final class SwiftDataOllamaProfileRepository: OllamaProfileRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allProfiles() throws -> [OllamaProfile] {
        let descriptor = FetchDescriptor<SDOllamaProfile>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor).map { sd in
            OllamaProfile(
                name: sd.name,
                endpoint: sd.endpoint,
                model: sd.model,
                instruction: sd.instruction
            )
        }
    }

    func save(_ profile: OllamaProfile) throws {
        let profileName = profile.name
        var descriptor = FetchDescriptor<SDOllamaProfile>(
            predicate: #Predicate { $0.name == profileName }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.endpoint = profile.endpoint
            existing.model = profile.model
            existing.instruction = profile.instruction
        } else {
            modelContext.insert(SDOllamaProfile(
                name: profile.name,
                endpoint: profile.endpoint,
                model: profile.model,
                instruction: profile.instruction
            ))
        }
        try modelContext.save()
    }

    func delete(name: String) throws {
        var descriptor = FetchDescriptor<SDOllamaProfile>(
            predicate: #Predicate { $0.name == name }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }
}
