import SwiftUI
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
                Text("Ollama settings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Button("Disconnect") {
                            manager?.disconnect()
                        }
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
