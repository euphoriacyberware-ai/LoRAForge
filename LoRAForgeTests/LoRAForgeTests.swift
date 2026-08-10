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

    // MARK: - Phase 3: Category management

    @Test("User category can be created and appears at the end")
    func addUserCategory() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let custom = try repo.addCategory(name: "Custom", selectMode: .single, prefix: nil)
        let all = try repo.allCategories()
        #expect(all.count == 12)
        #expect(all.last?.id == custom.id)
        #expect(!custom.isBuiltIn)
    }

    @Test("User category can be deleted")
    func deleteUserCategory() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let custom = try repo.addCategory(name: "Custom", selectMode: .single, prefix: nil)
        try repo.deleteCategory(id: custom.id)
        let all = try repo.allCategories()
        #expect(all.count == 11)
    }

    @Test("Built-in category cannot be deleted")
    func cannotDeleteBuiltIn() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        #expect(throws: TagRepositoryError.self) {
            try repo.deleteCategory(id: BuiltInCategory.subject.id)
        }
    }

    @Test("Deleting a category cascade-deletes its tags")
    func deleteCategoryCascadesTags() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let custom = try repo.addCategory(name: "Custom", selectMode: .single, prefix: nil)
        _ = try repo.addTag(canonicalString: "test tag", toCategoryID: custom.id)
        #expect(try repo.tags(in: custom.id).count == 1)

        try repo.deleteCategory(id: custom.id)
        #expect(try repo.allTags().isEmpty)
    }

    @Test("Categories can be reordered")
    func reorderCategories() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        var cats = try repo.allCategories()
        let first = cats[1] // Framing
        let second = cats[2] // Camera Angle
        cats.swapAt(1, 2)

        try repo.reorderCategories(cats.map(\.id))

        let reordered = try repo.allCategories()
        #expect(reordered[1].id == second.id)
        #expect(reordered[2].id == first.id)
    }

    @Test("Tag count returns correct number")
    func tagCount() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let poseID = BuiltInCategory.pose.id
        #expect(try repo.tagCount(in: poseID) == 0)

        _ = try repo.addTag(canonicalString: "standing", toCategoryID: poseID)
        _ = try repo.addTag(canonicalString: "sitting", toCategoryID: poseID)
        #expect(try repo.tagCount(in: poseID) == 2)
    }

    // MARK: - Phase 4: Bundle and Library

    @Test("Project bundle round-trips metadata")
    func bundleRoundTrip() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let categories = try repo.allCategories()
        let doc = ProjectDocument(name: "Test Project", categories: categories)
        let schema = SchemaSnapshot(categories: categories, tags: [])

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let bundleURL = tempDir.appending(path: "Test.loraforge")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try ProjectBundle.create(at: bundleURL, project: doc, schema: schema)

        let bundle = ProjectBundle(url: bundleURL)
        let loaded = try bundle.readProject()
        #expect(loaded.id == doc.id)
        #expect(loaded.name == "Test Project")
        #expect(loaded.categoryOrder.count == 11)

        let loadedSchema = try bundle.readSchema()
        #expect(loadedSchema.categories.count == 11)
    }

    @Test("Atomic write survives overwrite")
    func atomicOverwrite() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let categories = try repo.allCategories()
        var doc = ProjectDocument(name: "Original", categories: categories)
        let schema = SchemaSnapshot(categories: categories, tags: [])

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let bundleURL = tempDir.appending(path: "Test.loraforge")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try ProjectBundle.create(at: bundleURL, project: doc, schema: schema)

        doc.name = "Updated"
        let bundle = ProjectBundle(url: bundleURL)
        try bundle.writeProjectAtomic(doc)

        let loaded = try bundle.readProject()
        #expect(loaded.name == "Updated")
    }

    @Test("Library manager creates and lists projects")
    func libraryCreateAndList() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = LibraryManager(libraryURL: tempDir)
        #expect(library.projects.isEmpty)

        let info = try library.createProject(name: "Maya", repo: repo)
        #expect(library.projects.count == 1)
        #expect(library.projects[0].name == "Maya")
        #expect(info.id == library.projects[0].id)
    }

    @Test("Library manager deletes projects")
    func libraryDelete() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = LibraryManager(libraryURL: tempDir)
        let info = try library.createProject(name: "ToDelete", repo: repo)
        try library.deleteProject(id: info.id)
        #expect(library.projects.isEmpty)
    }

    @Test("Library manager renames projects")
    func libraryRename() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = LibraryManager(libraryURL: tempDir)
        let info = try library.createProject(name: "Old Name", repo: repo)
        try library.renameProject(id: info.id, to: "New Name")

        let doc = try library.loadDocument(id: info.id)
        #expect(doc?.name == "New Name")
    }

    @Test("Project snapshots category order at creation")
    func categoryOrderSnapshot() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = LibraryManager(libraryURL: tempDir)
        let info = try library.createProject(name: "Test", repo: repo)
        let doc = try library.loadDocument(id: info.id)!

        #expect(doc.categoryOrder.count == 11)
        #expect(doc.categoryOrder[0] == BuiltInCategory.subject.id)
        #expect(doc.categoryEnabled.count == 11)
    }

    // MARK: - Phase 5: Entry and image model

    @Test("Entries with images round-trip through bundle")
    func entryImageRoundTrip() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let categories = try repo.allCategories()
        var doc = ProjectDocument(name: "ImageTest", categories: categories)
        var entry = EntryDocument(name: "Entry 1", position: 1)
        entry.images = [
            ImageDocument(filename: "test1.png", rank: .candidate),
            ImageDocument(filename: "test2.png", rank: .final),
        ]
        doc.entries.append(entry)

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let bundleURL = tempDir.appending(path: "Test.loraforge")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let schema = SchemaSnapshot(categories: categories, tags: [])
        try ProjectBundle.create(at: bundleURL, project: doc, schema: schema)

        let loaded = try ProjectBundle(url: bundleURL).readProject()
        #expect(loaded.entries.count == 1)
        #expect(loaded.entries[0].images.count == 2)
        #expect(loaded.entries[0].finalImage?.filename == "test2.png")
    }

    @Test("Promoting to final demotes previous final to shortlist")
    func finalPromotion() throws {
        var entry = EntryDocument(name: "Test", position: 1)
        entry.images = [
            ImageDocument(filename: "a.png", rank: .final),
            ImageDocument(filename: "b.png", rank: .candidate),
        ]
        let oldFinalID = entry.images[0].id
        let newFinalID = entry.images[1].id

        // Simulate promotion: demote old final, promote new
        for i in entry.images.indices {
            if entry.images[i].rank == .final {
                entry.images[i].rank = .shortlist
            }
        }
        if let idx = entry.images.firstIndex(where: { $0.id == newFinalID }) {
            entry.images[idx].rank = .final
        }

        #expect(entry.images.first { $0.id == oldFinalID }?.rank == .shortlist)
        #expect(entry.images.first { $0.id == newFinalID }?.rank == .final)
    }

    @Test("Sweep moves candidates to discarded, leaves others")
    func sweepEntry() throws {
        var entry = EntryDocument(name: "Test", position: 1)
        entry.images = [
            ImageDocument(filename: "a.png", rank: .final),
            ImageDocument(filename: "b.png", rank: .shortlist),
            ImageDocument(filename: "c.png", rank: .candidate),
            ImageDocument(filename: "d.png", rank: .candidate),
        ]

        // Sweep: candidates → discarded
        for i in entry.images.indices {
            if entry.images[i].rank == .candidate {
                entry.images[i].rank = .discarded
            }
        }

        #expect(entry.images[0].rank == .final)
        #expect(entry.images[1].rank == .shortlist)
        #expect(entry.images[2].rank == .discarded)
        #expect(entry.images[3].rank == .discarded)
    }

    @Test("Active image count excludes discarded")
    func activeImageCount() throws {
        var entry = EntryDocument(name: "Test", position: 1)
        entry.images = [
            ImageDocument(filename: "a.png", rank: .final),
            ImageDocument(filename: "b.png", rank: .candidate),
            ImageDocument(filename: "c.png", rank: .discarded),
        ]
        #expect(entry.activeImageCount == 2)
    }
}
