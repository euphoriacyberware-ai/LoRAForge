import Foundation
import SwiftData
import Testing
import TaggingCore
@testable import LoRAForge

private func makeInMemoryContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: SDTagCategory.self, SDTag.self, SDKnownProject.self,
        configurations: config
    )
}

// MARK: - Category Store

@Suite("Store — Categories")
@MainActor
struct CategoryStoreTests {

    @Test func builtInsSeedOnFirstLaunch() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCategoryRepository(modelContext: container.mainContext)
        try repo.seedBuiltInsIfNeeded()

        let categories = try repo.allCategories()
        #expect(categories.count == 11)
    }

    @Test func builtInsHaveCorrectOrder() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCategoryRepository(modelContext: container.mainContext)
        try repo.seedBuiltInsIfNeeded()

        let categories = try repo.allCategories()
        #expect(categories[0].name == "Subject")
        #expect(categories[0].position == 0)
        #expect(categories[0].selectMode == .single)
        #expect(categories[0].prefix == nil)
        #expect(categories[0].isBuiltIn == true)

        #expect(categories[8].name == "Clothing")
        #expect(categories[8].selectMode == .multi)
        #expect(categories[8].prefix == "wearing")

        #expect(categories[10].name == "Background-Location")
        #expect(categories[10].position == 10)
    }

    @Test func builtInsEachCarryOwnThresholds() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCategoryRepository(modelContext: container.mainContext)
        try repo.seedBuiltInsIfNeeded()

        let categories = try repo.allCategories()
        for cat in categories {
            #expect(cat.highThreshold == 0.70)
            #expect(cat.lowThreshold == 0.10)
        }
    }

    @Test func builtInsDoNotReseedIfAlreadyPresent() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCategoryRepository(modelContext: container.mainContext)
        try repo.seedBuiltInsIfNeeded()
        try repo.seedBuiltInsIfNeeded() // second call

        let categories = try repo.allCategories()
        #expect(categories.count == 11)
    }

    @Test func categoryCanBeUpdated() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCategoryRepository(modelContext: container.mainContext)
        try repo.seedBuiltInsIfNeeded()

        var subject = try repo.allCategories().first!
        subject.name = "Character"
        try repo.save(subject)

        let fetched = try repo.category(byID: subject.id)
        #expect(fetched?.name == "Character")
    }

    @Test func builtInCannotBeDeleted() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCategoryRepository(modelContext: container.mainContext)
        try repo.seedBuiltInsIfNeeded()

        let subject = try repo.allCategories().first!
        #expect(throws: StoreError.self) {
            try repo.delete(categoryID: subject.id)
        }
    }

    @Test func userCategoryCanBeCreatedAndDeleted() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCategoryRepository(modelContext: container.mainContext)

        let custom = TagCategory(
            name: "Custom", selectMode: .single, position: 99
        )
        try repo.save(custom)

        var all = try repo.allCategories()
        #expect(all.contains(where: { $0.name == "Custom" }))

        try repo.delete(categoryID: custom.id)
        all = try repo.allCategories()
        #expect(!all.contains(where: { $0.id == custom.id }))
    }
}

// MARK: - Tag Store

private typealias Tag = TaggingCore.Tag

@Suite("Store — Tags")
@MainActor
struct TagStoreTests {

    @Test func tagCanBeCreatedAndFetched() throws {
        let container = try makeInMemoryContainer()
        let catRepo = SwiftDataCategoryRepository(modelContext: container.mainContext)
        let tagRepo = SwiftDataTagRepository(modelContext: container.mainContext)
        try catRepo.seedBuiltInsIfNeeded()

        let categories = try catRepo.allCategories()
        let expression = categories.first(where: { $0.name == "Expression" })!

        let created = try tagRepo.createTag(canonicalString: "smiling", inCategory: expression.id)
        #expect(created.canonicalString == "smiling")
        #expect(created.categoryID == expression.id)

        let fetched = try tagRepo.tags(inCategory: expression.id)
        #expect(fetched.count == 1)
        #expect(fetched[0].canonicalString == "smiling")
    }

    @Test func duplicateCanonicalStringInSameCategoryIsRejected() throws {
        let container = try makeInMemoryContainer()
        let catRepo = SwiftDataCategoryRepository(modelContext: container.mainContext)
        let tagRepo = SwiftDataTagRepository(modelContext: container.mainContext)
        try catRepo.seedBuiltInsIfNeeded()

        let expression = try catRepo.allCategories().first(where: { $0.name == "Expression" })!

        _ = try tagRepo.createTag(canonicalString: "smiling", inCategory: expression.id)

        // Same canonical string (different case) should be rejected
        #expect(throws: StoreError.self) {
            _ = try tagRepo.createTag(canonicalString: "Smiling", inCategory: expression.id)
        }
    }

    @Test func sameCanonicalStringInDifferentCategoryIsAllowed() throws {
        let container = try makeInMemoryContainer()
        let catRepo = SwiftDataCategoryRepository(modelContext: container.mainContext)
        let tagRepo = SwiftDataTagRepository(modelContext: container.mainContext)
        try catRepo.seedBuiltInsIfNeeded()

        let categories = try catRepo.allCategories()
        let expression = categories.first(where: { $0.name == "Expression" })!
        let pose = categories.first(where: { $0.name == "Pose" })!

        _ = try tagRepo.createTag(canonicalString: "relaxed", inCategory: expression.id)
        let tag2 = try tagRepo.createTag(canonicalString: "relaxed", inCategory: pose.id)
        #expect(tag2.canonicalString == "relaxed")
        #expect(tag2.categoryID == pose.id)
    }

    @Test func tagCanBeDeleted() throws {
        let container = try makeInMemoryContainer()
        let catRepo = SwiftDataCategoryRepository(modelContext: container.mainContext)
        let tagRepo = SwiftDataTagRepository(modelContext: container.mainContext)
        try catRepo.seedBuiltInsIfNeeded()

        let expression = try catRepo.allCategories().first(where: { $0.name == "Expression" })!
        let created = try tagRepo.createTag(canonicalString: "smiling", inCategory: expression.id)

        try tagRepo.deleteTag(id: created.id)
        let remaining = try tagRepo.tags(inCategory: expression.id)
        #expect(remaining.isEmpty)
    }

    @Test func tagStoredWithNFCNormalization() throws {
        let container = try makeInMemoryContainer()
        let catRepo = SwiftDataCategoryRepository(modelContext: container.mainContext)
        let tagRepo = SwiftDataTagRepository(modelContext: container.mainContext)
        try catRepo.seedBuiltInsIfNeeded()

        let expression = try catRepo.allCategories().first(where: { $0.name == "Expression" })!

        // Decomposed é (e + combining accent)
        let decomposed = "caf\u{0065}\u{0301}"
        let tag = try tagRepo.createTag(canonicalString: decomposed, inCategory: expression.id)

        // Stored string should be NFC (precomposed é)
        let precomposed = "caf\u{00E9}"
        #expect(tag.canonicalString == precomposed)
    }

    @Test func allTagsReturnsFromAllCategories() throws {
        let container = try makeInMemoryContainer()
        let catRepo = SwiftDataCategoryRepository(modelContext: container.mainContext)
        let tagRepo = SwiftDataTagRepository(modelContext: container.mainContext)
        try catRepo.seedBuiltInsIfNeeded()

        let categories = try catRepo.allCategories()
        _ = try tagRepo.createTag(canonicalString: "smiling", inCategory: categories[5].id)
        _ = try tagRepo.createTag(canonicalString: "standing", inCategory: categories[3].id)

        let all = try tagRepo.allTags()
        #expect(all.count == 2)
    }
}

// MARK: - Known Projects

@Suite("Store — Known Projects")
@MainActor
struct KnownProjectsStoreTests {

    @Test func projectCanBeRegisteredAndFetched() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataKnownProjectsRepository(modelContext: container.mainContext)

        let id = UUID()
        try repo.register(projectID: id, name: "Test Project")

        let projects = try repo.allProjects()
        #expect(projects.count == 1)
        #expect(projects[0].projectID == id)
        #expect(projects[0].name == "Test Project")
    }

    @Test func registeringExistingProjectUpdatesIt() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataKnownProjectsRepository(modelContext: container.mainContext)

        let id = UUID()
        try repo.register(projectID: id, name: "Old Name")
        try repo.register(projectID: id, name: "New Name")

        let projects = try repo.allProjects()
        #expect(projects.count == 1)
        #expect(projects[0].name == "New Name")
    }

    @Test func projectCanBeRemoved() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataKnownProjectsRepository(modelContext: container.mainContext)

        let id = UUID()
        try repo.register(projectID: id, name: "Test")
        try repo.remove(projectID: id)

        let projects = try repo.allProjects()
        #expect(projects.isEmpty)
    }
}
