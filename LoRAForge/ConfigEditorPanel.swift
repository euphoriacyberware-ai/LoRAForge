import SwiftUI
import DTConfigEditorKit
import DTConfigBridge
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Diagnostic tallies for one configuration document, by severity.
struct DiagnosticCounts: Equatable {
    var errors = 0
    var warnings = 0
    var unused = 0

    init(_ diagnostics: [Diagnostic]) {
        for diagnostic in diagnostics {
            switch diagnostic.severity {
            case .error: errors += 1
            case .warning: warnings += 1
            case .inert: unused += 1
            }
        }
    }

    var isEmpty: Bool { errors == 0 && warnings == 0 && unused == 0 }
}

/// Whole-document rewrites offered by the editor's action bar.
enum ConfigEditorCommand {
    case format
    case sortKeys

    func transform(_ text: String) -> String {
        switch self {
        case .format: JSONFormatter.format(text)
        case .sortKeys: JSONFormatter.sortKeys(text)
        }
    }

    /// Runs through the attached text view as one undoable edit; falls back to rewriting
    /// the model directly when no text view is attached.
    @MainActor
    func perform(on model: ConfigEditorModel, actions: ConfigEditorActions?) {
        let handled: Bool
        switch self {
        case .format: handled = actions?.formatDocument() ?? false
        case .sortKeys: handled = actions?.sortDocumentKeys() ?? false
        }
        guard !handled else { return }
        let rewritten = transform(model.text)
        if rewritten != model.text { model.text = rewritten }
    }
}

/// The Draw Things configuration editor with its action bar and problems list.
///
/// Hosts keep their own persistence (`.onChange(of: model.text)`) and surrounding UI.
struct ConfigEditorPanel: View {
    let model: ConfigEditorModel

    @State private var actions = ConfigEditorActions()
    @AppStorage("configEditorShowProblems") private var showProblems = false
    @AppStorage("configEditorShowUnused") private var showUnused = false

    var body: some View {
        VStack(spacing: 6) {
            actionBar

            // The text view's coordinator captures the model once, so a new model
            // (e.g. after loading a preset) needs a new text view.
            ConfigTextView(model: model, actions: actions)
                .id(ObjectIdentifier(model))

            if showProblems {
                ProblemsListView(
                    diagnostics: model.diagnostics,
                    text: model.text,
                    showInert: $showUnused,
                    onSelect: { actions.select($0.range) },
                    onApplyFixIt: { actions.applyFixIt($0) }
                )
                .frame(maxHeight: 180)
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            status
            Spacer()
            Button {
                ConfigEditorCommand.format.perform(on: model, actions: actions)
            } label: {
                Label("Format", systemImage: "text.alignleft")
            }
            .help("Reformat the JSON with consistent indentation")

            Button {
                ConfigEditorCommand.sortKeys.perform(on: model, actions: actions)
            } label: {
                Label("Sort keys", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort object keys alphabetically")

            Button(action: copyJSON) {
                Label("Copy JSON", systemImage: "doc.on.doc")
            }
            .help("Copy the configuration JSON to the clipboard")

            Button(action: pasteJSON) {
                Label("Paste JSON", systemImage: "doc.on.clipboard")
            }
            .help("Replace the configuration with JSON from the clipboard")

            Toggle(isOn: $showProblems) {
                Label("Problems", systemImage: "list.bullet")
            }
            .toggleStyle(.button)
            .help(showProblems ? "Hide the problems list" : "Show the problems list")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.caption)
    }

    @ViewBuilder
    private var status: some View {
        let counts = DiagnosticCounts(model.diagnostics)
        HStack(spacing: 8) {
            if !model.isValid {
                Label("Invalid JSON", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if counts.errors > 0 {
                Label("\(counts.errors)", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
                    .help("\(counts.errors) error(s) in this configuration")
            }
            if counts.warnings > 0 {
                Label("\(counts.warnings)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("\(counts.warnings) warning(s) in this configuration")
            }
            if counts.unused > 0 {
                Label("\(counts.unused)", systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
                    .help("\(counts.unused) setting(s) in this configuration have no effect")
            }
            if model.isValid && counts.isEmpty {
                Label("No issues", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
        .labelStyle(.titleAndIcon)
    }

    // MARK: - Clipboard

    private func copyJSON() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.text, forType: .string)
        #else
        UIPasteboard.general.string = model.text
        #endif
    }

    private func pasteJSON() {
        #if os(macOS)
        let pasted = NSPasteboard.general.string(forType: .string)
        #else
        let pasted = UIPasteboard.general.string
        #endif
        guard let pasted, !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if !actions.replaceText(with: pasted), pasted != model.text {
            model.text = pasted
        }
    }
}
