import Foundation
import SwiftData
import Testing
import TaggingCore
@testable import LoRAForge

private typealias Tag = TaggingCore.Tag

private func makeInMemoryContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: SDTagCategory.self, SDTag.self, SDKnownProject.self,
        configurations: config
    )
}

@Suite("Export")
@MainActor
struct ExportTests {

    private func makeDocument(entries: [DatasetEntry]) -> LoRAForgeDocument {
        let doc = LoRAForgeDocument()
        doc.entries = entries
        return doc
    }

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoRAForgeExportTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func finalsOnlyExportsCorrectFiles() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let catRepo = SwiftDataCategoryRepository(modelContext: context)
        try catRepo.seedBuiltInsIfNeeded()

        // Create a document with 3 entries, 2 with finals
        let doc = makeDocument(entries: [
            DatasetEntry(name: "Entry 1", images: [
                EntryImage(rank: .final, filename: "img1.png"),
                EntryImage(rank: .candidate, filename: "img2.png"),
            ]),
            DatasetEntry(name: "Entry 2", images: []),  // no final
            DatasetEntry(name: "Entry 3", images: [
                EntryImage(rank: .final, filename: "img3.png"),
            ]),
        ])
        // Add image data
        doc.imagesWrapper.addRegularFile(withContents: Data([0xFF]), preferredFilename: "img1.png")
        doc.imagesWrapper.addRegularFile(withContents: Data([0xFF]), preferredFilename: "img2.png")
        doc.imagesWrapper.addRegularFile(withContents: Data([0xFF]), preferredFilename: "img3.png")

        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = ExportService(document: doc, modelContext: context)
        let report = try service.export(to: dir, baseName: "maya", scope: .finalsOnly, clearFirst: false)

        #expect(report.exported == 2)
        #expect(report.skippedNoFinal == 1)
        #expect(report.totalImages == 2)
        #expect(report.totalSidecars == 2)

        // Check files exist — entry 2 has no final, so position 002 is skipped
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("maya_001.png").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("maya_001.txt").path))
        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("maya_002.png").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("maya_003.png").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("maya_003.txt").path))
    }

    @Test func emptyCaptionProducesEmptySidecar() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let doc = makeDocument(entries: [
            DatasetEntry(name: "Entry 1", images: [
                EntryImage(rank: .final, filename: "img1.png"),
            ]),
        ])
        doc.imagesWrapper.addRegularFile(withContents: Data([0xFF]), preferredFilename: "img1.png")

        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = ExportService(document: doc, modelContext: context)
        _ = try service.export(to: dir, baseName: "test", scope: .finalsOnly, clearFirst: false)

        let sidecarURL = dir.appendingPathComponent("test_001.txt")
        let content = try String(contentsOf: sidecarURL, encoding: .utf8)
        #expect(content == "")  // empty sidecar, no trailing newline when empty
    }

    @Test func captionedEntryExportsWithTrailingNewline() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        var entry = DatasetEntry(name: "Entry 1", images: [
            EntryImage(rank: .final, filename: "img1.png"),
        ])
        entry.captionMode = .manual
        entry.captionText = "A test caption"

        let doc = makeDocument(entries: [entry])
        doc.imagesWrapper.addRegularFile(withContents: Data([0xFF]), preferredFilename: "img1.png")

        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = ExportService(document: doc, modelContext: context)
        _ = try service.export(to: dir, baseName: "test", scope: .finalsOnly, clearFirst: false)

        let content = try String(contentsOf: dir.appendingPathComponent("test_001.txt"), encoding: .utf8)
        #expect(content == "A test caption\n")
    }

    @Test func positionIsProjectPositionNotExportPosition() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        // 5 entries, only entries 1, 3, 5 have finals
        let doc = makeDocument(entries: (1...5).map { i in
            DatasetEntry(name: "E\(i)", images: i % 2 == 1
                ? [EntryImage(rank: .final, filename: "img\(i).png")]
                : []
            )
        })
        for i in stride(from: 1, through: 5, by: 2) {
            doc.imagesWrapper.addRegularFile(withContents: Data([0xFF]), preferredFilename: "img\(i).png")
        }

        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = ExportService(document: doc, modelContext: context)
        _ = try service.export(to: dir, baseName: "x", scope: .finalsOnly, clearFirst: false)

        // Positions are 001, 003, 005 — not 001, 002, 003
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("x_001.png").path))
        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("x_002.png").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("x_003.png").path))
        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("x_004.png").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("x_005.png").path))
    }

    @Test func lockedEntryExportsStoredText() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        var entry = DatasetEntry(name: "E1", images: [
            EntryImage(rank: .final, filename: "img.png"),
        ])
        entry.captionMode = .tagged
        entry.isLocked = true
        entry.lockedText = "The locked caption"
        entry.captionText = "The locked caption"

        let doc = makeDocument(entries: [entry])
        doc.imagesWrapper.addRegularFile(withContents: Data([0xFF]), preferredFilename: "img.png")

        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = ExportService(document: doc, modelContext: context)
        _ = try service.export(to: dir, baseName: "t", scope: .finalsOnly, clearFirst: false)

        let content = try String(contentsOf: dir.appendingPathComponent("t_001.txt"), encoding: .utf8)
        #expect(content == "The locked caption\n")
    }

    @Test func additionalImagesGetDashSuffix() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let doc = makeDocument(entries: [
            DatasetEntry(name: "E1", images: [
                EntryImage(rank: .final, filename: "f.png"),
                EntryImage(rank: .shortlist, filename: "s1.png"),
                EntryImage(rank: .shortlist, filename: "s2.png"),
                EntryImage(rank: .candidate, filename: "c1.png"),
                EntryImage(rank: .discarded, filename: "d1.png"),
            ]),
        ])
        for name in ["f.png", "s1.png", "s2.png", "c1.png", "d1.png"] {
            doc.imagesWrapper.addRegularFile(withContents: Data([0xFF]), preferredFilename: name)
        }

        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = ExportService(document: doc, modelContext: context)
        _ = try service.export(to: dir, baseName: "m", scope: .allImages, clearFirst: false)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("m_001.png").path))       // final
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("m_001-1.png").path))     // shortlist
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("m_001-2.png").path))     // shortlist
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("m_001-3.png").path))     // candidate
        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("m_001-4.png").path))    // discarded excluded
    }
}
