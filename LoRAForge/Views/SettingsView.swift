import SwiftUI
import SwiftData
import DrawThingsQueue

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                Text("General settings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Tab("Draw Things", systemImage: "paintbrush") {
                DrawThingsSettingsTab()
            }
            Tab("Ollama", systemImage: "text.bubble") {
                OllamaSettingsTab()
            }
            Tab("Tagging", systemImage: "tag") {
                Text("Tagging settings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Tab("Generation", systemImage: "wand.and.stars") {
                Text("Generation settings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 300)
        #endif
    }
}

// MARK: - Draw Things Tab

struct DrawThingsSettingsTab: View {
    @Environment(GenerationManager.self) private var manager: GenerationManager?

    @State private var address = ""
    @State private var useTLS = true

    var body: some View {
        Form {
            Section("Server connection") {
                TextField("Address (host:port)", text: $address)
                    .onAppear { address = manager?.serverAddress ?? "localhost:7859" }
                    .onSubmit { saveAddress() }

                Toggle("Use TLS", isOn: $useTLS)
                    .onAppear { useTLS = manager?.useTLS ?? true }
                    .onChange(of: useTLS) { _, newValue in
                        manager?.useTLS = newValue
                    }

                HStack {
                    if manager?.isConnected == true {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not connected", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(manager?.isConnected == true ? "Reconnect" : "Connect") {
                        saveAddress()
                        manager?.connect()
                    }
                    if manager?.isConnected == true {
                        Button("Disconnect") { manager?.disconnect() }
                    }
                }
            }

            if let queue = manager?.queue {
                Section("Queue status") {
                    LabeledContent("Pending") { Text("\(queue.pendingRequests.count)") }
                    LabeledContent("Processing") { Text(queue.isProcessing ? "Yes" : "No") }
                    if queue.isPaused {
                        LabeledContent("Paused") {
                            Text(queue.lastError ?? "Manually paused")
                                .foregroundStyle(.orange)
                        }
                        Button("Resume") { queue.resume() }
                    }
                }
            }

            if let manager, !manager.stagedResults.isEmpty {
                Section("Staged results") {
                    Text("\(manager.stagedResults.count) results waiting for their projects to be opened.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func saveAddress() {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        manager?.serverAddress = trimmed
    }
}

// MARK: - Ollama Tab

struct OllamaSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var profiles: [OllamaProfile] = []
    @State private var showAddProfile = false
    @State private var editingProfile: OllamaProfile?

    // New profile form
    @State private var newName = ""
    @State private var newEndpoint = "http://localhost:11434"
    @State private var newModel = "llava"
    @State private var newInstruction = "Describe this image in detail for a LoRA training caption."

    var body: some View {
        Form {
            Section("Profiles") {
                if profiles.isEmpty {
                    Text("No captioning profiles configured.")
                        .foregroundStyle(.secondary)
                }
                ForEach(profiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .fontWeight(.medium)
                            Text("\(profile.model) @ \(profile.endpoint)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editingProfile = profile; populateForm(profile) }
                            .buttonStyle(.bordered)
                    }
                    .contextMenu {
                        Button(role: .destructive) { deleteProfile(profile) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button { showAddProfile = true; resetForm() } label: {
                    Label("Add profile", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadProfiles() }
        .sheet(isPresented: $showAddProfile) { profileSheet(isEdit: false) }
        .sheet(item: $editingProfile) { _ in profileSheet(isEdit: true) }
    }

    private func profileSheet(isEdit: Bool) -> some View {
        NavigationStack {
            Form {
                TextField("Name", text: $newName)
                TextField("Endpoint", text: $newEndpoint)
                TextField("Model", text: $newModel)
                Section("Instruction") {
                    TextEditor(text: $newInstruction)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(isEdit ? "Edit profile" : "New profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddProfile = false; editingProfile = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveProfile(); showAddProfile = false; editingProfile = nil }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func loadProfiles() {
        let repo = SwiftDataOllamaProfileRepository(modelContext: modelContext)
        profiles = (try? repo.allProfiles()) ?? []
    }

    private func saveProfile() {
        let profile = OllamaProfile(
            name: newName.trimmingCharacters(in: .whitespaces),
            endpoint: newEndpoint.trimmingCharacters(in: .whitespaces),
            model: newModel.trimmingCharacters(in: .whitespaces),
            instruction: newInstruction
        )
        let repo = SwiftDataOllamaProfileRepository(modelContext: modelContext)
        try? repo.save(profile)
        loadProfiles()
    }

    private func deleteProfile(_ profile: OllamaProfile) {
        let repo = SwiftDataOllamaProfileRepository(modelContext: modelContext)
        try? repo.delete(name: profile.name)
        loadProfiles()
    }

    private func populateForm(_ profile: OllamaProfile) {
        newName = profile.name
        newEndpoint = profile.endpoint
        newModel = profile.model
        newInstruction = profile.instruction
    }

    private func resetForm() {
        newName = ""
        newEndpoint = "http://localhost:11434"
        newModel = "llava"
        newInstruction = "Describe this image in detail for a LoRA training caption."
    }
}
