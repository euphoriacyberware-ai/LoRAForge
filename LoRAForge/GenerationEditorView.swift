import SwiftUI

struct GenerationEditorView: View {
    @Binding var entry: EntryDocument
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingPromptTab = true // true = prompt, false = negative

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                promptPanel
                    .frame(minWidth: 220, idealWidth: 280)
                Divider()
                seedAndReferencesPanel
                    .frame(minWidth: 200, idealWidth: 240)
                Divider()
                configPanel
                    .frame(minWidth: 240, idealWidth: 300)
            }
            .navigationTitle("Entry generation editor")
            #if os(macOS)
            .frame(minWidth: 700, minHeight: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Left: Name + Prompt

    private var promptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Name", text: $entry.name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: entry.name) { onChanged() }
            }

            Picker("", selection: $showingPromptTab) {
                Text("Prompt").tag(true)
                Text("Negative").tag(false)
            }
            .pickerStyle(.segmented)

            if showingPromptTab {
                TextEditor(text: $entry.generationPrompt)
                    .font(.body)
                    .onChange(of: entry.generationPrompt) { onChanged() }
            } else {
                TextEditor(text: $entry.generationNegativePrompt)
                    .font(.body)
                    .onChange(of: entry.generationNegativePrompt) { onChanged() }
            }
        }
        .padding()
    }

    // MARK: - Center: Seed + Reference Images

    private var seedAndReferencesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Seed
            HStack {
                Text("Seed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Use custom", isOn: $entry.useCustomSeed)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: entry.useCustomSeed) { onChanged() }
            }

            HStack {
                TextField("0", value: Binding(
                    get: { entry.generationSeed ?? 0 },
                    set: { entry.generationSeed = $0; onChanged() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .disabled(!entry.useCustomSeed)

                Button {
                    entry.generationSeed = Int64(Int.random(in: 0...Int(UInt32.max)))
                    onChanged()
                } label: {
                    Image(systemName: "dice")
                }
                .disabled(!entry.useCustomSeed)
            }

            Divider()

            // Reference Images (phase 10 — stubs)
            Text("Reference images")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.1))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.quaternary)
                        }
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Right: Generation Configuration

    private var configPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Generation configuration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Use custom", isOn: $entry.useCustomConfig)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: entry.useCustomConfig) { onChanged() }
            }

            if entry.useCustomConfig {
                TextEditor(text: $entry.generationConfigJSON)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: entry.generationConfigJSON) { onChanged() }
            } else {
                TextEditor(text: .constant(defaultConfigPreview))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .disabled(true)
            }

            if !entry.useCustomConfig {
                Text("Turn on Use custom to edit.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text("Seed and batch size are overridden by the app.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private var defaultConfigPreview: String {
        """
        {
          "steps": 30,
          "cfg_scale": 7.0,
          "sampler": "dpmpp_2m",
          "scheduler": "karras",
          "width": 1024,
          "height": 1024,
          "batch_size": 1
        }
        """
    }
}
