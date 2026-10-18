import Testing
import Foundation
@testable import LoRAForge
import DTConfigEditorKit
import DTConfigBridge

@MainActor
struct ConfigEditorPanelTests {

    /// `ConfigEditorModel.diagnostics` arrives after a debounce, so validate directly.
    private func diagnostics(for text: String) -> [Diagnostic] {
        Validator.validate(Parser.parse(text))
    }

    @Test func countsErrorsAndWarningsBySeverity() {
        let counts = DiagnosticCounts(diagnostics(for: """
        {"model": "z_image_turbo_1.0_q6p.ckpt", "width": 1000, "notARealKey": 1}
        """))
        #expect(counts.errors >= 1)
        #expect(counts.warnings >= 1)
        #expect(!counts.isEmpty)
    }

    @Test func cleanConfigHasNoIssues() {
        let counts = DiagnosticCounts(diagnostics(for: #"{"model": "z_image_turbo_1.0_q6p.ckpt"}"#))
        #expect(counts.isEmpty)
    }

    @Test func formatFallsBackToRewritingModelWhenUnattached() {
        let minified = #"{"model":"z_image_turbo_1.0_q6p.ckpt","width":1024,"steps":8}"#
        let model = ConfigEditorModel(text: minified)
        ConfigEditorCommand.format.perform(on: model, actions: ConfigEditorActions())
        #expect(model.text == JSONFormatter.format(minified))
        #expect(model.text != minified)
    }

    @Test func sortKeysFallsBackToRewritingModelWhenUnattached() {
        let model = ConfigEditorModel(text: #"{"width": 1024, "model": "z_image_turbo_1.0_q6p.ckpt"}"#)
        ConfigEditorCommand.sortKeys.perform(on: model, actions: nil)
        let modelIndex = model.text.range(of: "\"model\"")!.lowerBound
        let widthIndex = model.text.range(of: "\"width\"")!.lowerBound
        #expect(modelIndex < widthIndex)
    }
}
