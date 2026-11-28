import Testing
import Foundation
@testable import LoRAForge

@MainActor
struct ImageViewerModelTests {

    private typealias Content = ImageViewerContent
    private typealias Selection = ImageViewerContent.Selection

    private let visible: Set<ImageRank> = [.final, .shortlist, .candidate]

    /// Three entries: A with images a1 a2 a3, B with none, C with c1.
    private func makeDocument() -> ProjectDocument {
        var doc = ProjectDocument(name: "Test", categories: [])
        var a = EntryDocument(name: "A", position: 1)
        a.images = [
            ImageDocument(filename: "a1.png"),
            ImageDocument(filename: "a2.png", rank: .shortlist),
            ImageDocument(filename: "a3.png"),
        ]
        let b = EntryDocument(name: "B", position: 2)
        var c = EntryDocument(name: "C", position: 3)
        c.images = [ImageDocument(filename: "c1.png", rank: .final)]
        doc.entries = [a, b, c]
        return doc
    }

    private func selection(_ doc: ProjectDocument, entry: Int, image: Int) -> Selection {
        Selection(entryID: doc.entries[entry].id, imageID: doc.entries[entry].images[image].id)
    }

    // MARK: - Content

    @Test func contentFiltersByRankAndKeepsOrder() {
        var doc = makeDocument()
        doc.entries[0].images[2].rank = .discarded
        let content = Content(document: doc, visibleRanks: visible)
        #expect(content.entries.map(\.name) == ["A", "B", "C"])
        #expect(content.entries[0].images.map(\.filename) == ["a1.png", "a2.png"])
        #expect(content.navigableEntries.map(\.name) == ["A", "C"])
    }

    @Test func rankChangeChangesContent() {
        var doc = makeDocument()
        let before = Content(document: doc, visibleRanks: visible)
        doc.entries[0].images[0].rank = .shortlist
        #expect(Content(document: doc, visibleRanks: visible) != before)
    }

    // MARK: - Selection

    @Test func newImageDoesNotMoveSelection() {
        var doc = makeDocument()
        let old = Content(document: doc, visibleRanks: visible)
        let current = selection(doc, entry: 0, image: 1)
        doc.entries[0].images.append(ImageDocument(filename: "a4.png"))
        let new = Content(document: doc, visibleRanks: visible)
        #expect(new.reconciled(current, from: old) == current)
    }

    @Test func removedImageMovesToSameIndex() {
        var doc = makeDocument()
        let old = Content(document: doc, visibleRanks: visible)
        let current = selection(doc, entry: 0, image: 1)
        let expected = selection(doc, entry: 0, image: 2)
        doc.entries[0].images.remove(at: 1)
        let new = Content(document: doc, visibleRanks: visible)
        #expect(new.reconciled(current, from: old) == expected)
    }

    @Test func hiddenLastImageMovesToNewLast() {
        var doc = makeDocument()
        let old = Content(document: doc, visibleRanks: visible)
        let current = selection(doc, entry: 0, image: 2)
        let expected = selection(doc, entry: 0, image: 1)
        doc.entries[0].images[2].rank = .discarded
        let new = Content(document: doc, visibleRanks: visible)
        #expect(new.reconciled(current, from: old) == expected)
    }

    @Test func emptiedEntryMovesToNextEntryWithImages() {
        var doc = makeDocument()
        let old = Content(document: doc, visibleRanks: visible)
        let current = selection(doc, entry: 0, image: 0)
        let expected = selection(doc, entry: 2, image: 0) // B has no images, so C
        for i in doc.entries[0].images.indices { doc.entries[0].images[i].rank = .discarded }
        let new = Content(document: doc, visibleRanks: visible)
        #expect(new.reconciled(current, from: old) == expected)
    }

    @Test func emptiedLastEntryMovesToPreviousEntry() {
        var doc = makeDocument()
        let old = Content(document: doc, visibleRanks: visible)
        let current = selection(doc, entry: 2, image: 0)
        let expected = selection(doc, entry: 0, image: 0)
        doc.entries[2].images.removeAll()
        let new = Content(document: doc, visibleRanks: visible)
        #expect(new.reconciled(current, from: old) == expected)
    }

    @Test func nothingLeftGivesNil() {
        var doc = makeDocument()
        let old = Content(document: doc, visibleRanks: visible)
        let current = selection(doc, entry: 0, image: 0)
        for e in doc.entries.indices { doc.entries[e].images.removeAll() }
        let new = Content(document: doc, visibleRanks: visible)
        #expect(new.reconciled(current, from: old) == nil)
    }

    @Test func deletedEntryMovesToItsNeighbour() {
        var doc = makeDocument()
        let old = Content(document: doc, visibleRanks: visible)
        let current = selection(doc, entry: 0, image: 0)
        let expected = selection(doc, entry: 2, image: 0)
        doc.entries.remove(at: 0)
        let new = Content(document: doc, visibleRanks: visible)
        #expect(new.reconciled(current, from: old) == expected)
    }

    // MARK: - References

    private func refs(_ names: [String]) -> [ReferenceImageDocument] {
        names.map { ReferenceImageDocument(filename: $0, contentHash: $0) }
    }

    @Test func referenceAddedKeepsSelection() {
        let images = refs(["r1", "r2"])
        let old = ReferenceViewerContent(referenceImages: images)
        let new = ReferenceViewerContent(referenceImages: images + refs(["r3"]))
        #expect(new.reconciled(images[1].id, from: old) == images[1].id)
    }

    @Test func referenceDeletedMovesToSameIndexOrCloses() {
        let images = refs(["r1", "r2", "r3"])
        let old = ReferenceViewerContent(referenceImages: images)
        let withoutMiddle = ReferenceViewerContent(referenceImages: [images[0], images[2]])
        #expect(withoutMiddle.reconciled(images[1].id, from: old) == images[2].id)
        let withoutLast = ReferenceViewerContent(referenceImages: [images[0], images[1]])
        #expect(withoutLast.reconciled(images[2].id, from: old) == images[1].id)
        #expect(ReferenceViewerContent(referenceImages: []).reconciled(images[0].id, from: old) == nil)
    }
}
