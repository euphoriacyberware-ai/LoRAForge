import Testing
import Foundation
@testable import LoRAForge
import TaggingCore
import DTConfigEditorKit
import DTConfigBridge

@MainActor
struct BulkEditsTests {

    // MARK: - Demotion

    private func entry(_ ranks: [ImageRank]) -> EntryDocument {
        var e = EntryDocument(name: "E", position: 1)
        e.images = ranks.map { ImageDocument(filename: UUID().uuidString, rank: $0) }
        return e
    }

    @Test func demotionCountsAndMoves() {
        var entries = [entry([.final, .candidate]), entry([.final, .shortlist]), entry([.candidate])]
        #expect(BulkDemotion.finalToShortlist.count(in: entries) == 2)
        #expect(BulkDemotion.finalToShortlist.entryCount(in: entries) == 2)
        BulkDemotion.finalToShortlist.apply(to: &entries)
        #expect(entries[0].images.map(\.rank) == [.shortlist, .candidate])
        #expect(entries[1].images.map(\.rank) == [.shortlist, .shortlist])
        #expect(BulkDemotion.finalToShortlist.count(in: entries) == 0)
    }

    @Test func candidateDemotionIsAProjectWideSweep() {
        var entries = [entry([.final, .candidate, .candidate]), entry([.candidate, .shortlist])]
        BulkDemotion.candidateToDiscarded.apply(to: &entries)
        #expect(entries[0].images.map(\.rank) == [.final, .discarded, .discarded])
        #expect(entries[1].images.map(\.rank) == [.discarded, .shortlist])
    }

    // MARK: - Tags

    private let single = TagCategory(name: "Framing", selectMode: .single, position: 0)
    private let multi = TagCategory(name: "Clothing", selectMode: .multi, position: 1)
    private let closeUp = UUID(), fullShot = UUID(), hat = UUID(), scarf = UUID(), gloves = UUID()

    private var tagCategory: [UUID: UUID] {
        [closeUp: single.id, fullShot: single.id, hat: multi.id, scarf: multi.id, gloves: multi.id]
    }

    private func edit(_ instructions: [UUID: BulkTagEdit.Instruction]) -> BulkTagEdit {
        BulkTagEdit(instructions: instructions, categories: [single, multi], tagCategory: tagCategory)
    }

    private func tagged(_ tags: [(UUID, Int)], mode: CaptionMode = .tagged, locked: Bool = false) -> EntryDocument {
        var e = EntryDocument(name: "E", position: 1)
        e.assignments = tags.map { AssignmentDocument(tagID: $0.0, selectionOrder: $0.1) }
        e.captionMode = mode
        if locked { e.lockedCaptionText = "frozen" }
        return e
    }

    @Test func singleSelectReplaces() {
        var entries = [tagged([(fullShot, 0), (hat, 0)])]
        edit([single.id: .apply([closeUp])]).apply(to: &entries)
        #expect(Set(entries[0].assignments.map(\.tagID)) == [closeUp, hat])
    }

    @Test func multiSelectAppendsWithoutDuplicates() {
        var entries = [tagged([(hat, 0), (scarf, 1)])]
        edit([multi.id: .apply([scarf, gloves])]).apply(to: &entries)
        #expect(entries[0].assignments.map(\.tagID) == [hat, scarf, gloves])
        #expect(entries[0].assignments.map(\.selectionOrder) == [0, 1, 2])
    }

    @Test func removeAllClearsOnlyThatCategory() {
        var entries = [tagged([(closeUp, 0), (hat, 0), (scarf, 1)])]
        edit([multi.id: .removeAll]).apply(to: &entries)
        #expect(entries[0].assignments.map(\.tagID) == [closeUp])
    }

    @Test func lockedEntriesAreSkippedAndCounted() {
        var entries = [tagged([(hat, 0)]), tagged([(hat, 0)], locked: true)]
        let bulk = edit([multi.id: .removeAll])
        let summary = bulk.summary(of: entries)
        #expect(summary == .init(changed: 1, captionsRewritten: 1, lockedSkipped: 1))
        let changed = bulk.apply(to: &entries)
        #expect(changed == [entries[0].id])
        #expect(entries[0].assignments.isEmpty)
        #expect(entries[1].assignments.map(\.tagID) == [hat])
    }

    @Test func manualEntriesChangeWithoutCaptionRewrite() {
        let entries = [tagged([], mode: .manual), tagged([], mode: .tagged)]
        let summary = edit([single.id: .apply([closeUp])]).summary(of: entries)
        #expect(summary == .init(changed: 2, captionsRewritten: 1, lockedSkipped: 0))
    }

    @Test func entriesAlreadyMatchingAreNotCounted() {
        let entries = [tagged([(closeUp, 0)]), tagged([])]
        let summary = edit([single.id: .apply([closeUp])]).summary(of: entries)
        #expect(summary.changed == 1)
    }

    // MARK: - Generation settings

    @Test func onlyChosenKeysChange() throws {
        let json = """
        {
          "customKey": "kept",
          "model": "z_image.ckpt",
          "steps": 8
        }
        """
        let loras = GenerationSettingsWriter.loras([LoRAConfig(file: "style.ckpt", weight: 0.7, mode: .all)])
        let bulk = BulkGenerationEdit(values: [("loras", loras)])
        let result = ConfigEditorModel(text: bulk.edited(json))
        let config = try #require(result.configuration)
        #expect(config.model == "z_image.ckpt")
        #expect(config.steps == 8)
        #expect(config.loras.map(\.file) == ["style.ckpt"])
        #expect(result.text.contains(#""customKey": "kept""#))
    }

    @Test func lorasAreReplacedAsAWhole() throws {
        let json = #"{"model": "z.ckpt", "loras": [{"file": "a.ckpt", "mode": "all", "weight": 1.0}, {"file": "b.ckpt", "mode": "all", "weight": 1.0}]}"#
        let loras = GenerationSettingsWriter.loras([LoRAConfig(file: "c.ckpt", weight: 0.5, mode: .all)])
        let result = ConfigEditorModel(text: BulkGenerationEdit(values: [("loras", loras)]).edited(json))
        #expect(try #require(result.configuration).loras.map(\.file) == ["c.ckpt"])
    }

    @Test func emptyConfigStartsFromDefaults() throws {
        let bulk = BulkGenerationEdit(values: [("steps", GenerationSettingsWriter.int(30))])
        let config = try #require(ConfigEditorModel(text: bulk.edited("")).configuration)
        #expect(config.steps == 30)
    }

    @Test func changedCountIgnoresEntriesAlreadyMatching() {
        let bulk = BulkGenerationEdit(values: [("steps", GenerationSettingsWriter.int(30))])
        var same = EntryDocument(name: "A", position: 1)
        same.generationConfigJSON = bulk.edited(#"{"steps": 8}"#)
        var different = EntryDocument(name: "B", position: 2)
        different.generationConfigJSON = #"{"steps": 8}"#
        #expect(bulk.changedCount(in: [same, different]) == 1)
    }
}
