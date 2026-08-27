import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsPanel: View {
    @Environment(LibraryManager.self) private var library
    @State private var showingFolderPicker = false
    @State private var isMigrating = false
    @State private var migrationError: String?

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
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: library.libraryURL.path(percentEncoded: false))
                    }
                    Button("Change location\u{2026}") {
                        showingFolderPicker = true
                    }
                    .disabled(isMigrating)
                    if isMigrating {
                        ProgressView()
                            .controlSize(.small)
                        Text("Moving projects\u{2026}")
                            .foregroundStyle(.secondary)
                    }
                }
                if let migrationError {
                    Text(migrationError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("General")
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else {
                    migrationError = "Could not access the selected folder."
                    return
                }
                migrateToFolder(url)
            case .failure(let error):
                migrationError = error.localizedDescription
            }
        }
    }

    private func migrateToFolder(_ destination: URL) {
        migrationError = nil
        isMigrating = true
        Task.detached {
            do {
                try await MainActor.run {
                    try library.migrateLibrary(to: destination)
                }
                await MainActor.run {
                    isMigrating = false
                }
            } catch {
                await MainActor.run {
                    migrationError = error.localizedDescription
                    isMigrating = false
                }
            }
        }
    }
}

struct ConnectionsSettingsPanel: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Draw Things")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
                    .padding(.top, 12)
                DrawThingsConnectionPane()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text("Ollama")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
                    .padding(.top, 12)
                OllamaConnectionPane()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Connections")
    }
}

struct DrawThingsConnectionPane: View {
    @Environment(GenerationService.self) private var generation
    @Environment(ConnectionProfileRepository.self) private var profileRepo
    @State private var profiles: [SDConnectionProfile] = []
    @AppStorage("defaultConnectionProfileID") private var defaultProfileID: String = ""
    @AppStorage("autoConnectOnLaunch") private var autoConnectOnLaunch: Bool = false
    @State private var editingProfile: SDConnectionProfile?
    @State private var showingSaveSheet = false
    @State private var saveProfileName = ""
    @State private var showingSwitchAlert = false
    @State private var pendingSwitchProfile: SDConnectionProfile?

    private var defaultUUID: UUID? {
        UUID(uuidString: defaultProfileID)
    }

    var body: some View {
        @Bindable var generation = generation
        Form {
            Section("Profiles") {
                ForEach(profiles) { profile in
                    HStack(spacing: 10) {
                        Image(systemName: isActive(profile) ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(isActive(profile) ? Color.accentColor : Color.secondary)
                            .imageScale(.large)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(profile.name).font(.headline)
                                if profile.id == defaultUUID {
                                    Text("Default")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(profile.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(isActive(profile) ? "Reconnect" : "Connect") {
                            connectToProfile(profile)
                        }
                        .buttonStyle(.bordered)
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Connect") {
                            connectToProfile(profile)
                        }
                        Divider()
                        if profile.id == defaultUUID {
                            Button("Clear default") {
                                defaultProfileID = ""
                            }
                        } else {
                            Button("Set as default") {
                                defaultProfileID = profile.id.uuidString
                            }
                        }
                        Divider()
                        Button("Edit\u{2026}") {
                            editingProfile = profile
                        }
                        Button("Delete", role: .destructive) {
                            if profile.id == defaultUUID {
                                defaultProfileID = ""
                            }
                            try? profileRepo.deleteProfile(profile)
                            refresh()
                        }
                    }
                }
                if profiles.isEmpty {
                    Text("No profiles saved.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Active connection") {
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
                Button("Save current as profile\u{2026}") {
                    saveProfileName = ""
                    showingSaveSheet = true
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

            Section("Startup") {
                Toggle("Auto-connect on launch", isOn: $autoConnectOnLaunch)
                if autoConnectOnLaunch {
                    if let uuid = defaultUUID,
                       let profile = profiles.first(where: { $0.id == uuid }) {
                        Text("Will connect to: \(profile.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No default profile set. Auto-connect will not activate.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .sheet(item: $editingProfile) { profile in
            ConnectionProfileEditor(profile: profile, repo: profileRepo, onSave: refresh)
        }
        .alert("Save profile", isPresented: $showingSaveSheet) {
            TextField("Profile name", text: $saveProfileName)
            Button("Save") { saveCurrentAsProfile() }
            Button("Cancel", role: .cancel) { }
        }
        .alert(
            "Switch server?",
            isPresented: $showingSwitchAlert,
            presenting: pendingSwitchProfile
        ) { profile in
            Button("Switch", role: .destructive) {
                generation.clearPending()
                generation.applyProfile(profile)
                pendingSwitchProfile = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSwitchProfile = nil
            }
        } message: { profile in
            Text("You have \(generation.pendingCount) items queued. Connecting to \(profile.name) will discard them.")
        }
    }

    /// The profile whose settings match the active connection fields, if any.
    private func isActive(_ profile: SDConnectionProfile) -> Bool {
        profile.address == generation.serverAddress
            && profile.useTLS == generation.useTLS
            && profile.sharedSecret == generation.sharedSecret
    }

    private func refresh() {
        profiles = (try? profileRepo.allProfiles()) ?? []
    }

    private func connectToProfile(_ profile: SDConnectionProfile) {
        if generation.pendingCount > 0 {
            pendingSwitchProfile = profile
            showingSwitchAlert = true
        } else {
            generation.applyProfile(profile)
        }
    }

    private func saveCurrentAsProfile() {
        let name = saveProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        _ = try? profileRepo.addProfile(
            name: name,
            address: generation.serverAddress,
            useTLS: generation.useTLS,
            sharedSecret: generation.sharedSecret
        )
        refresh()
    }
}

struct ConnectionProfileEditor: View {
    let profile: SDConnectionProfile
    let repo: ConnectionProfileRepository
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String
    @State private var useTLS: Bool
    @State private var sharedSecret: String

    init(profile: SDConnectionProfile, repo: ConnectionProfileRepository, onSave: @escaping () -> Void) {
        self.profile = profile
        self.repo = repo
        self.onSave = onSave
        _name = State(initialValue: profile.name)
        _address = State(initialValue: profile.address)
        _useTLS = State(initialValue: profile.useTLS)
        _sharedSecret = State(initialValue: profile.sharedSecret)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Address", text: $address)
                Toggle("Use TLS", isOn: $useTLS)
                TextField("Shared secret", text: $sharedSecret)
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
                        profile.address = address
                        profile.useTLS = useTLS
                        profile.sharedSecret = sharedSecret
                        try? repo.updateProfile(profile)
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct OllamaConnectionPane: View {
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
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Edit\u{2026}") { editingProfile = profile }
                        Button("Delete", role: .destructive) {
                            try? repo.deleteProfile(profile)
                            refresh()
                        }
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
        .onAppear(perform: refresh)
        .sheet(item: $editingProfile) { profile in
            OllamaProfileEditor(profile: profile, repo: repo, onSave: refresh)
        }
    }

    private func refresh() {
        profiles = (try? repo.allProfiles()) ?? []
    }
}

struct OllamaProfileEditor: View {
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
