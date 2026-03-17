import SwiftUI
import AppKit

struct ConfigurationEditorSheet: View {
    @Binding var isPresented: Bool
    @Binding var configurationJSON: String
    let title: String

    @StateObject private var presetManager = ConfigurationPresetManager.shared
    @State private var editText: String = ""
    @State private var validationError: String?
    @State private var showingSaveAlert = false
    @State private var newPresetName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            Text(title)
                .font(.headline)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            // Toolbar row
            HStack {
                presetsMenu

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(editText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    if let str = NSPasteboard.general.string(forType: .string) {
                        editText = str
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    formatJSON()
                } label: {
                    Label("Format", systemImage: "text.alignleft")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(validationError != nil)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // JSON editor
            TextEditor(text: $editText)
                .font(.system(.body, design: .monospaced))
                .border(validationError != nil ? Color.red.opacity(0.5) : Color.secondary.opacity(0.3))
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onChange(of: editText) {
                    validate()
                }

            // Validation indicator
            HStack {
                if let error = validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Valid JSON", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
            }
            .padding(.horizontal)

            Divider()

            // Bottom bar
            HStack {
                if let error = validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    configurationJSON = trimmed.isEmpty ? "{}" : trimmed
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validationError != nil)
            }
            .padding()
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 450, idealHeight: 550)
        .onAppear {
            editText = configurationJSON
            validate()
        }
        .alert("Save Preset", isPresented: $showingSaveAlert) {
            TextField("Preset name", text: $newPresetName)
            Button("Cancel", role: .cancel) {
                newPresetName = ""
            }
            Button("Save") {
                let preset = ConfigurationPreset(
                    id: UUID(),
                    name: newPresetName,
                    json: editText,
                    createdAt: Date()
                )
                presetManager.add(preset)
                newPresetName = ""
            }
            .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for this preset.")
        }
    }

    // MARK: - Presets Menu

    private var presetsMenu: some View {
        Menu {
            if presetManager.presets.isEmpty {
                Text("No saved presets")
            } else {
                ForEach(presetManager.presets) { preset in
                    Button(preset.name) {
                        editText = preset.json
                    }
                }
            }

            Divider()

            Button("Save as New Preset\u{2026}") {
                showingSaveAlert = true
            }

            if !presetManager.presets.isEmpty {
                Menu("Update Preset") {
                    ForEach(presetManager.presets) { preset in
                        Button(preset.name) {
                            var updated = preset
                            updated.json = editText
                            presetManager.update(updated)
                        }
                    }
                }

                Divider()

                Menu("Delete Preset") {
                    ForEach(presetManager.presets) { preset in
                        Button(preset.name, role: .destructive) {
                            presetManager.delete(id: preset.id)
                        }
                    }
                }
            }
        } label: {
            Label("Presets", systemImage: "list.bullet")
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
    }

    // MARK: - Validation

    private func validate() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            validationError = nil
            return
        }

        guard let data = trimmed.data(using: .utf8) else {
            validationError = "Invalid encoding"
            return
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data)
            validationError = nil
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func formatJSON() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: formatted, encoding: .utf8) else { return }
        editText = str
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Configuration Editor Sheet") {
    ConfigurationEditorSheet(
        isPresented: .constant(true),
        configurationJSON: .constant("{\n  \"steps\": 20,\n  \"seed\": 0\n}"),
        title: "DrawThings Configuration"
    )
}
#endif
