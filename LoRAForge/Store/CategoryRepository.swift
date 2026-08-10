import Foundation
import SwiftData
import TaggingCore

protocol CategoryRepository {
    func allCategories() throws -> [TagCategory]
    func category(byID id: UUID) throws -> TagCategory?
    func save(_ category: TagCategory) throws
    func delete(categoryID: UUID) throws
    func seedBuiltInsIfNeeded() throws
}

final class SwiftDataCategoryRepository: CategoryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allCategories() throws -> [TagCategory] {
        let descriptor = FetchDescriptor<SDTagCategory>(
            sortBy: [SortDescriptor(\.position)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func category(byID id: UUID) throws -> TagCategory? {
        try fetchSD(byID: id)?.toDomain()
    }

    func save(_ category: TagCategory) throws {
        if let existing = try fetchSD(byID: category.id) {
            existing.name = category.name
            existing.selectModeRaw = category.selectMode == .single ? 0 : 1
            existing.prefix = category.prefix
            existing.position = category.position
            existing.isEnabled = category.isEnabled
            existing.highThreshold = category.highThreshold
            existing.lowThreshold = category.lowThreshold
        } else {
            modelContext.insert(SDTagCategory(from: category))
        }
        try modelContext.save()
    }

    func delete(categoryID: UUID) throws {
        guard let sd = try fetchSD(byID: categoryID) else {
            throw StoreError.categoryNotFound(id: categoryID)
        }
        if sd.isBuiltIn {
            throw StoreError.cannotDeleteBuiltInCategory
        }
        modelContext.delete(sd)
        try modelContext.save()
    }

    func seedBuiltInsIfNeeded() throws {
        let descriptor = FetchDescriptor<SDTagCategory>(
            predicate: #Predicate { $0.isBuiltIn == true }
        )
        let existing = try modelContext.fetch(descriptor)
        if !existing.isEmpty { return }

        for category in BuiltInCategories.all {
            modelContext.insert(SDTagCategory(from: category))
        }
        try modelContext.save()
    }

    // MARK: - Private

    private func fetchSD(byID id: UUID) throws -> SDTagCategory? {
        var descriptor = FetchDescriptor<SDTagCategory>(
            predicate: #Predicate { $0.stableID == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
