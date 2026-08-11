import SwiftUI
import DTConfigEditorKit
import DTConfigBridge
import DrawThingsClient

struct ConfigLibraryView: View {
    @Environment(GenerationPresetRepository.self) private var presetRepo
    @State private var presets: [SDGenerationPreset] = []
    @State private var selectedPresetID: UUID?
    @State private var configModel: ConfigEditorModel?
    @State private var newName = ""
    @State private var presetToDelete: SDGenerationPreset?
    @State private var presetToRename: SDGenerationPreset?
    @State private var renameName = ""

    var body: some View {
        HStack(spacing: 0) {
            presetList
                .frame(width: 250)
            Divider()
            configEditor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Config Library")
        .onAppear(perform: refresh)
    }

    // MARK: - Preset List

    private var presetList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedPresetID) {
                ForEach(presets) { preset in
                    Text(preset.name)
                        .tag(preset.id)
                        .contextMenu {
                            Button("Rename") {
                                renameName = preset.name
                                presetToRename = preset
                            }
                            Button("Duplicate") { duplicatePreset(preset) }
                            Divider()
                            Button("Delete", role: .destructive) { presetToDelete = preset }
                        }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedPresetID) { _, newID in
                if let newID, let preset = presets.first(where: { $0.id == newID }) {
                    configModel = ConfigEditorModel(text: preset.configJSON)
                }
            }

            Divider()

            HStack {
                TextField("New preset", text: $newName)
                    .textFieldStyle(.roundedBorder)
                Button { createPreset() } label: {
                    Image(systemName: "plus")
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
        }
        .alert("Delete preset?", isPresented: .init(
            get: { presetToDelete != nil },
            set: { if !$0 { presetToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { presetToDelete = nil }
        } message: {
            if let preset = presetToDelete {
                Text("Delete '\(preset.name)'?")
            }
        }
        .alert("Rename preset", isPresented: .init(
            get: { presetToRename != nil },
            set: { if !$0 { presetToRename = nil } }
        )) {
            TextField("Name", text: $renameName)
            Button("Rename") { performRename() }
            Button("Cancel", role: .cancel) { presetToRename = nil }
        }
    }

    // MARK: - Config Editor

    @ViewBuilder
    private var configEditor: some View {
        if let selectedID = selectedPresetID,
           let preset = presets.first(where: { $0.id == selectedID }),
           let configModel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(preset.name)
                        .font(.headline)
                    Spacer()
                    if configModel.isValid {
                        Label("Valid", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("Invalid JSON", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                ConfigTextView(model: configModel)
                    .id(selectedID)
                    .onChange(of: configModel.text) {
                        if let idx = presets.firstIndex(where: { $0.id == selectedID }) {
                            presets[idx].configJSON = configModel.text
                            try? presetRepo.updatePreset(presets[idx])
                        }
                    }
            }
            .padding()
        } else {
            ContentUnavailableView(
                "Select a configuration",
                systemImage: "slider.horizontal.3",
                description: Text("Choose a preset to view and edit, or create a new one.")
            )
        }
    }

    // MARK: - Actions

    private func refresh() {
        presets = (try? presetRepo.allPresets()) ?? []
    }

    private func createPreset() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let defaultJSON = ConfigurationInterop.text(
            from: DrawThingsConfiguration(), style: .nonDefaultOnly
        )
        if let preset = try? presetRepo.addPreset(name: name, configJSON: defaultJSON) {
            newName = ""
            refresh()
            selectedPresetID = preset.id
        }
    }

    private func duplicatePreset(_ preset: SDGenerationPreset) {
        _ = try? presetRepo.addPreset(name: "\(preset.name) Copy", configJSON: preset.configJSON)
        refresh()
    }

    private func performRename() {
        guard let preset = presetToRename else { return }
        let trimmed = renameName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { presetToRename = nil; return }
        preset.name = trimmed
        try? presetRepo.updatePreset(preset)
        presetToRename = nil
        refresh()
    }

    private func performDelete() {
        guard let preset = presetToDelete else { return }
        if selectedPresetID == preset.id {
            selectedPresetID = nil
            configModel = nil
        }
        try? presetRepo.deletePreset(preset)
        presetToDelete = nil
        refresh()
    }
}
