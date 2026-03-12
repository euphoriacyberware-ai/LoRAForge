import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: LoRAForgeDocument
    @ObservedObject var connectionManager = ConnectionManager.shared
    @StateObject private var generationService = GenerationService()
    @StateObject private var captionService = CaptionService()
    @State private var selectedPromptID: UUID?
    @State private var showingTrash = false
    @State private var editingLabelID: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            detail
        }
        .frame(minWidth: 700, minHeight: 400)
        .safeAreaInset(edge: .bottom) {
            if generationService.isRunning || !generationService.statusMessage.isEmpty
                || captionService.isBulkCaptioning || !captionService.bulkStatusMessage.isEmpty {
                statusBar
            }
        }
        .toolbar(id: "main") {
            ToolbarItem(id: "serverPicker", placement: .automatic) {
                serverPicker
            }
            ToolbarItem(id: "captionPicker", placement: .automatic) {
                captionServerPicker
            }
            ToolbarItem(id: "run", placement: .automatic) {
                Button {
                    document.ensureSaved {
                        generationService.run(document: document, runAll: false)
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(generationService.isRunning || document.project.generationConnectionID == nil)
                .help("Generate images for prompts without a final image")
            }
            ToolbarItem(id: "runAll", placement: .automatic) {
                Button {
                    document.ensureSaved {
                        generationService.run(document: document, runAll: true)
                    }
                } label: {
                    Label("Run All", systemImage: "arrow.clockwise")
                }
                .disabled(generationService.isRunning || document.project.generationConnectionID == nil)
                .help("Regenerate all prompts")
            }
            ToolbarItem(id: "stop", placement: .automatic) {
                Button {
                    generationService.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!generationService.isRunning)
                .help("Stop generation")
            }
            ToolbarItem(id: "trash", placement: .automatic) {
                Toggle(isOn: $showingTrash) {
                    Label("Trash", systemImage: "trash")
                }
                .help("Toggle trash view")
            }
            ToolbarItem(id: "autoCaption", placement: .automatic) {
                if captionService.isBulkCaptioning {
                    Button {
                        captionService.stopBulkCaption()
                    } label: {
                        Label("Stop Captioning", systemImage: "stop.fill")
                    }
                    .help("Stop auto-captioning")
                } else {
                    Button {
                        document.ensureSaved {
                            captionService.captionAll(document: document)
                        }
                    } label: {
                        Label("Auto-caption", systemImage: "sparkles")
                    }
                    .disabled(document.project.captionConnectionID == nil)
                    .help("Auto-caption all uncaptioned images")
                }
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

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            // Generation progress
            if generationService.isRunning {
                ProgressView(value: generationService.progressFraction)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
            }

            if !generationService.statusMessage.isEmpty {
                Text(generationService.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let stage = generationService.generationStage {
                    Text("— \(stage)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            // Caption progress
            if captionService.isBulkCaptioning {
                if !generationService.statusMessage.isEmpty {
                    Text("│")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
                ProgressView(value: Double(captionService.bulkProgress), total: Double(max(captionService.bulkTotal, 1)))
                    .progressViewStyle(.linear)
                    .frame(width: 100)
            }

            if !captionService.bulkStatusMessage.isEmpty {
                Text(captionService.bulkStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Dismiss button for completed messages
            if !generationService.isRunning && !captionService.isBulkCaptioning
                && (!generationService.statusMessage.isEmpty || !captionService.bulkStatusMessage.isEmpty) {
                Button {
                    generationService.statusMessage = ""
                    captionService.bulkStatusMessage = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
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

    private var captionServerPicker: some View {
        Picker("Caption", selection: $document.project.captionConnectionID) {
            Text("No Caption Server").tag(UUID?.none)
            ForEach(connectionManager.connections(ofType: .ollama)) { conn in
                Text(conn.name).tag(UUID?.some(conn.id))
            }
        }
        .frame(width: 150)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedPromptID) {
            Section("Source Images") {
                ForEach(document.project.sourceImages) { source in
                    sourceImageRow(source)
                }

                Button {
                    importSourceImages()
                } label: {
                    Label("Import Images…", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            Section("Prompts") {
                ForEach(document.project.prompts) { prompt in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(prompt.text.isEmpty ? "Empty prompt" : prompt.text)
                                .lineLimit(1)
                                .foregroundStyle(prompt.text.isEmpty ? .secondary : .primary)
                            Text("\(prompt.generatedImages.count) image(s)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if generationService.isRunning && generationService.currentPromptID == prompt.id {
                            ProgressView()
                                .controlSize(.small)
                        } else if prompt.generatedImages.contains(where: { $0.rank == .final_ }) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                    .tag(prompt.id)
                    .contextMenu {
                        Button("Delete Prompt") {
                            deletePrompt(id: prompt.id)
                        }
                    }
                }
                .onMove { from, to in
                    document.project.prompts.move(fromOffsets: from, toOffset: to)
                    reorderPrompts()
                }
                .onDelete { offsets in
                    for index in offsets.sorted().reversed() {
                        let id = document.project.prompts[index].id
                        deletePrompt(id: id)
                    }
                }

                Button {
                    addPrompt()
                } label: {
                    Label("Add Prompt", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Source Image Row

    private func sourceImageRow(_ source: SourceImage) -> some View {
        HStack(spacing: 8) {
            // Thumbnail
            if let url = document.sourceImageURL(for: source),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }

            // Label (inline editable)
            if editingLabelID == source.id {
                let labelBinding = Binding<String>(
                    get: {
                        document.project.sourceImages.first(where: { $0.id == source.id })?.label ?? ""
                    },
                    set: { newValue in
                        if let idx = document.project.sourceImages.firstIndex(where: { $0.id == source.id }) {
                            document.project.sourceImages[idx].label = newValue.isEmpty ? nil : newValue
                        }
                    }
                )
                TextField("Label", text: labelBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        editingLabelID = nil
                        document.updateChangeCount(.changeDone)
                    }
            } else {
                Text(source.label ?? source.filename)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        editingLabelID = source.id
                    }
            }
        }
        .contextMenu {
            Button("Rename…") {
                editingLabelID = source.id
            }
            Button("Remove") {
                document.removeSourceImage(id: source.id)
            }
            .disabled(document.isSourceImageReferenced(source.id))
        }
    }

    // MARK: - Import

    private func importSourceImages() {
        document.ensureSaved {
            showImageOpenPanel()
        }
    }

    private func showImageOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .heic]
        panel.message = "Select images to import as source images"

        guard panel.runModal() == .OK else { return }
        document.importSourceImages(from: panel.urls)
    }

    // MARK: - Prompt Management

    private func addPrompt() {
        let newPrompt = Prompt(
            id: UUID(),
            order: document.project.prompts.count,
            text: "",
            sourceImageIDs: [],
            generateCount: 4,
            configurationOverrideJSON: nil,
            generatedImages: []
        )
        document.project.prompts.append(newPrompt)
        selectedPromptID = newPrompt.id
        document.updateChangeCount(.changeDone)
    }

    private func deletePrompt(id: UUID) {
        document.project.prompts.removeAll { $0.id == id }
        if selectedPromptID == id {
            selectedPromptID = nil
        }
        reorderPrompts()
        document.updateChangeCount(.changeDone)
    }

    private func reorderPrompts() {
        for i in document.project.prompts.indices {
            document.project.prompts[i].order = i
        }
        document.updateChangeCount(.changeDone)
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let promptID = selectedPromptID,
               document.project.prompts.contains(where: { $0.id == promptID }) {
                PromptDetailView(
                    document: document,
                    promptID: promptID,
                    generationService: generationService,
                    captionService: captionService,
                    showingTrash: showingTrash
                )
            } else {
                Text("Select a prompt to get started")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
