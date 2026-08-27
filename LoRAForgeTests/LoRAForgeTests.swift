import Testing
import Foundation
import SwiftData
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
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
        let categories = BuiltInCategory.defaultCategories
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
        let categories = BuiltInCategory.defaultCategories
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

    // MARK: - Phase 6: Caption model

    @Test("Caption fields round-trip through bundle")
    func captionRoundTrip() throws {
        let categories = BuiltInCategory.defaultCategories
        var doc = ProjectDocument(name: "CaptionTest", categories: categories)
        var entry = EntryDocument(name: "Entry 1", position: 1)
        entry.captionMode = .manual
        entry.manualCaptionText = "A test caption"
        doc.entries.append(entry)

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let bundleURL = tempDir.appending(path: "Test.loraforge")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let schema = SchemaSnapshot(categories: categories, tags: [])
        try ProjectBundle.create(at: bundleURL, project: doc, schema: schema)

        let loaded = try ProjectBundle(url: bundleURL).readProject()
        #expect(loaded.entries[0].captionMode == .manual)
        #expect(loaded.entries[0].manualCaptionText == "A test caption")
        #expect(!loaded.entries[0].isLocked)
    }

    @Test("Locking freezes caption text")
    func lockingFreezes() throws {
        var entry = EntryDocument(name: "Test", position: 1)
        entry.captionMode = .manual
        entry.manualCaptionText = "Frozen text"
        entry.lockedCaptionText = "Frozen text"

        #expect(entry.isLocked)
        #expect(entry.lockedCaptionText == "Frozen text")
    }

    @Test("Unlocking clears locked text")
    func unlocking() throws {
        var entry = EntryDocument(name: "Test", position: 1)
        entry.lockedCaptionText = "Frozen"
        #expect(entry.isLocked)

        entry.lockedCaptionText = nil
        #expect(!entry.isLocked)
    }

    @Test("Assignments persist through caption mode changes")
    func assignmentsPersistAcrossModes() throws {
        var entry = EntryDocument(name: "Test", position: 1)
        entry.assignments = [
            AssignmentDocument(tagID: UUID(), selectionOrder: 0),
            AssignmentDocument(tagID: UUID(), selectionOrder: 1),
        ]
        entry.captionMode = .manual
        #expect(entry.assignments.count == 2)

        entry.captionMode = .tagged
        #expect(entry.assignments.count == 2)
    }

    // MARK: - Phase 7: Export

    @Test("Export produces correct filenames and sidecars")
    func exportFilenames() throws {
        let categories = BuiltInCategory.defaultCategories
        var doc = ProjectDocument(name: "Maya", categories: categories)
        var entry1 = EntryDocument(name: "Entry 1", position: 1)
        entry1.images = [ImageDocument(filename: "img1.png", rank: .final)]
        entry1.captionMode = .manual
        entry1.manualCaptionText = "test caption"
        var entry2 = EntryDocument(name: "Entry 2", position: 2)
        entry2.images = [ImageDocument(filename: "img2.png", rank: .candidate)]
        // entry2 has no final — should be skipped
        doc.entries = [entry1, entry2]

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let bundleURL = tempDir.appending(path: "Test.loraforge")
        let exportDir = tempDir.appending(path: "export")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try ProjectBundle.create(at: bundleURL, project: doc, schema: SchemaSnapshot(categories: categories, tags: []))
        // Create the image file so copy works
        try "".write(to: bundleURL.appending(path: "images/img1.png"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let result = try ExportManager.export(
            document: doc, bundleURL: bundleURL, to: exportDir,
            baseName: "maya", scope: .finalsOnly,
            categories: categories, allTags: [:]
        )

        #expect(result.exportedEntries == 1)
        #expect(result.skippedEntries == 1)
        #expect(FileManager.default.fileExists(atPath: exportDir.appending(path: "maya_001.png").path))
        #expect(FileManager.default.fileExists(atPath: exportDir.appending(path: "maya_001.txt").path))

        // Sidecar content
        let sidecar = try String(contentsOf: exportDir.appending(path: "maya_001.txt"), encoding: .utf8)
        #expect(sidecar == "test caption\n")
    }

    @Test("Locked entries export stored text, unlocked tagged render fresh")
    func exportCaptionSource() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let poseID = BuiltInCategory.pose.id
        let tag = try repo.addTag(canonicalString: "standing", toCategoryID: poseID)
        let categories = try repo.allCategories()
        let tags = try repo.allTags()
        let tagDict = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })

        // Locked entry — exports stored text
        var locked = EntryDocument(name: "Locked", position: 1)
        locked.captionMode = .tagged
        locked.lockedCaptionText = "old caption before changes"

        // Unlocked tagged entry — renders fresh
        var unlocked = EntryDocument(name: "Unlocked", position: 2)
        unlocked.captionMode = .tagged
        unlocked.assignments = [AssignmentDocument(tagID: tag.id, selectionOrder: 0)]

        let lockedCaption = ExportManager.captionForExport(entry: locked, categories: categories, allTags: tagDict)
        let unlockedCaption = ExportManager.captionForExport(entry: unlocked, categories: categories, allTags: tagDict)

        #expect(lockedCaption == "old caption before changes")
        #expect(unlockedCaption == "standing")
    }

    @Test("Empty caption produces empty sidecar with trailing newline")
    func emptySidecar() throws {
        let entry = EntryDocument(name: "Empty", position: 1)
        let caption = ExportManager.captionForExport(entry: entry, categories: [], allTags: [:])
        #expect(caption.isEmpty)
        // The sidecar would be "\n" — just the trailing newline
    }

    @Test("Base name sanitization removes illegal characters")
    func baseNameSanitization() throws {
        #expect(ExportManager.sanitizeBaseName("my project") == "myproject")
        #expect(ExportManager.sanitizeBaseName("test/name") == "testname")
        #expect(ExportManager.sanitizeBaseName("") == "export")
    }

    // MARK: - Phase 12: Auditing

    @Test("Audit scopes to tagged-mode entries with final image")
    func auditScope() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let categories = try repo.allCategories()
        let poseTag = try repo.addTag(canonicalString: "standing", toCategoryID: BuiltInCategory.pose.id)
        let allTags = try repo.allTags()
        let tagDict = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })

        var doc = ProjectDocument(name: "AuditTest", categories: categories)

        // Entry 1: tagged + final → scoped
        var e1 = EntryDocument(name: "E1", position: 1)
        e1.captionMode = .tagged
        e1.images = [ImageDocument(filename: "a.png", rank: .final)]
        e1.assignments = [AssignmentDocument(tagID: poseTag.id, selectionOrder: 0)]

        // Entry 2: manual + final → excluded (not tagged)
        var e2 = EntryDocument(name: "E2", position: 2)
        e2.captionMode = .manual
        e2.images = [ImageDocument(filename: "b.png", rank: .final)]

        // Entry 3: tagged but no final → excluded
        var e3 = EntryDocument(name: "E3", position: 3)
        e3.captionMode = .tagged

        doc.entries = [e1, e2, e3]

        let result = AuditEngine.audit(document: doc, categories: categories, allTags: tagDict)
        #expect(result.totalEntries == 3)
        #expect(result.scopedEntries == 1)
        #expect(result.excludedNoFinal == 1)
        #expect(result.excludedNotTagged == 1)
    }

    @Test("Audit computes per-category coverage and tag frequency")
    func auditCoverage() throws {
        let repo = try freshRepository()
        try repo.seedBuiltInCategoriesIfNeeded()

        let categories = try repo.allCategories()
        let standing = try repo.addTag(canonicalString: "standing", toCategoryID: BuiltInCategory.pose.id)
        let sitting = try repo.addTag(canonicalString: "sitting", toCategoryID: BuiltInCategory.pose.id)
        let allTags = try repo.allTags()
        let tagDict = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })

        var doc = ProjectDocument(name: "CoverageTest", categories: categories)

        // 3 scoped entries: 2 have Pose assigned, 1 does not
        var e1 = EntryDocument(name: "E1", position: 1)
        e1.captionMode = .tagged
        e1.images = [ImageDocument(filename: "a.png", rank: .final)]
        e1.assignments = [AssignmentDocument(tagID: standing.id, selectionOrder: 0)]

        var e2 = EntryDocument(name: "E2", position: 2)
        e2.captionMode = .tagged
        e2.images = [ImageDocument(filename: "b.png", rank: .final)]
        e2.assignments = [AssignmentDocument(tagID: standing.id, selectionOrder: 0)]

        var e3 = EntryDocument(name: "E3", position: 3)
        e3.captionMode = .tagged
        e3.images = [ImageDocument(filename: "c.png", rank: .final)]
        e3.assignments = [AssignmentDocument(tagID: sitting.id, selectionOrder: 0)]

        doc.entries = [e1, e2, e3]

        let result = AuditEngine.audit(document: doc, categories: categories, allTags: tagDict)
        #expect(result.scopedEntries == 3)

        let poseResult = result.categoryResults.first { $0.id == BuiltInCategory.pose.id }!
        #expect(poseResult.coverage == 1.0) // all 3 entries have a Pose tag
        #expect(poseResult.tagFrequencies.count == 2) // standing and sitting

        let standingFreq = poseResult.tagFrequencies.first { $0.tagName == "standing" }!
        #expect(standingFreq.count == 2)
        // standing: 2/3 = 66.7%, below 70% high threshold — not flagged
        #expect(!standingFreq.isAboveHigh)
    }

    @Test("Audit states explicit denominator")
    func auditDenominator() throws {
        let categories = BuiltInCategory.defaultCategories
        var doc = ProjectDocument(name: "Empty", categories: categories)
        doc.entries = []

        let result = AuditEngine.audit(document: doc, categories: categories, allTags: [:])
        #expect(result.totalEntries == 0)
        #expect(result.scopedEntries == 0)
        #expect(result.categoryResults.isEmpty)
    }
}

// MARK: - Folder import

@Suite("Folder import")
struct FolderImportTests {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a real image so the scan and transcode paths have something genuine to read.
    @discardableResult
    private func writeTestImage(
        at url: URL,
        type: UTType,
        width: Int = 8,
        height: Int = 4,
        orientation: UInt32? = nil,
        frames: Int = 1
    ) throws -> URL {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, frames, nil
        )!
        let properties: CFDictionary? = orientation.map {
            [kCGImagePropertyOrientation: $0] as CFDictionary
        }
        for _ in 0..<frames {
            CGImageDestinationAddImage(dest, cgImage, properties)
        }
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    // MARK: Scan

    @Test("Scan finds only top-level images and counts subfolders")
    func scanIsShallow() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeTestImage(at: dir.appending(path: "top.png"), type: .png)
        let sub = dir.appending(path: "nested")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try writeTestImage(at: sub.appending(path: "buried.png"), type: .png)

        let result = FolderImporter.scan(folder: dir)
        #expect(result.candidates.count == 1)
        #expect(result.candidates.first?.stem == "top")
        #expect(result.subfoldersIgnored == 1)
    }

    @Test("Scan skips hidden files, sidecars, and non-images")
    func scanSkipsNonImages() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeTestImage(at: dir.appending(path: "real.png"), type: .png)
        try Data("caption".utf8).write(to: dir.appending(path: "real.txt"))
        try Data().write(to: dir.appending(path: ".DS_Store"))
        try Data("notes".utf8).write(to: dir.appending(path: "readme.md"))

        let result = FolderImporter.scan(folder: dir)
        #expect(result.candidates.count == 1)
        #expect(result.candidates.first?.stem == "real")
        #expect(result.orphanSidecars == 0)
    }

    @Test("Scan pairs sidecars by stem and counts orphans")
    func scanPairsSidecars() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeTestImage(at: dir.appending(path: "a.jpg"), type: .jpeg)
        try Data("a caption".utf8).write(to: dir.appending(path: "a.txt"))
        try writeTestImage(at: dir.appending(path: "b.png"), type: .png)
        try Data("nobody".utf8).write(to: dir.appending(path: "orphan.txt"))

        let result = FolderImporter.scan(folder: dir)
        #expect(result.candidates.count == 2)
        #expect(result.candidates.first { $0.stem == "a" }?.sidecarURL != nil)
        #expect(result.candidates.first { $0.stem == "b" }?.sidecarURL == nil)
        #expect(result.orphanSidecars == 1)
        #expect(result.captionCount == 1)
    }

    @Test("Sidecar pairing is case-insensitive")
    func scanPairsCaseInsensitively() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeTestImage(at: dir.appending(path: "Maya_042.jpg"), type: .jpeg)
        try Data("a woman".utf8).write(to: dir.appending(path: "maya_042.txt"))

        let result = FolderImporter.scan(folder: dir)
        #expect(result.candidates.count == 1)
        #expect(result.candidates.first?.sidecarURL != nil)
        #expect(result.orphanSidecars == 0)
    }

    @Test("Scan orders numerically, not lexically")
    func scanNaturalOrder() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        for name in ["img10.png", "img2.png", "img1.png"] {
            try writeTestImage(at: dir.appending(path: name), type: .png)
        }

        let stems = FolderImporter.scan(folder: dir).candidates.map(\.stem)
        #expect(stems == ["img1", "img2", "img10"])
    }

    @Test("Supported types exclude vector and non-image formats")
    func supportedTypes() {
        #expect(FolderImporter.isSupportedImageType(.png))
        #expect(FolderImporter.isSupportedImageType(.jpeg))
        #expect(FolderImporter.isSupportedImageType(.gif))
        #expect(FolderImporter.isSupportedImageType(.tiff))
        #expect(!FolderImporter.isSupportedImageType(.svg))
        #expect(!FolderImporter.isSupportedImageType(.pdf))
        #expect(!FolderImporter.isSupportedImageType(.plainText))
        #expect(!FolderImporter.isSupportedImageType(nil))
    }

    // MARK: Caption decoding

    @Test("Caption decoding strips BOM, CRLF, and the exporter's trailing newline")
    func captionNormalization() {
        var bytes = Data([0xEF, 0xBB, 0xBF])
        bytes.append(Data("a woman,\r\n standing\n".utf8))

        let decoded = FolderImporter.decodeCaption(bytes)
        #expect(decoded == "a woman,\n standing")
        #expect(!(decoded ?? "").hasPrefix("\u{FEFF}"))
    }

    @Test("Caption decoding round-trips what ExportManager writes")
    func captionRoundTrips() {
        let caption = "a woman, standing, red hair"
        #expect(FolderImporter.decodeCaption(Data((caption + "\n").utf8)) == caption)
    }

    @Test("Caption decoding preserves interior blank lines")
    func captionKeepsInteriorBlanks() {
        let caption = "first line\n\nthird line"
        #expect(FolderImporter.decodeCaption(Data((caption + "\n").utf8)) == caption)
    }

    @Test("Whitespace-only caption decodes to empty")
    func captionWhitespaceOnly() {
        #expect(FolderImporter.decodeCaption(Data("   \n\n".utf8)) == "")
    }

    // MARK: Conversion

    @Test("Non-PNG input is converted to a real PNG")
    func convertsToPNG() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = try writeTestImage(at: dir.appending(path: "src.jpg"), type: .jpeg)
        let dest = dir.appending(path: "out.png")

        #expect(FolderImporter.writePNG(from: source, to: dest) == nil)
        let header = try Data(contentsOf: dest).prefix(8)
        #expect(Array(header) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    @Test("Clean PNG input is copied byte-for-byte")
    func pngIsNotReEncoded() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = try writeTestImage(at: dir.appending(path: "src.png"), type: .png)
        let dest = dir.appending(path: "out.png")

        #expect(FolderImporter.writePNG(from: source, to: dest) == nil)
        #expect(try Data(contentsOf: source) == (try Data(contentsOf: dest)))
    }

    @Test("A JPEG named .png is transcoded, not copied")
    func mislabelledJPEGIsTranscoded() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // The extension lies; only ImageIO's sniff catches it.
        let source = try writeTestImage(at: dir.appending(path: "liar.png"), type: .jpeg)
        let dest = dir.appending(path: "out.png")

        #expect(FolderImporter.writePNG(from: source, to: dest) == nil)
        #expect(try Data(contentsOf: source) != (try Data(contentsOf: dest)))

        let out = CGImageSourceCreateWithURL(dest as CFURL, nil)!
        #expect((CGImageSourceGetType(out) as String?) == UTType.png.identifier)
    }

    @Test("Multi-frame input yields a single frame")
    func animatedInputFlattened() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = try writeTestImage(at: dir.appending(path: "anim.gif"), type: .gif, frames: 2)
        let dest = dir.appending(path: "out.png")

        #expect(FolderImporter.writePNG(from: source, to: dest) == nil)
        let out = CGImageSourceCreateWithURL(dest as CFURL, nil)!
        #expect(CGImageSourceGetCount(out) == 1)
    }

    @Test("EXIF orientation is baked in and not carried forward")
    func orientationIsBaked() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Orientation 6 means the stored pixels are rotated a quarter turn.
        let source = try writeTestImage(
            at: dir.appending(path: "rot.jpg"), type: .jpeg,
            width: 8, height: 4, orientation: 6
        )
        let dest = dir.appending(path: "out.png")
        #expect(FolderImporter.writePNG(from: source, to: dest) == nil)

        let out = CGImageSourceCreateWithURL(dest as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(out, 0, nil) as? [CFString: Any]
        #expect((props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 4)
        #expect((props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 8)
        #expect(props?[kCGImagePropertyOrientation] == nil)
    }

    @Test("Unreadable input is reported and leaves no file behind")
    func unreadableInputSkipped() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appending(path: "broken.jpg")
        try Data("not an image".utf8).write(to: source)
        let dest = dir.appending(path: "out.png")

        #expect(FolderImporter.writePNG(from: source, to: dest) != nil)
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }

    // MARK: Ingest

    @Test("Ingest writes every image and attaches captions")
    func ingestWritesAll() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeTestImage(at: dir.appending(path: "one.png"), type: .png)
        try writeTestImage(at: dir.appending(path: "two.jpg"), type: .jpeg)
        try Data("two's caption\n".utf8).write(to: dir.appending(path: "two.txt"))

        let imagesDir = dir.appending(path: "images")
        let scan = FolderImporter.scan(folder: dir)
        let summary = await FolderImporter.ingest(scan.candidates, into: imagesDir)

        #expect(summary.items.count == 2)
        #expect(summary.captionCount == 1)
        #expect(summary.skipped.isEmpty)
        #expect(!summary.wasCancelled)

        for item in summary.items {
            #expect(FileManager.default.fileExists(
                atPath: imagesDir.appending(path: item.filename).path
            ))
        }
    }

    @Test("A corrupt file is skipped without stopping the import")
    func ingestSurvivesCorruptFile() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeTestImage(at: dir.appending(path: "a.png"), type: .png)
        try Data("garbage".utf8).write(to: dir.appending(path: "b.png"))
        try writeTestImage(at: dir.appending(path: "c.png"), type: .png)

        let imagesDir = dir.appending(path: "images")
        let scan = FolderImporter.scan(folder: dir)
        let summary = await FolderImporter.ingest(scan.candidates, into: imagesDir)

        #expect(summary.items.count == 2)
        #expect(summary.skipped.count == 1)
        #expect(summary.skipped.first?.name == "b.png")
        #expect(summary.items.map(\.stem) == ["a", "c"])
    }

    @Test("Cancelling rolls back every file already written")
    func ingestCancelRollsBack() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        for name in ["a.png", "b.png", "c.png"] {
            try writeTestImage(at: dir.appending(path: name), type: .png)
        }

        let imagesDir = dir.appending(path: "images")
        let scan = FolderImporter.scan(folder: dir)

        // Injected rather than Task.isCancelled, so the cancellation point is deterministic.
        nonisolated(unsafe) var calls = 0
        let summary = await FolderImporter.ingest(
            scan.candidates,
            into: imagesDir,
            isCancelled: { calls += 1; return calls > 2 }
        )

        #expect(summary.wasCancelled)
        #expect(summary.items.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: imagesDir, includingPropertiesForKeys: nil
        )
        #expect(leftovers.isEmpty)
    }

    @Test("Progress reports every file and ends at the total")
    func ingestReportsProgress() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        for name in ["a.png", "b.png", "c.png"] {
            try writeTestImage(at: dir.appending(path: name), type: .png)
        }

        let scan = FolderImporter.scan(folder: dir)
        nonisolated(unsafe) var seen: [Int] = []
        _ = await FolderImporter.ingest(
            scan.candidates, into: dir.appending(path: "images")
        ) { done in
            seen.append(done)
        }

        #expect(seen == [1, 2, 3])
    }

    // MARK: Entry mapping

    @Test("Sidecar produces a manual entry, absence keeps tagged mode")
    func captionModeRule() {
        let items = [
            FolderImporter.ImportedItem(filename: "a.png", stem: "a", caption: "a woman"),
            FolderImporter.ImportedItem(filename: "b.png", stem: "b", caption: nil),
        ]

        let entries = FolderImporter.makeEntries(
            from: items, startPosition: 1, defaultConfigJSON: ""
        )

        #expect(entries[0].captionMode == .manual)
        #expect(entries[0].manualCaptionText == "a woman")
        #expect(entries[0].captionPreviewText == "a woman")
        #expect(entries[0].lockedCaptionText == nil)

        #expect(entries[1].captionMode == .tagged)
        #expect(entries[1].manualCaptionText.isEmpty)
    }

    @Test("Imported image is the entry's final")
    func importedImageIsFinal() {
        let items = [FolderImporter.ImportedItem(filename: "a.png", stem: "a", caption: nil)]
        let entries = FolderImporter.makeEntries(
            from: items, startPosition: 1, defaultConfigJSON: ""
        )

        #expect(entries[0].finalImage?.filename == "a.png")
        #expect(entries[0].images.count == 1)
    }

    @Test("Entry names come from filename stems, positions continue the project")
    func namingAndPositions() {
        let items = (1...3).map {
            FolderImporter.ImportedItem(filename: "\($0).png", stem: "maya_00\($0)", caption: nil)
        }
        let entries = FolderImporter.makeEntries(
            from: items, startPosition: 5, defaultConfigJSON: "{}"
        )

        #expect(entries.map(\.name) == ["maya_001", "maya_002", "maya_003"])
        #expect(entries.map(\.position) == [5, 6, 7])
        #expect(entries[0].generationConfigJSON == "{}")
    }

    @Test("An empty stem falls back to a positional name")
    func emptyStemFallback() {
        let items = [FolderImporter.ImportedItem(filename: "a.png", stem: "   ", caption: nil)]
        let entries = FolderImporter.makeEntries(
            from: items, startPosition: 7, defaultConfigJSON: ""
        )
        #expect(entries[0].name == "Entry 7")
    }

    // MARK: Round trip

    @Test("Imported entries round-trip through the bundle")
    func importedEntriesRoundTrip() throws {
        let categories = BuiltInCategory.defaultCategories
        var doc = ProjectDocument(name: "Imported", categories: categories)
        doc.entries = FolderImporter.makeEntries(
            from: [FolderImporter.ImportedItem(
                filename: "x.png", stem: "maya_001", caption: "a woman, standing"
            )],
            startPosition: 1,
            defaultConfigJSON: ""
        )

        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundleURL = tempDir.appending(path: "Imported.loraforge")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let schema = SchemaSnapshot(categories: categories, tags: [])
        try ProjectBundle.create(at: bundleURL, project: doc, schema: schema)

        let loaded = try ProjectBundle(url: bundleURL).readProject()
        #expect(loaded.entries.count == 1)
        #expect(loaded.entries[0].name == "maya_001")
        #expect(loaded.entries[0].captionMode == .manual)
        #expect(loaded.entries[0].manualCaptionText == "a woman, standing")
        #expect(loaded.entries[0].finalImage?.filename == "x.png")
    }

    @Test("Export then import preserves captions and images")
    func exportImportRoundTrip() async throws {
        let categories = BuiltInCategory.defaultCategories
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // A project with two captioned finals, backed by real PNG bytes.
        let bundleURL = tempDir.appending(path: "Source.loraforge")
        var doc = ProjectDocument(name: "Source", categories: categories)
        let captions = ["a woman, standing", "a woman, seated\n\nsecond paragraph"]
        try ProjectBundle.create(
            at: bundleURL, project: doc, schema: SchemaSnapshot(categories: categories, tags: [])
        )
        for (index, caption) in captions.enumerated() {
            let filename = "img\(index).png"
            try writeTestImage(
                at: bundleURL.appending(path: "images/\(filename)"), type: .png
            )
            var entry = EntryDocument(name: "e\(index)", position: index + 1)
            entry.images = [ImageDocument(filename: filename, rank: .final)]
            entry.captionMode = .manual
            entry.manualCaptionText = caption
            doc.entries.append(entry)
        }

        let exportDir = tempDir.appending(path: "export")
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        _ = try ExportManager.export(
            document: doc, bundleURL: bundleURL, to: exportDir,
            baseName: "maya", scope: .finalsOnly, categories: categories, allTags: [:]
        )

        // Now read that export straight back in.
        let scan = FolderImporter.scan(folder: exportDir)
        #expect(scan.candidates.count == 2)

        let imagesDir = tempDir.appending(path: "reimport")
        let summary = await FolderImporter.ingest(scan.candidates, into: imagesDir)
        let entries = FolderImporter.makeEntries(
            from: summary.items, startPosition: 1, defaultConfigJSON: ""
        )

        #expect(entries.map(\.name) == ["maya_001", "maya_002"])
        #expect(entries.map(\.manualCaptionText) == captions)
        #expect(entries.allSatisfy { $0.captionMode == .manual })
        #expect(entries.allSatisfy { $0.finalImage != nil })

        // Tier-1 byte copy means the exported pixels reach the new bundle untouched.
        for (index, item) in summary.items.enumerated() {
            let exported = try Data(contentsOf: exportDir.appending(path: "maya_00\(index + 1).png"))
            let imported = try Data(contentsOf: imagesDir.appending(path: item.filename))
            #expect(exported == imported)
        }
    }
}
