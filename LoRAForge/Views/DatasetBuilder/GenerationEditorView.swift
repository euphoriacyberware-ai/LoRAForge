import SwiftUI
import DrawThingsQueue

struct GenerationEditorView: View {
    @ObservedObject var document: LoRAForgeDocument
    let entryIndex: Int
    @Environment(GenerationManager.self) private var manager: GenerationManager?

    @State private var generateCount = 1

    private var entry: DatasetEntry { document.entries[entryIndex] }
    private var settings: GenerationSettings { entry.generationSettings }

    var body: some View {
        Form {
            promptSection
            seedSection
            configSection
            generateSection
            pendingSection
        }
        .formStyle(.grouped)
        .navigationTitle("Generate — \(entry.name)")
    }

    // MARK: - Prompt

    private var promptSection: some View {
        Section("Prompt") {
            TextEditor(text: promptBinding)
                .frame(minHeight: 60)

            DisclosureGroup("Negative prompt") {
                TextEditor(text: negativePromptBinding)
                    .frame(minHeight: 40)
            }
        }
    }

    // MARK: - Seed

    private var seedSection: some View {
        Section("Seed") {
            Toggle("Use custom seed", isOn: useCustomSeedBinding)

            if settings.useCustomSeed {
                TextField("Seed", value: customSeedBinding, format: .number)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            } else {
                Text("A random seed will be assigned to each request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Config

    private var configSection: some View {
        Section {
            TextEditor(text: configJSONBinding)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
        } header: {
            Text("Configuration")
        } footer: {
            Label("Seed and batch size are managed by the app and will be ignored in this configuration.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Generate

    private var generateSection: some View {
        Section {
            HStack {
                Stepper("Count: \(generateCount)", value: $generateCount, in: 1...20)
                Spacer()
                Button {
                    guard let manager else { return }
                    manager.enqueue(entry: entry, in: document, count: generateCount)
                } label: {
                    Label("Generate", systemImage: "wand.and.stars")
                }
                .disabled(manager?.isConnected != true || settings.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if manager?.isConnected != true {
                Label("Connect to a Draw Things server in Settings to generate.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Pending

    @ViewBuilder
    private var pendingSection: some View {
        if let manager {
            let pending = manager.pendingRequests(for: document.metadata.id)
                .filter { $0.entryID == entry.id }
            if !pending.isEmpty {
                Section("Pending (\(pending.count))") {
                    ForEach(pending) { mapping in
                        HStack {
                            Text(mapping.prompt.prefix(50).description)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("seed: \(mapping.seed)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bindings

    private var promptBinding: Binding<String> {
        Binding(
            get: { settings.prompt },
            set: { document.entries[entryIndex].generationSettings.prompt = $0 }
        )
    }

    private var negativePromptBinding: Binding<String> {
        Binding(
            get: { settings.negativePrompt },
            set: { document.entries[entryIndex].generationSettings.negativePrompt = $0 }
        )
    }

    private var useCustomSeedBinding: Binding<Bool> {
        Binding(
            get: { settings.useCustomSeed },
            set: { document.entries[entryIndex].generationSettings.useCustomSeed = $0 }
        )
    }

    private var customSeedBinding: Binding<Int64> {
        Binding(
            get: { settings.customSeed },
            set: { document.entries[entryIndex].generationSettings.customSeed = $0 }
        )
    }

    private var configJSONBinding: Binding<String> {
        Binding(
            get: { settings.configurationJSON },
            set: { document.entries[entryIndex].generationSettings.configurationJSON = $0 }
        )
    }
}
