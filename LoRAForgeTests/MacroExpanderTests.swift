import Testing
import Foundation
@testable import LoRAForge
import TaggingCore

@Suite("Macro expansion") @MainActor
struct MacroExpanderTests {

    private let character = ProjectMacro(name: "Character Description", text: "a tall woman with red hair")
    private let style = ProjectMacro(name: "Style", text: "studio lighting")

    @Test("Expands defined references")
    func expandsDefined() {
        let result = MacroExpander.expand("photo of <Character Description>, <Style>", macros: [character, style])
        #expect(result.text == "photo of a tall woman with red hair, studio lighting")
        #expect(!result.hasWarnings)
    }

    @Test("Names match ignoring case and surrounding spaces")
    func caseInsensitive() {
        let result = MacroExpander.expand("<character description> and < STYLE >", macros: [character, style])
        #expect(result.text == "a tall woman with red hair and studio lighting")
    }

    @Test("Undefined references are sent as written and reported once")
    func unresolved() {
        let result = MacroExpander.expand("<Outfit>, <Style>, <outfit>", macros: [style])
        #expect(result.text == "<Outfit>, studio lighting, <outfit>")
        #expect(result.unresolved == ["Outfit"])
        #expect(result.empty.isEmpty)
    }

    @Test("Empty macros expand to nothing and are reported")
    func emptyMacro() {
        let stub = ProjectMacro(name: "Outfit")
        let result = MacroExpander.expand("a<Outfit>b", macros: [stub])
        #expect(result.text == "ab")
        #expect(result.empty == ["Outfit"])
        #expect(result.unresolved.isEmpty)
    }

    @Test("Expansion is single-pass")
    func noNesting() {
        let outer = ProjectMacro(name: "Outer", text: "wearing <Style>")
        let result = MacroExpander.expand("<Outer>", macros: [outer, style])
        #expect(result.text == "wearing <Style>")
    }

    @Test("Unclosed or empty brackets are left alone")
    func literalBrackets() {
        let text = "a < b, <>, x > y, <Style"
        let result = MacroExpander.expand(text, macros: [style])
        #expect(result.text == text)
        #expect(!result.hasWarnings)
    }

    @Test("References spanning a line break do not match")
    func noMultiline() {
        let text = "<Sty\nle>"
        #expect(MacroExpander.references(in: text).isEmpty)
    }

    @Test("References are de-duplicated in first-seen order")
    func referencesOrder() {
        #expect(MacroExpander.references(in: "<B> <a> <b> <C>") == ["B", "a", "C"])
    }

    @Test("Name validation")
    func nameValidation() {
        let existing = [character, style]
        #expect(MacroExpander.validateName("  ", existing: existing) == .empty)
        #expect(MacroExpander.validateName("a<b", existing: existing) == .invalidCharacters)
        #expect(MacroExpander.validateName("a\nb", existing: existing) == .invalidCharacters)
        #expect(MacroExpander.validateName("style", existing: existing) == .duplicate)
        #expect(MacroExpander.validateName("Style", existing: existing, excluding: style.id) == nil)
        #expect(MacroExpander.validateName("Outfit", existing: existing) == nil)
    }

    @Test("Usage and undefined references across entries")
    func usageAcrossEntries() {
        var a = EntryDocument(name: "A", position: 1)
        a.generationPrompt = "<Style>, <Outfit>"
        var b = EntryDocument(name: "B", position: 2)
        b.generationNegativePrompt = "<style>"
        let c = EntryDocument(name: "C", position: 3)
        let entries = [a, b, c]
        #expect(MacroExpander.usageCount(of: "Style", in: entries) == 2)
        #expect(MacroExpander.undefinedReferences(in: entries, macros: [style]) == ["Outfit"])
    }

    @Test("Template load adds stubs only for missing names")
    func templateStubs() {
        var macros = [style]
        let added = MacroExpander.addStubs(
            for: ["<Character Description>, <style>", "<character description> <Outfit>"],
            to: &macros
        )
        #expect(added == ["Character Description", "Outfit"])
        #expect(macros.map(\.name) == ["Style", "Character Description", "Outfit"])
        #expect(macros.dropFirst().allSatisfy { $0.text.isEmpty })
    }

    // MARK: - Persistence

    @Test("Project macros round-trip through the bundle")
    func bundleRoundTrip() throws {
        let categories = BuiltInCategory.defaultCategories
        var doc = ProjectDocument(name: "Macros", categories: categories)
        doc.macros = [character, style]

        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundleURL = tempDir.appending(path: "Test.loraforge")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try ProjectBundle.create(at: bundleURL, project: doc, schema: SchemaSnapshot(categories: categories, tags: []))
        let loaded = try ProjectBundle(url: bundleURL).readProject()
        #expect(loaded.macros == [character, style])
    }

    @Test("Projects saved before macros decode with none")
    func legacyProjectDecodes() throws {
        let doc = ProjectDocument(name: "Legacy", categories: BuiltInCategory.defaultCategories)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try #require(JSONSerialization.jsonObject(with: encoder.encode(doc)) as? [String: Any])
        json.removeValue(forKey: "macros")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(ProjectDocument.self, from: data)
        #expect(loaded.id == doc.id)
        #expect(loaded.macros.isEmpty)
    }

    @Test("Provenance keeps the source prompt and restores it")
    func provenanceSource() throws {
        let expanded = ImageProvenance(
            prompt: "a tall woman", negativePrompt: "blurry", seed: 1,
            sourcePrompt: "<Character Description>"
        )
        let data = try JSONEncoder().encode(expanded)
        let loaded = try JSONDecoder().decode(ImageProvenance.self, from: data)
        #expect(loaded.editablePrompt == "<Character Description>")
        #expect(loaded.editableNegativePrompt == "blurry")

        // Images recorded before macros have no source keys.
        let legacy = #"{"prompt":"p","negativePrompt":"n","seed":3}"#
        let old = try JSONDecoder().decode(ImageProvenance.self, from: Data(legacy.utf8))
        #expect(old.sourcePrompt == nil)
        #expect(old.editablePrompt == "p")
    }
}
