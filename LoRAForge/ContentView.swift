import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DrawThingsQueue

struct ContentView: View {
    @ObservedObject var document: LoRAForgeDocument
    @ObservedObject var connectionManager = ConnectionManager.shared
    @StateObject private var generationService = GenerationService()
    @StateObject private var captionService = CaptionService()
    @State private var selection: SidebarSelection?
    @State private var showingTrash = false
    @State private var showingExport = false
    @State private var showingBaseConfigEditor = false
    @State private var showingQueue = false
    @State private var editingLabelID: UUID?

    enum SidebarSelection: Hashable {
        case sourceImage(UUID)
        case prompt(UUID)
    }

    private var selectedPromptID: UUID? {
        if case .prompt(let id) = selection { return id }
        return nil
    }

    private var hasValidConfiguration: Bool {
        let trimmed = document.project.baseConfigurationJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "{}" && trimmed != "{ }"
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            } detail: {
                detail
            }

            Divider()
            statusBar
        }
        .frame(minWidth: 700, minHeight: 400)
        .toolbar(id: "main") {
            ToolbarItem(id: "config", placement: .automatic) {
                Button {
                    showingBaseConfigEditor = true
                } label: {
                    Label("Configuration", systemImage: "gearshape")
                }
                .help("Edit DrawThings configuration")
            }
            
            ToolbarItem(id: "serverPicker", placement: .automatic) {
                serverPicker
            }
            ToolbarItem(id: "captionPicker", placement: .automatic) {
                captionServerPicker
            }
            
            ToolbarItem(id: "runSelected", placement: .automatic) {
                Button {
                    guard hasValidConfiguration else {
                        showingBaseConfigEditor = true
                        return
                    }
                    if let promptID = selectedPromptID {
                        document.ensureSaved {
                            generationService.runSingle(document: document, promptID: promptID)
                        }
                    }
                } label: {
                    Label("Run Selected", systemImage: "play")
                }
                .disabled(document.project.generationConnectionID == nil || selectedPromptID == nil)
                .help("Generate images for the selected prompt")
            }
            ToolbarItem(id: "run", placement: .automatic) {
                Button {
                    guard hasValidConfiguration else {
                        showingBaseConfigEditor = true
                        return
                    }
                    document.ensureSaved {
                        generationService.run(document: document, runAll: false)
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(document.project.generationConnectionID == nil)
                .help("Generate images for prompts without a final image")
            }
            ToolbarItem(id: "runAll", placement: .automatic) {
                Button {
                    guard hasValidConfiguration else {
                        showingBaseConfigEditor = true
                        return
                    }
                    document.ensureSaved {
                        generationService.run(document: document, runAll: true)
                    }
                } label: {
                    Label("Run All", systemImage: "arrow.clockwise")
                }
                .disabled(document.project.generationConnectionID == nil)
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
                    showingExport = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export images and captions")
            }
        }
        .sheet(isPresented: $showingExport) {
            ExportView(document: document, isPresented: $showingExport)
        }
        .sheet(isPresented: $showingBaseConfigEditor) {
            ConfigurationEditorSheet(
                isPresented: $showingBaseConfigEditor,
                configurationJSON: Binding(
                    get: { document.project.baseConfigurationJSON },
                    set: {
                        document.project.baseConfigurationJSON = $0
                        document.updateChangeCount(.changeDone)
                    }
                ),
                title: "DrawThings Configuration"
            )
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            // Generation preview + progress
            if generationService.isRunning {
                if let preview = generationService.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if let queue = generationService.queue, queue.isPaused {
                    Image(systemName: queue.lastError != nil ? "wifi.exclamationmark" : "pause.fill")
                        .foregroundStyle(queue.lastError != nil ? .orange : .yellow)
                        .font(.caption)
                }

                ProgressView(value: generationService.progressFraction)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
            }

            // Generation status
            if !generationService.statusMessage.isEmpty {
                Text(generationService.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let stage = generationService.generationStage {
                    Text("— \(stage)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
                    .truncationMode(.tail)
            }

            // Idle state
            if !generationService.isRunning && generationService.statusMessage.isEmpty
                && !captionService.isBulkCaptioning && captionService.bulkStatusMessage.isEmpty {
                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            // Queue button — always visible when queue exists
            if generationService.queue != nil {
                Button {
                    showingQueue.toggle()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show generation queue")
                .popover(isPresented: $showingQueue) {
                    if let queue = generationService.queue {
                        QueuePopoverView(generationService: generationService, queue: queue)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(height: 52)
        .background(.bar)
    }

    // MARK: - Server Picker

    private var serverPicker: some View {
        Menu {
            Button {
                document.project.generationConnectionID = nil
            } label: {
                if document.project.generationConnectionID == nil {
                    Label("No Server", systemImage: "checkmark")
                } else {
                    Text("No Server")
                }
            }
            ForEach(connectionManager.connections(ofType: .drawThings)) { conn in
                Button {
                    document.project.generationConnectionID = conn.id
                } label: {
                    if document.project.generationConnectionID == conn.id {
                        Label(conn.name, systemImage: "checkmark")
                    } else {
                        Text(conn.name)
                    }
                }
            }
            Divider()
            Button("Address Book…") {
                NSApp.sendAction(#selector(AppDelegate.showAddressBook), to: nil, from: nil)
            }
        } label: {
            Label(serverPickerLabel, systemImage: "server.rack")
                .labelStyle(.titleAndIcon)
        }
        .frame(width: 170)
    }

    private var serverPickerLabel: String {
        if let id = document.project.generationConnectionID,
           let conn = connectionManager.connection(for: id) {
            return conn.name
        }
        return "No Server"
    }

    private var captionServerPicker: some View {
        Menu {
            Button {
                document.project.captionConnectionID = nil
            } label: {
                if document.project.captionConnectionID == nil {
                    Label("No Caption Server", systemImage: "checkmark")
                } else {
                    Text("No Caption Server")
                }
            }
            ForEach(connectionManager.connections(ofType: .ollama)) { conn in
                Button {
                    document.project.captionConnectionID = conn.id
                } label: {
                    if document.project.captionConnectionID == conn.id {
                        Label(conn.name, systemImage: "checkmark")
                    } else {
                        Text(conn.name)
                    }
                }
            }
            Divider()
            Button("Address Book…") {
                NSApp.sendAction(#selector(AppDelegate.showAddressBook), to: nil, from: nil)
            }
        } label: {
            Label(captionPickerLabel, systemImage: "text.bubble")
                .labelStyle(.titleAndIcon)
        }
        .frame(width: 170)
    }

    private var captionPickerLabel: String {
        if let id = document.project.captionConnectionID,
           let conn = connectionManager.connection(for: id) {
            return conn.name
        }
        return "No Caption Server"
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Source Images") {
                ForEach(document.project.sourceImages) { source in
                    sourceImageRow(source)
                        .tag(SidebarSelection.sourceImage(source.id))
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
                    .tag(SidebarSelection.prompt(prompt.id))
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
            Divider()
            Button("Append to All Prompts") {
                appendSourceToAllPrompts(source.id)
            }
            .disabled(document.project.prompts.isEmpty)
            Button("Replace on All Prompts") {
                replaceSourceOnAllPrompts(source.id)
            }
            .disabled(document.project.prompts.isEmpty)
            Divider()
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
        selection = .prompt(newPrompt.id)
        document.updateChangeCount(.changeDone)
    }

    private func deletePrompt(id: UUID) {
        document.trashPrompt(id: id)
        if selection == .prompt(id) {
            selection = nil
        }
    }

    private func appendSourceToAllPrompts(_ sourceID: UUID) {
        for i in document.project.prompts.indices {
            if !document.project.prompts[i].sourceImageIDs.contains(sourceID) {
                document.project.prompts[i].sourceImageIDs.append(sourceID)
            }
        }
        document.updateChangeCount(.changeDone)
    }

    private func replaceSourceOnAllPrompts(_ sourceID: UUID) {
        for i in document.project.prompts.indices {
            document.project.prompts[i].sourceImageIDs = [sourceID]
        }
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
            switch selection {
            case .prompt(let promptID) where document.project.prompts.contains(where: { $0.id == promptID }):
                PromptDetailView(
                    document: document,
                    promptID: promptID,
                    generationService: generationService,
                    captionService: captionService,
                    showingTrash: showingTrash
                )
            case .sourceImage(let sourceID):
                if let source = document.project.sourceImages.first(where: { $0.id == sourceID }) {
                    sourceImageDetail(source)
                } else {
                    Text("Select a prompt to get started")
                        .foregroundStyle(.secondary)
                }
            default:
                Text("Select a prompt to get started")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Source Image Detail

    private func sourceImageDetail(_ source: SourceImage) -> some View {
        VStack {
            if let url = document.sourceImageURL(for: source),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }

            Text(source.label ?? source.filename)
                .font(.headline)
                .padding(.bottom)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Content View") {
    ContentView(document: PreviewData.sampleDocument)
        .frame(width: 900, height: 600)
}

#Preview("Content View — Empty") {
    ContentView(document: LoRAForgeDocument())
        .frame(width: 900, height: 600)
}
#endif
