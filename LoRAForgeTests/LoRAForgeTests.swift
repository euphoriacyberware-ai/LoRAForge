import Testing
import Foundation
import SwiftData
@testable import LoRAForge
import TaggingCore

private typealias Tag = TaggingCore.Tag

@MainActor
private let testContainer: ModelContainer = {
    let schema = Schema([SDCategory.self, SDTag.self])
    let config = ModelConfiguration(
        "test-store", schema: schema, isStoredInMemoryOnly: true
    )
    return try! ModelContainer(for: schema, configurations: [config])
}()

@MainActor
private func freshRepository() throws -> TagRepository {
    let context = testContainer.mainContext
    for tag in try context.fetch(FetchDescriptor<SDTag>()) {
        context.delete(tag)
    }
    for cat in try context.fetch(FetchDescriptor<SDCategory>()) {
        context.delete(cat)
    }
    try context.save()
    return TagRepository(modelContext: context)
}

@Suite("Store", .serialized) @MainActor
struct StoreTests {

    @Test("Seeds eleven built-in categories")
    func seedsBuiltIns() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()
        let categories = try repo.allCategories()
        #expect(categories.count == 11)
    }

    @Test("Seeding is idempotent")
    func seedIdempotent() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()
        try repo.seedBuiltInCategoriesIfNeeded()
        let categories = try repo.allCategories()
        #expect(categories.count == 11)
    }

    @Test("Seeded categories match design spec")
    func seedMatchesDesign() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()
        let categories = try repo.allCategories()
        let names = categories.sorted { $0.position < $1.position }.map(\.name)
        #expect(names == [
            "Subject", "Framing", "Camera Angle", "Pose", "Gaze", "Expression",
            "Lighting", "Hairstyle", "Clothing", "Held-Items", "Background-Location"
        ])

        let clothing = categories.first { $0.name == "Clothing" }!
        #expect(clothing.selectMode == .multi)
        #expect(clothing.prefix == "wearing")
        #expect(clothing.highThreshold == 70)
        #expect(clothing.lowThreshold == 10)
    }

    @Test("Each category carries its own threshold pair")
    func individualThresholds() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()
        for cat in try repo.allCategories() {
            #expect(cat.highThreshold == 70)
            #expect(cat.lowThreshold == 10)
        }
    }

    @Test("Category updates persist")
    func categoryUpdate() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        var lighting = try repo.allCategories().first { $0.name == "Lighting" }!
        lighting.isEnabled = false
        try repo.updateCategory(lighting)

        let fetched = try repo.category(id: lighting.id)
        #expect(fetched?.isEnabled == false)
    }

    @Test("Tags persist and are retrievable by category")
    func tagRoundTrip() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let poseID = BuiltInCategory.pose.id
        let tag = try repo.addTag(canonicalString: "standing", toCategoryID: poseID)

        let tags = try repo.tags(in: poseID)
        #expect(tags.count == 1)
        #expect(tags[0].id == tag.id)
        #expect(tags[0].canonicalString == "standing")
    }

    @Test("Tags can be deleted")
    func tagDeletion() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let tag = try repo.addTag(canonicalString: "standing", toCategoryID: BuiltInCategory.pose.id)
        try repo.deleteTag(id: tag.id)
        let tags = try repo.tags(in: BuiltInCategory.pose.id)
        #expect(tags.isEmpty)
    }

    @Test("allTags returns tags across categories")
    func allTagsAcrossCategories() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        _ = try repo.addTag(canonicalString: "standing", toCategoryID: BuiltInCategory.pose.id)
        _ = try repo.addTag(canonicalString: "smiling", toCategoryID: BuiltInCategory.expression.id)

        let all = try repo.allTags()
        #expect(all.count == 2)
    }

    @Test("Duplicate canonical string within a category is rejected")
    func duplicateRejected() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        _ = try repo.addTag(canonicalString: "standing", toCategoryID: BuiltInCategory.pose.id)

        #expect(throws: TagRepositoryError.self) {
            _ = try repo.addTag(canonicalString: "standing", toCategoryID: BuiltInCategory.pose.id)
        }
    }

    @Test("Normalized duplicate is rejected")
    func normalizedDuplicateRejected() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        _ = try repo.addTag(canonicalString: "standing", toCategoryID: BuiltInCategory.pose.id)

        #expect(throws: TagRepositoryError.self) {
            _ = try repo.addTag(canonicalString: "Standing", toCategoryID: BuiltInCategory.pose.id)
        }
    }

    @Test("Same string in different categories is allowed")
    func sameStringDifferentCategory() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        _ = try repo.addTag(canonicalString: "smiling", toCategoryID: BuiltInCategory.expression.id)
        _ = try repo.addTag(canonicalString: "smiling", toCategoryID: BuiltInCategory.pose.id)

        let expressionTags = try repo.tags(in: BuiltInCategory.expression.id)
        let poseTags = try repo.tags(in: BuiltInCategory.pose.id)
        #expect(expressionTags.count == 1)
        #expect(poseTags.count == 1)
    }

    @Test("Adding tag to nonexistent category throws")
    func nonexistentCategory() throws {
        let repo = try freshRepository()

        #expect(throws: TagRepositoryError.self) {
            _ = try repo.addTag(canonicalString: "test", toCategoryID: UUID())
        }
    }
}
