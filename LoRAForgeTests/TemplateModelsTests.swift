import Testing
import Foundation
@testable import LoRAForge

@Suite("Template models") @MainActor
struct TemplateModelsTests {

    private func makeTemplate() -> Template {
        Template(
            id: UUID(),
            name: "Portraits",
            createdAt: Date(timeIntervalSince1970: 0),
            prompts: [
                TemplatePrompt(id: UUID(), order: 0, text: "close-up of <Character>", sourceSlotIndex: nil, generateCount: 1, entryName: "Close-up"),
                TemplatePrompt(id: UUID(), order: 1, text: "full body of <Character>", sourceSlotIndex: nil, generateCount: 2)
            ]
        )
    }

    @Test("Export envelope round-trip preserves entry names")
    func envelopeRoundTrip() throws {
        let envelope = TemplateExportEnvelope(version: TemplateExportEnvelope.currentVersion, template: makeTemplate())
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(TemplateExportEnvelope.self, from: data)
        #expect(decoded.template.prompts.map(\.entryName) == ["Close-up", nil])
        #expect(decoded.template.prompts.map(\.text) == ["close-up of <Character>", "full body of <Character>"])
    }

    @Test("Export files without entry names still import")
    func envelopeWithoutEntryName() throws {
        let json = """
        {"version":1,"template":{"name":"Old","createdAt":0,"prompts":[{"order":0,"text":"a photo","generateCount":1}]}}
        """
        let decoded = try JSONDecoder().decode(TemplateExportEnvelope.self, from: Data(json.utf8))
        #expect(decoded.template.prompts.count == 1)
        #expect(decoded.template.prompts[0].entryName == nil)
    }

    @Test("Stored templates without entry names still load")
    func libraryWithoutEntryName() throws {
        let id = UUID()
        let promptID = UUID()
        let json = """
        [{"id":"\(id.uuidString)","name":"Old","createdAt":0,"prompts":[{"id":"\(promptID.uuidString)","order":0,"text":"a photo","generateCount":1}]}]
        """
        let decoded = try JSONDecoder().decode([Template].self, from: Data(json.utf8))
        #expect(decoded[0].prompts[0].entryName == nil)
        #expect(decoded[0].prompts[0].text == "a photo")
    }
}
