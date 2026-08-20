import Foundation
import SwiftData

@Model
final class SDGenerationPreset {
    var id: UUID
    var name: String
    var configJSON: String
    var createdAt: Date

    init(name: String, configJSON: String) {
        self.id = UUID()
        self.name = name
        self.configJSON = configJSON
        self.createdAt = Date()
    }
}

@Observable
final class GenerationPresetRepository {
    @ObservationIgnored private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allPresets() throws -> [SDGenerationPreset] {
        let descriptor = FetchDescriptor<SDGenerationPreset>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func addPreset(name: String, configJSON: String) throws -> SDGenerationPreset {
        let preset = SDGenerationPreset(name: name, configJSON: configJSON)
        modelContext.insert(preset)
        try modelContext.save()
        return preset
    }

    func updatePreset(_ preset: SDGenerationPreset) throws {
        try modelContext.save()
    }

    func deletePreset(_ preset: SDGenerationPreset) throws {
        modelContext.delete(preset)
        try modelContext.save()
    }
}
