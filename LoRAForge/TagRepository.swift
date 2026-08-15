import Foundation
import SwiftData
import TaggingCore

@Observable
final class TagRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Seeding

    func seedBuiltInCategoriesIfNeeded() throws {
        let descriptor = FetchDescriptor<SDCategory>(
            predicate: #Predicate<SDCategory> { $0.isBuiltIn }
        )
        let existing = try modelContext.fetch(descriptor)
        guard existing.isEmpty else { return }

        for category in BuiltInCategory.defaultCategories {
            modelContext.insert(SDCategory(from: category))
        }
        try modelContext.save()
    }

    // MARK: - Categories

    func allCategories() throws -> [TagCategory] {
        let descriptor = FetchDescriptor<SDCategory>(
            sortBy: [SortDescriptor(\.position)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func category(id: UUID) throws -> TagCategory? {
        let catID = id
        var descriptor = FetchDescriptor<SDCategory>(
            predicate: #Predicate<SDCategory> { $0.id == catID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.toDomain()
    }

    func updateCategory(_ category: TagCategory) throws {
        let catID = category.id
        var descriptor = FetchDescriptor<SDCategory>(
            predicate: #Predicate<SDCategory> { $0.id == catID }
        )
        descriptor.fetchLimit = 1
        guard let model = try modelContext.fetch(descriptor).first else { return }
        model.update(from: category)
        try modelContext.save()
    }

    func addCategory(name: String, selectMode: TagCategory.SelectMode, prefix: String?) throws -> TagCategory {
        let maxPosition = (try allCategories().map(\.position).max() ?? -1) + 1
        let category = TagCategory(
            name: name, selectMode: selectMode, prefix: prefix,
            position: maxPosition, isBuiltIn: false
        )
        modelContext.insert(SDCategory(from: category))
        try modelContext.save()
        return category
    }

    func deleteCategory(id: UUID) throws {
        let catID = id
        var descriptor = FetchDescriptor<SDCategory>(
            predicate: #Predicate<SDCategory> { $0.id == catID }
        )
        descriptor.fetchLimit = 1
        guard let model = try modelContext.fetch(descriptor).first else { return }
        if model.isBuiltIn {
            throw TagRepositoryError.cannotDeleteBuiltIn(model.name)
        }
        modelContext.delete(model) // cascade deletes tags
        try modelContext.save()
    }

    func reorderCategories(_ orderedIDs: [UUID]) throws {
        for (index, catID) in orderedIDs.enumerated() {
            let id = catID
            var descriptor = FetchDescriptor<SDCategory>(
                predicate: #Predicate<SDCategory> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                model.position = index
            }
        }
        try modelContext.save()
    }

    func category(name: String) throws -> TagCategory? {
        let catName = name
        var descriptor = FetchDescriptor<SDCategory>(
            predicate: #Predicate<SDCategory> { $0.name == catName }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.toDomain()
    }

    func insertCategory(_ category: TagCategory) throws {
        modelContext.insert(SDCategory(from: category))
        try modelContext.save()
    }

    func tagCount(in categoryID: UUID) throws -> Int {
        let catID = categoryID
        let descriptor = FetchDescriptor<SDTag>(
            predicate: #Predicate<SDTag> { $0.categoryID == catID }
        )
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Tags

    func tags(in categoryID: UUID) throws -> [Tag] {
        let catID = categoryID
        let descriptor = FetchDescriptor<SDTag>(
            predicate: #Predicate<SDTag> { $0.categoryID == catID }
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func allTags() throws -> [Tag] {
        return try modelContext.fetch(FetchDescriptor<SDTag>()).map { $0.toDomain() }
    }

    func addTag(canonicalString: String, toCategoryID categoryID: UUID) throws -> Tag {
        let catID = categoryID
        let normalized = DuplicateDetector.normalize(canonicalString)

        // Application-level uniqueness check
        let dupeDescriptor = FetchDescriptor<SDTag>(
            predicate: #Predicate<SDTag> { $0.categoryID == catID && $0.normalizedString == normalized }
        )
        if let existing = try modelContext.fetch(dupeDescriptor).first {
            throw TagRepositoryError.duplicateTag(canonicalString, existingTag: existing.toDomain())
        }

        // Find category model
        var catDescriptor = FetchDescriptor<SDCategory>(
            predicate: #Predicate<SDCategory> { $0.id == catID }
        )
        catDescriptor.fetchLimit = 1
        guard let categoryModel = try modelContext.fetch(catDescriptor).first else {
            throw TagRepositoryError.categoryNotFound(categoryID)
        }

        let tag = SDTag(canonicalString: canonicalString, category: categoryModel)
        modelContext.insert(tag)
        try modelContext.save()
        return tag.toDomain()
    }

    func tag(normalizedString: String, inCategoryID categoryID: UUID) throws -> Tag? {
        let norm = normalizedString
        let catID = categoryID
        var descriptor = FetchDescriptor<SDTag>(
            predicate: #Predicate<SDTag> { $0.normalizedString == norm && $0.categoryID == catID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.toDomain()
    }

    func insertTag(id: UUID, canonicalString: String, categoryID: UUID) throws -> Tag {
        let catID = categoryID
        var catDescriptor = FetchDescriptor<SDCategory>(
            predicate: #Predicate<SDCategory> { $0.id == catID }
        )
        catDescriptor.fetchLimit = 1
        guard let categoryModel = try modelContext.fetch(catDescriptor).first else {
            throw TagRepositoryError.categoryNotFound(categoryID)
        }
        let tag = SDTag(id: id, canonicalString: canonicalString, category: categoryModel)
        modelContext.insert(tag)
        try modelContext.save()
        return tag.toDomain()
    }

    func deleteTag(id: UUID) throws {
        let tagID = id
        var descriptor = FetchDescriptor<SDTag>(
            predicate: #Predicate<SDTag> { $0.id == tagID }
        )
        descriptor.fetchLimit = 1
        guard let tag = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(tag)
        try modelContext.save()
    }
}

enum TagRepositoryError: Error, LocalizedError {
    case duplicateTag(String, existingTag: Tag)
    case categoryNotFound(UUID)
    case cannotDeleteBuiltIn(String)

    var errorDescription: String? {
        switch self {
        case .duplicateTag(let string, _):
            return "A tag matching '\(string)' already exists in this category."
        case .categoryNotFound(let id):
            return "Category \(id) not found."
        case .cannotDeleteBuiltIn(let name):
            return "'\(name)' is a built-in category and cannot be deleted. Disable it instead."
        }
    }
}
