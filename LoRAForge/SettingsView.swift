import SwiftUI

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

#Preview {
    SettingsView()
}
