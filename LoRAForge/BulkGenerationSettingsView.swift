import SwiftUI
import DTConfigEditorKit
import DTConfigBridge
import DrawThingsClient

/// Applies chosen generation settings to every entry, leaving each entry's other settings alone.
///
/// The form starts from the project default configuration. Each setting has an Apply checkbox,
/// ticked automatically when the setting is edited; only ticked settings are written.
struct BulkGenerationSettingsView: View {
    @Binding var document: ProjectDocument
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var model: ConfigEditorModel?
    @State private var applyKeys: Set<String> = []
    @State private var confirming = false

    private var edit: BulkGenerationEdit? {
        guard let config = model?.configuration, !applyKeys.isEmpty else { return nil }
        return BulkGenerationEdit(keys: applyKeys, from: config)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tick the settings to apply to every entry; editing a setting ticks it. Each entry keeps its other settings. LoRAs are applied as a whole list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()

                Divider()

                if let model {
                    GenerationSettingsForm(model: model, applyKeys: $applyKeys)
                }

                Divider()

                Text("Seed and batch size are overridden by the app.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(8)
            }
            .navigationTitle("Bulk generation settings")
            .frame(minWidth: 1200, idealWidth: 1300, minHeight: 800, idealHeight: 850)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply…") { confirming = true }
                        .disabled(edit?.isEmpty ?? true)
                }
            }
            .alert("Apply generation settings?", isPresented: $confirming) {
                if let edit, edit.changedCount(in: document.entries) > 0 {
                    Button("Apply") { apply(edit) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let edit {
                    Text(summaryText(edit))
                }
            }
        }
        .onAppear {
            let json = document.defaultGenerationConfigJSON
            model = json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ConfigEditorModel(DrawThingsConfiguration(), style: .nonDefaultOnly)
                : ConfigEditorModel(text: json)
        }
    }

    private func summaryText(_ edit: BulkGenerationEdit) -> String {
        let changed = edit.changedCount(in: document.entries)
        let names = ListFormatter.localizedString(byJoining: edit.settingNames)
        guard changed > 0 else {
            return "Every entry already has these settings: \(names)."
        }
        let total = document.entries.count
        let entries = "\(changed) of \(total) entr\(total == 1 ? "y" : "ies")"
        return "Will set \(names) on \(entries). Other settings are unchanged."
    }

    private func apply(_ edit: BulkGenerationEdit) {
        var entries = document.entries
        edit.apply(to: &entries)
        document.entries = entries
        onChanged()
        dismiss()
    }
}
