import SwiftUI

struct ContentView: View {
    @ObservedObject var document: LoRAForgeDocument
    @ObservedObject var connectionManager = ConnectionManager.shared
    @State private var selectedPromptID: UUID?
    @State private var showingTrash = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            detail
        }
        .frame(minWidth: 700, minHeight: 400)
        .toolbar(id: "main") {
            ToolbarItem(id: "serverPicker", placement: .automatic) {
                serverPicker
            }
            ToolbarItem(id: "run", placement: .automatic) {
                Button {
                    // Phase 10: Run Generation
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .help("Generate images for prompts without a final image")
            }
            ToolbarItem(id: "runAll", placement: .automatic) {
                Button {
                    // Phase 10: Run All
                } label: {
                    Label("Run All", systemImage: "arrow.clockwise")
                }
                .help("Regenerate all prompts")
            }
            ToolbarItem(id: "stop", placement: .automatic) {
                Button {
                    // Phase 10: Stop
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(true)
                .help("Stop generation")
            }
            ToolbarItem(id: "trash", placement: .automatic) {
                Toggle(isOn: $showingTrash) {
                    Label("Trash", systemImage: "trash")
                }
                .help("Toggle trash view")
            }
            ToolbarItem(id: "autoCaption", placement: .automatic) {
                Button {
                    // Phase 14: Auto-caption All
                } label: {
                    Label("Auto-caption", systemImage: "sparkles")
                }
                .help("Auto-caption all uncaptioned images")
            }
            ToolbarItem(id: "export", placement: .automatic) {
                Button {
                    // Phase 16: Export
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export images and captions")
            }
        }
    }

    // MARK: - Server Picker

    private var serverPicker: some View {
        Picker("Server", selection: $document.project.generationConnectionID) {
            Text("No Server").tag(UUID?.none)
            ForEach(connectionManager.connections(ofType: .drawThings)) { conn in
                Text(conn.name).tag(UUID?.some(conn.id))
            }
        }
        .frame(width: 150)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedPromptID) {
            Section("Source Images") {
                if document.project.sourceImages.isEmpty {
                    Text("No source images")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(document.project.sourceImages) { source in
                        HStack {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                            Text(source.label ?? source.filename)
                                .lineLimit(1)
                        }
                    }
                }

                Button {
                    // Phase 6: Import source images
                } label: {
                    Label("Import Images…", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            Section("Prompts") {
                if document.project.prompts.isEmpty {
                    Text("No prompts")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(document.project.prompts) { prompt in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(prompt.text.isEmpty ? "Empty prompt" : prompt.text)
                                    .lineLimit(1)
                                    .foregroundStyle(prompt.text.isEmpty ? .secondary : .primary)
                            }
                            Spacer()
                            if prompt.generatedImages.contains(where: { $0.rank == .final_ }) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                        .tag(prompt.id)
                    }
                }

                Button {
                    // Phase 7: Add prompt
                } label: {
                    Label("Add Prompt", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let promptID = selectedPromptID,
               let _ = document.project.prompts.first(where: { $0.id == promptID }) {
                // Phase 7: Prompt detail view
                Text("Prompt detail — coming in Phase 7")
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a prompt to get started")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
