import Foundation
import SwiftData

struct KnownProject: Sendable {
    let projectID: UUID
    let name: String
    let lastOpened: Date
}

protocol KnownProjectsRepository {
    func allProjects() throws -> [KnownProject]
    func register(projectID: UUID, name: String) throws
    func remove(projectID: UUID) throws
}

final class SwiftDataKnownProjectsRepository: KnownProjectsRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allProjects() throws -> [KnownProject] {
        let descriptor = FetchDescriptor<SDKnownProject>(
            sortBy: [SortDescriptor(\.lastOpened, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map {
            KnownProject(projectID: $0.projectID, name: $0.name, lastOpened: $0.lastOpened)
        }
    }

    func register(projectID: UUID, name: String) throws {
        var descriptor = FetchDescriptor<SDKnownProject>(
            predicate: #Predicate { $0.projectID == projectID }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.name = name
            existing.lastOpened = Date()
        } else {
            modelContext.insert(SDKnownProject(projectID: projectID, name: name))
        }
        try modelContext.save()
    }

    func remove(projectID: UUID) throws {
        var descriptor = FetchDescriptor<SDKnownProject>(
            predicate: #Predicate { $0.projectID == projectID }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }
}
