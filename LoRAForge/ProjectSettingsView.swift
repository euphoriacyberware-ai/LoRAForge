import SwiftUI
import TaggingCore
import DTConfigEditorKit
import DTConfigBridge
import DrawThingsClient

struct ProjectSettingsView: View {
    @Binding var document: ProjectDocument
    let onChanged: () -> Void

    @Environment(TagRepository.self) private var repo
    @Environment(GenerationPresetRepository.self) private var presetRepo
    @Environment(\.dismiss) private var dismiss

    @State private var projectName: String
    @State private var categories: [TagCategory] = []
    @State private var presets: [SDGenerationPreset] = []
    @State private var configModel: ConfigEditorModel?

    init(document: Binding<ProjectDocument>, onChanged: @escaping () -> Void) {
        self._document = document
        self.onChanged = onChanged
        self._projectName = State(initialValue: document.wrappedValue.name)
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left pane: project + categories
                leftPane
                Divider()
                // Right pane: generation config
                rightPane
            }
            .navigationTitle("Project settings")
            #if os(macOS)
            .frame(minWidth: 800, minHeight: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                categories = (try? repo.allCategories()) ?? []
                presets = (try? presetRepo.allPresets()) ?? []
                initConfigModel()
            }
        }
    }

    // MARK: - Left Pane

    private var leftPane: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $projectName)
                    .onChange(of: projectName) {
                        document.name = projectName
                        onChanged()
                    }
            }

            Section("Category order and enabled state") {
                Text("These settings are independent of the app defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(orderedCategories) { cat in
                    Toggle(isOn: Binding(
                        get: { document.categoryEnabled[cat.id] ?? true },
                        set: {
                            document.categoryEnabled[cat.id] = $0
                            onChanged()
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text(cat.name)
                            if let prefix = cat.prefix, !prefix.isEmpty {
                                Text(prefix)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .onMove(perform: moveCategories)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 300)
    }

    // MARK: - Right Pane

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default generation configuration")
                .font(.headline)
            Text("Entries in this project use this config unless they override it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Preset picker
            if !presets.isEmpty {
                HStack {
                    Text("Load preset:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Menu("Presets") {
                        ForEach(presets) { preset in
                            Button(preset.name) { loadPreset(preset) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            if let configModel {
                ConfigTextView(model: configModel)
                    .onChange(of: configModel.text) {
                        document.defaultGenerationConfigJSON = configModel.text
                        onChanged()
                    }
            }

            HStack {
                if configModel?.isValid == true {
                    Label("Valid", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if configModel != nil {
                    Label("Invalid JSON", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Text("Seed and batch size are overridden by the app.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Helpers

    private var orderedCategories: [TagCategory] {
        document.categoryOrder.compactMap { catID in
            categories.first { $0.id == catID }
        }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var order = document.categoryOrder
        order.move(fromOffsets: source, toOffset: destination)
        if let subjectIdx = order.firstIndex(of: BuiltInCategory.subject.id), subjectIdx != 0 {
            return
        }
        document.categoryOrder = order
        onChanged()
    }

    private func initConfigModel() {
        let json = document.defaultGenerationConfigJSON
        if json.trimmingCharacters(in: .whitespaces).isEmpty {
            configModel = ConfigEditorModel(DrawThingsConfiguration(), style: .nonDefaultOnly)
            document.defaultGenerationConfigJSON = configModel?.text ?? ""
        } else {
            configModel = ConfigEditorModel(text: json)
        }
    }

    private func loadPreset(_ preset: SDGenerationPreset) {
        configModel = ConfigEditorModel(text: preset.configJSON)
        document.defaultGenerationConfigJSON = preset.configJSON
        onChanged()
    }
}
