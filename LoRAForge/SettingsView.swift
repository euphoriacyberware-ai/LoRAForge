import SwiftUI
import DTConfigEditorKit
import DTConfigBridge
import DrawThingsClient

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsTab()
            }
            Tab("Draw Things", systemImage: "paintbrush") {
                DrawThingsSettingsTab()
            }
            Tab("Ollama", systemImage: "brain") {
                OllamaSettingsTab()
            }
            Tab("Tagging", systemImage: "tag") {
                Text("Tagging settings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Tab("Generation", systemImage: "wand.and.stars") {
                GenerationSettingsTab()
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 300)
        #endif
    }
}

private struct GeneralSettingsTab: View {
    @Environment(LibraryManager.self) private var library

    var body: some View {
        Form {
            Section("Library folder") {
                LabeledContent("Location") {
                    Text(library.libraryURL.path(percentEncoded: false))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Projects") {
                    Text("\(library.projects.count)")
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DrawThingsSettingsTab: View {
    @Environment(GenerationService.self) private var generation

    var body: some View {
        @Bindable var generation = generation
        Form {
            Section("Server") {
                TextField("Address", text: $generation.serverAddress)
                Toggle("Use TLS", isOn: $generation.useTLS)
                TextField("Shared secret", text: $generation.sharedSecret)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    if generation.isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Disconnected", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(generation.isConnected ? "Disconnect" : "Connect") {
                        if generation.isConnected {
                            generation.disconnect()
                        } else {
                            generation.connect()
                        }
                    }
                }
                if let error = generation.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            Section("Queue") {
                LabeledContent("Pending") { Text("\(generation.pendingCount)") }
                LabeledContent("Processing") { Text(generation.isProcessing ? "Yes" : "No") }
                if generation.isPaused {
                    Label("Paused", systemImage: "pause.circle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OllamaSettingsTab: View {
    @Environment(OllamaRepository.self) private var repo
    @State private var profiles: [SDOllamaProfile] = []
    @State private var editingProfile: SDOllamaProfile?
    @State private var showingNew = false

    // New profile fields
    @State private var newName = ""
    @State private var newEndpoint = "http://localhost:11434"
    @State private var newModel = "llava"
    @State private var newInstruction = "Describe this image in detail."

    var body: some View {
        Form {
            Section("Profiles") {
                ForEach(profiles) { profile in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.name).font(.headline)
                            Text("\(profile.model) — \(profile.endpoint)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editingProfile = profile }
                        Button(role: .destructive) {
                            try? repo.deleteProfile(profile)
                            refresh()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
                if profiles.isEmpty {
                    Text("No profiles configured.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("New profile") {
                TextField("Name", text: $newName)
                TextField("Endpoint", text: $newEndpoint)
                TextField("Model", text: $newModel)
                TextField("Instruction", text: $newInstruction, axis: .vertical)
                    .lineLimit(3...6)
                Button("Add profile") {
                    guard !newName.isEmpty else { return }
                    _ = try? repo.addProfile(
                        name: newName, endpoint: newEndpoint,
                        model: newModel, instruction: newInstruction
                    )
                    newName = ""
                    refresh()
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: refresh)
        .sheet(item: $editingProfile) { profile in
            OllamaProfileEditor(profile: profile, repo: repo, onSave: refresh)
        }
    }

    private func refresh() {
        profiles = (try? repo.allProfiles()) ?? []
    }
}

private struct OllamaProfileEditor: View {
    let profile: SDOllamaProfile
    let repo: OllamaRepository
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var endpoint: String
    @State private var model: String
    @State private var instruction: String

    init(profile: SDOllamaProfile, repo: OllamaRepository, onSave: @escaping () -> Void) {
        self.profile = profile
        self.repo = repo
        self.onSave = onSave
        _name = State(initialValue: profile.name)
        _endpoint = State(initialValue: profile.endpoint)
        _model = State(initialValue: profile.model)
        _instruction = State(initialValue: profile.instruction)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Endpoint", text: $endpoint)
                TextField("Model", text: $model)
                TextField("Instruction", text: $instruction, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)
            .navigationTitle("Edit profile")
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 280)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.name = name
                        profile.endpoint = endpoint
                        profile.model = model
                        profile.instruction = instruction
                        try? repo.updateProfile(profile)
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct GenerationSettingsTab: View {
    @Environment(GenerationPresetRepository.self) private var presetRepo
    @State private var presets: [SDGenerationPreset] = []
    @State private var configModel = ConfigEditorModel(
        DrawThingsConfiguration(), style: .nonDefaultOnly
    )
    @State private var newPresetName = ""
    @State private var editingPreset: SDGenerationPreset?

    var body: some View {
        HStack(spacing: 0) {
            // Left: preset library
            VStack(alignment: .leading, spacing: 8) {
                Text("Configuration presets")
                    .font(.headline)

                List {
                    ForEach(presets) { preset in
                        HStack {
                            Text(preset.name)
                            Spacer()
                            Button("Load") { loadPreset(preset) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        .contextMenu {
                            Button("Load into default") { loadPreset(preset) }
                            Button("Update from current") {
                                preset.configJSON = configModel.text
                                try? presetRepo.updatePreset(preset)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                try? presetRepo.deletePreset(preset)
                                refresh()
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 150)

                HStack {
                    TextField("New preset name", text: $newPresetName)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") { saveAsPreset() }
                        .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .frame(width: 220)
            .padding()

            Divider()

            // Right: default config editor
            VStack(alignment: .leading, spacing: 8) {
                Text("App default configuration")
                    .font(.headline)
                Text("New projects inherit this. Seed and batch size are overridden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ConfigTextView(model: configModel)

                HStack {
                    if configModel.isValid {
                        Label("Valid", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("Invalid JSON", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refresh()
            if let saved = UserDefaults.standard.string(forKey: "defaultGenerationConfig"),
               !saved.isEmpty {
                configModel = ConfigEditorModel(text: saved)
            }
        }
        .onChange(of: configModel.text) {
            UserDefaults.standard.set(configModel.text, forKey: "defaultGenerationConfig")
        }
    }

    private func refresh() {
        presets = (try? presetRepo.allPresets()) ?? []
    }

    private func loadPreset(_ preset: SDGenerationPreset) {
        configModel = ConfigEditorModel(text: preset.configJSON)
    }

    private func saveAsPreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        _ = try? presetRepo.addPreset(name: name, configJSON: configModel.text)
        newPresetName = ""
        refresh()
    }
}

#Preview {
    SettingsView()
}
