import Foundation
import SwiftData
import TaggingCore

protocol TagRepository {
    func tags(inCategory categoryID: UUID) throws -> [Tag]
    func allTags() throws -> [Tag]
    func createTag(canonicalString: String, inCategory categoryID: UUID) throws -> Tag
    func deleteTag(id: UUID) throws
}

final class SwiftDataTagRepository: TagRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func tags(inCategory categoryID: UUID) throws -> [Tag] {
        let descriptor = FetchDescriptor<SDTag>(
            predicate: #Predicate { $0.categoryStableID == categoryID }
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func allTags() throws -> [Tag] {
        let descriptor = FetchDescriptor<SDTag>()
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func createTag(canonicalString: String, inCategory categoryID: UUID) throws -> Tag {
        // Application-level uniqueness: exact normalized match blocks creation
        let existing = try tags(inCategory: categoryID)
        let normalizedInput = DuplicateDetector.normalize(canonicalString)
        for tag in existing {
            if DuplicateDetector.normalize(tag.canonicalString) == normalizedInput {
                throw StoreError.duplicateTag(existing: tag)
            }
        }

        // NFC normalize for storage consistency (design §3.3)
        let storedString = canonicalString.precomposedStringWithCanonicalMapping

        let tag = Tag(canonicalString: storedString, categoryID: categoryID)
        modelContext.insert(SDTag(from: tag))
        try modelContext.save()
        return tag
    }

    func deleteTag(id: UUID) throws {
        var descriptor = FetchDescriptor<SDTag>(
            predicate: #Predicate { $0.stableID == id }
        )
        descriptor.fetchLimit = 1
        guard let sd = try modelContext.fetch(descriptor).first else {
            throw StoreError.tagNotFound(id: id)
        }
        modelContext.delete(sd)
        try modelContext.save()
    }
}
