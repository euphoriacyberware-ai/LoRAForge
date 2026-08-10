import Foundation
import SwiftData
import Testing
import TaggingCore
import UniformTypeIdentifiers
@testable import LoRAForge

// MARK: - Serialization Round-Trip

@Suite("Document — Serialization")
struct SerializationTests {

    @Test func metadataRoundTrips() throws {
        let original = ProjectMetadata(
            id: UUID(), name: "Test Project",
            categoryOrder: [UUID(), UUID(), UUID()],
            disabledCategories: [UUID()]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectMetadata.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == "Test Project")
        #expect(decoded.categoryOrder == original.categoryOrder)
        #expect(decoded.disabledCategories == original.disabledCategories)
    }

    @Test func schemaSnapshotRoundTrips() throws {
        let catID = UUID()
        let original = SchemaSnapshot(
            tags: [
                TagSnapshot(from: Tag(canonicalString: "smiling", categoryID: catID)),
                TagSnapshot(from: Tag(canonicalString: "frowning", categoryID: catID)),
            ],
            categories: [
                CategorySnapshot(from: TagCategory(
                    name: "Expression", selectMode: .single, position: 5,
                    highThreshold: 0.70, lowThreshold: 0.10
                )),
                CategorySnapshot(from: TagCategory(
                    name: "Clothing", selectMode: .multi, prefix: "wearing", position: 8
                )),
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SchemaSnapshot.self, from: data)

        #expect(decoded.tags.count == 2)
        #expect(decoded.tags[0].canonicalString == "smiling")
        #expect(decoded.categories.count == 2)
        #expect(decoded.categories[0].name == "Expression")
        #expect(decoded.categories[0].selectMode == .single)
        #expect(decoded.categories[1].prefix == "wearing")
        #expect(decoded.categories[1].selectMode == .multi)
    }

    @Test func categorySnapshotPreservesSelectMode() throws {
        let single = CategorySnapshot(from: TagCategory(
            name: "Pose", selectMode: .single, position: 3
        ))
        let multi = CategorySnapshot(from: TagCategory(
            name: "Clothing", selectMode: .multi, prefix: "wearing", position: 8
        ))
        let data = try JSONEncoder().encode([single, multi])
        let decoded = try JSONDecoder().decode([CategorySnapshot].self, from: data)

        #expect(decoded[0].selectMode == .single)
        #expect(decoded[1].selectMode == .multi)
        #expect(decoded[1].prefix == "wearing")
    }
}

// MARK: - Reconciliation

private func makeInMemoryContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: SDTagCategory.self, SDTag.self, SDKnownProject.self,
        configurations: config
    )
}

private typealias Tag = TaggingCore.Tag

@Suite("Document — Reconciliation")
@MainActor
struct ReconciliationTests {

    @Test func cleanSnapshotProducesNoIssues() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let catRepo = SwiftDataCategoryRepository(modelContext: context)
        try catRepo.seedBuiltInsIfNeeded()

        let categories = try catRepo.allCategories()
        let snapshot = SchemaSnapshot(
            tags: [],
            categories: categories.map { CategorySnapshot(from: $0) }
        )

        let service = ReconciliationService(modelContext: context)
        let result = service.reconcile(snapshot: snapshot)
        #expect(!result.needsAttention)
    }

    @Test func missingTagIsDetected() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let catRepo = SwiftDataCategoryRepository(modelContext: context)
        try catRepo.seedBuiltInsIfNeeded()
        let expression = try catRepo.allCategories().first(where: { $0.name == "Expression" })!

        let tagRepo = SwiftDataTagRepository(modelContext: context)
        let tag = try tagRepo.createTag(canonicalString: "smiling", inCategory: expression.id)

        let snapshot = SchemaSnapshot(
            tags: [TagSnapshot(from: tag)],
            categories: []
        )

        // Delete the tag from the library
        try tagRepo.deleteTag(id: tag.id)

        let service = ReconciliationService(modelContext: context)
        let result = service.reconcile(snapshot: snapshot)
        #expect(result.needsAttention)
        #expect(result.missingTags.count == 1)
        #expect(result.missingTags[0].canonicalString == "smiling")
    }

    @Test func missingTagCanBeImported() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let catRepo = SwiftDataCategoryRepository(modelContext: context)
        try catRepo.seedBuiltInsIfNeeded()
        let expression = try catRepo.allCategories().first(where: { $0.name == "Expression" })!

        let missingTag = TagSnapshot(
            from: Tag(canonicalString: "grinning", categoryID: expression.id)
        )

        let service = ReconciliationService(modelContext: context)
        let importResult = try service.importTag(missingTag)

        if case .created(let created) = importResult {
            #expect(created.canonicalString == "grinning")
        } else {
            Issue.record("Expected .created")
        }

        let tagRepo = SwiftDataTagRepository(modelContext: context)
        let tags = try tagRepo.tags(inCategory: expression.id)
        #expect(tags.contains(where: { $0.canonicalString == "grinning" }))
    }

    @Test func importDetectsExactDuplicate() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let catRepo = SwiftDataCategoryRepository(modelContext: context)
        try catRepo.seedBuiltInsIfNeeded()
        let expression = try catRepo.allCategories().first(where: { $0.name == "Expression" })!

        let tagRepo = SwiftDataTagRepository(modelContext: context)
        let existing = try tagRepo.createTag(canonicalString: "smiling", inCategory: expression.id)

        // Import tag with same string but different ID
        let snapshot = TagSnapshot(
            from: Tag(canonicalString: "smiling", categoryID: expression.id)
        )

        let service = ReconciliationService(modelContext: context)
        let importResult = try service.importTag(snapshot)

        if case .mappedToExisting(let tag) = importResult {
            #expect(tag.id == existing.id)
        } else {
            Issue.record("Expected .mappedToExisting")
        }
    }

    @Test func driftedPrefixIsDetected() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let catRepo = SwiftDataCategoryRepository(modelContext: context)
        try catRepo.seedBuiltInsIfNeeded()
        let categories = try catRepo.allCategories()

        let snapshot = SchemaSnapshot(
            tags: [],
            categories: categories.map { CategorySnapshot(from: $0) }
        )

        // Change Clothing prefix
        var clothing = categories.first(where: { $0.name == "Clothing" })!
        clothing.prefix = "dressed in"
        try catRepo.save(clothing)

        let service = ReconciliationService(modelContext: context)
        let result = service.reconcile(snapshot: snapshot)
        #expect(result.driftedCategories.count == 1)
        #expect(result.driftedCategories[0].prefixChanged)
    }

    @Test func missingCategoryIsDetected() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let catRepo = SwiftDataCategoryRepository(modelContext: context)

        let custom = TagCategory(name: "Custom", selectMode: .single, position: 99)
        try catRepo.save(custom)

        let snapshot = SchemaSnapshot(
            tags: [],
            categories: [CategorySnapshot(from: custom)]
        )

        try catRepo.delete(categoryID: custom.id)

        let service = ReconciliationService(modelContext: context)
        let result = service.reconcile(snapshot: snapshot)
        #expect(result.missingCategories.count == 1)
        #expect(result.missingCategories[0].name == "Custom")
    }
}
