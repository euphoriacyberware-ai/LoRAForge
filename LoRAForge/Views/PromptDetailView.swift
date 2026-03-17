import SwiftUI
import AppKit

struct PromptDetailView: View {
    @ObservedObject var document: LoRAForgeDocument
    let promptID: UUID
    @ObservedObject var generationService: GenerationService
    @ObservedObject var captionService: CaptionService
    let showingTrash: Bool
    @State private var showingSlotPicker = false
    @State private var editingSlotIndex: Int?
    @State private var lightboxImageID: UUID?
    @State private var showingBaseConfigEditor = false
    @State private var showingOverrideConfigEditor = false

    private var promptIndex: Int? {
        document.project.prompts.firstIndex(where: { $0.id == promptID })
    }

    var body: some View {
        if let index = promptIndex {
            let prompt = document.project.prompts[index]
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    promptTextEditor(index: index)
                    sourceSlots(prompt: prompt, index: index)
                    generateCountSection(index: index)
                    generatedImagesSection(prompt: prompt, promptIndex: index)
                    configOverrideSection(prompt: prompt, index: index)
                    baseConfigSection()
                    
                }
                .padding()
            }
            .onChange(of: lightboxImageID) { _, newValue in
                guard let newValue, let idx = promptIndex else { return }
                let images = filteredImages(prompt: document.project.prompts[idx])
                guard let startIndex = images.firstIndex(where: { $0.id == newValue }) else { return }
                LightboxController.show(
                    document: document,
                    promptID: promptID,
                    showingTrash: showingTrash,
                    startingImageID: newValue
                )
                lightboxImageID = nil
            }
        } else {
            Text("Prompt not found")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Prompt Text

    private func promptTextEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prompt Text")
                .font(.headline)
            TextEditor(text: $document.project.prompts[index].text)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 150)
                .border(Color.secondary.opacity(0.3))
                .onChange(of: document.project.prompts[index].text) {
                    document.updateChangeCount(.changeDone)
                }
        }
    }

    // MARK: - Source Image Slots

    private func sourceSlots(prompt: Prompt, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source Images")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(prompt.sourceImageIDs.enumerated()), id: \.offset) { slotIndex, imageID in
                        sourceSlotCell(imageID: imageID, slotIndex: slotIndex, promptIndex: index)
                    }

                    // Add slot button
                    Button {
                        editingSlotIndex = prompt.sourceImageIDs.count
                        showingSlotPicker = true
                    } label: {
                        VStack {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 64, height: 64)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showingSlotPicker) {
            SourceImagePickerSheet(
                document: document,
                isPresented: $showingSlotPicker
            ) { selectedID in
                guard let idx = promptIndex else { return }
                if let slotIndex = editingSlotIndex,
                   slotIndex < document.project.prompts[idx].sourceImageIDs.count {
                    document.project.prompts[idx].sourceImageIDs[slotIndex] = selectedID
                } else {
                    document.project.prompts[idx].sourceImageIDs.append(selectedID)
                }
                document.updateChangeCount(.changeDone)
            }
        }
    }

    private func sourceSlotCell(imageID: UUID, slotIndex: Int, promptIndex: Int) -> some View {
        let source = document.project.sourceImages.first(where: { $0.id == imageID })
        return VStack(spacing: 2) {
            if let source,
               let url = document.sourceImageURL(for: source),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                VStack {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64, height: 64)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text(source?.label ?? "Missing")
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 64)
        }
        .contextMenu {
            Button("Change…") {
                editingSlotIndex = slotIndex
                showingSlotPicker = true
            }
            Button("Remove Slot") {
                document.project.prompts[promptIndex].sourceImageIDs.remove(at: slotIndex)
                document.updateChangeCount(.changeDone)
            }
        }
    }

    // MARK: - Generate Count

    private func generateCountSection(index: Int) -> some View {
        HStack {
            Text("Batch Size")
                .font(.headline)
            Spacer()
            Stepper(
                value: $document.project.prompts[index].generateCount,
                in: 1...100
            ) {
                Text("\(document.project.prompts[index].generateCount)")
                    .monospacedDigit()
            }
            .onChange(of: document.project.prompts[index].generateCount) {
                document.updateChangeCount(.changeDone)
            }
        }
    }

    // MARK: - Config Override

    private func configOverrideSection(prompt: Prompt, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let hasOverride = prompt.configurationOverrideJSON != nil
            Toggle("Configuration Override", isOn: Binding(
                get: { hasOverride },
                set: { enabled in
                    if enabled {
                        document.project.prompts[index].configurationOverrideJSON = document.project.baseConfigurationJSON
                    } else {
                        document.project.prompts[index].configurationOverrideJSON = nil
                    }
                    document.updateChangeCount(.changeDone)
                }
            ))
            .font(.headline)

            if hasOverride {
                Button {
                    showingOverrideConfigEditor = true
                } label: {
                    HStack {
                        Label("Edit Override", systemImage: "slider.horizontal.3")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingOverrideConfigEditor) {
                    ConfigurationEditorSheet(
                        isPresented: $showingOverrideConfigEditor,
                        configurationJSON: Binding(
                            get: { document.project.prompts[index].configurationOverrideJSON ?? "{}" },
                            set: {
                                document.project.prompts[index].configurationOverrideJSON = $0
                                document.updateChangeCount(.changeDone)
                            }
                        ),
                        title: "Configuration Override"
                    )
                }
            }
        }
    }

    // MARK: - Base Configuration

    private func baseConfigSection() -> some View {
        Button {
            showingBaseConfigEditor = true
        } label: {
            HStack {
                Label("DrawThings Configuration", systemImage: "gearshape")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
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

    // MARK: - Generated Images

    private var isGeneratingThisPrompt: Bool {
        generationService.isRunning && generationService.currentPromptID == promptID
    }

    private func filteredImages(prompt: Prompt) -> [GeneratedImage] {
        if showingTrash {
            return prompt.generatedImages.filter { $0.rank == .discarded }
        } else {
            return prompt.generatedImages.filter { $0.rank != .discarded }
        }
    }

    private func generatedImagesSection(prompt: Prompt, promptIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(showingTrash ? "Trash" : "Generated Images")
                    .font(.headline)
                Spacer()
                if isGeneratingThisPrompt {
                    ProgressView()
                        .controlSize(.small)
                    Text(generationService.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let images = filteredImages(prompt: prompt)

            if images.isEmpty {
                let message = showingTrash
                    ? "No discarded images."
                    : "No generated images yet. Use Run to generate."
                Text(message)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                generatedImageGrid(images: images, promptIndex: promptIndex)
            }
        }
    }

    private func generatedImageGrid(images: [GeneratedImage], promptIndex: Int) -> some View {
        let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(images) { image in
                generatedImageCell(image: image, promptIndex: promptIndex)
            }
        }
    }

    private func generatedImageCell(image: GeneratedImage, promptIndex: Int) -> some View {
        VStack(spacing: 4) {
            // Thumbnail with rank badge
            ZStack(alignment: .topTrailing) {
                if let url = document.generatedImageURL(promptID: promptID, image: image),
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(minWidth: 120, maxWidth: .infinity, minHeight: 120, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 120, maxWidth: .infinity, minHeight: 120, maxHeight: 160)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Rank badge
                rankBadge(image.rank)
                    .padding(4)
            }
            .onTapGesture(count: 2) {
                lightboxImageID = image.id
            }

            // Caption field + auto-caption button
            HStack(alignment: .top, spacing: 4) {
                TextField(
                    "Caption…",
                    text: Binding(
                        get: {
                            guard let pIdx = document.project.prompts.firstIndex(where: { $0.id == promptID }),
                                  let iIdx = document.project.prompts[pIdx].generatedImages.firstIndex(where: { $0.id == image.id }) else {
                                return ""
                            }
                            return document.project.prompts[pIdx].generatedImages[iIdx].caption ?? ""
                        },
                        set: { newValue in
                            guard let pIdx = document.project.prompts.firstIndex(where: { $0.id == promptID }),
                                  let iIdx = document.project.prompts[pIdx].generatedImages.firstIndex(where: { $0.id == image.id }) else {
                                return
                            }
                            document.project.prompts[pIdx].generatedImages[iIdx].caption = newValue.isEmpty ? nil : newValue
                            document.updateChangeCount(.changeDone)
                        }
                    ),
                    axis: .vertical
                )
                .font(.caption)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

                autoCaptionButton(image: image, promptIndex: promptIndex)
            }
        }
        .contextMenu {
            imageContextMenu(image: image)
        }
    }

    // MARK: - Auto-Caption Button

    private func autoCaptionButton(image: GeneratedImage, promptIndex: Int) -> some View {
        let isCaptioning = captionService.captioningImageIDs.contains(image.id)
        let captionConnectionID = document.project.captionConnectionID
        let hasConnection = captionConnectionID != nil
            && ConnectionManager.shared.connection(for: captionConnectionID) != nil

        return Group {
            if isCaptioning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
            } else {
                Button {
                    guard let connID = document.project.captionConnectionID,
                          let conn = ConnectionManager.shared.connection(for: connID),
                          let url = document.generatedImageURL(promptID: promptID, image: image) else { return }
                    captionService.caption(
                        imageID: image.id,
                        imageURL: url,
                        connection: conn,
                        document: document,
                        promptID: promptID
                    )
                } label: {
                    Image(systemName: "sparkles")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(!hasConnection)
                .help(hasConnection ? "Auto-caption with Ollama" : "Set a caption server in the toolbar")
            }
        }
    }

    // MARK: - Rank Badge

    private func rankBadge(_ rank: ImageRank) -> some View {
        Text(rankLabel(rank))
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(rankColor(rank).opacity(0.85))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func rankLabel(_ rank: ImageRank) -> String {
        switch rank {
        case .candidate: "C"
        case .shortlisted: "S"
        case .final_: "F"
        case .discarded: "D"
        }
    }

    private func rankColor(_ rank: ImageRank) -> Color {
        switch rank {
        case .candidate: .gray
        case .shortlisted: .blue
        case .final_: .green
        case .discarded: .red
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func imageContextMenu(image: GeneratedImage) -> some View {
        if !showingTrash {
            // Normal view actions
            if image.rank != .final_ {
                Button("Promote Rank") {
                    document.promoteImage(promptID: promptID, imageID: image.id)
                }
            }
            if image.rank != .candidate {
                Button("Demote Rank") {
                    document.demoteImage(promptID: promptID, imageID: image.id)
                }
            }

            Button("Discard") {
                document.discardImage(promptID: promptID, imageID: image.id)
            }

            Divider()

            Button("View Full Size") {
                lightboxImageID = image.id
            }

            Button("Reveal in Finder") {
                if let url = document.generatedImageURL(promptID: promptID, image: image) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        } else {
            // Trash view actions
            Button("Restore") {
                document.restoreImage(promptID: promptID, imageID: image.id)
            }

            Button("Delete Permanently") {
                document.deleteImagePermanently(promptID: promptID, imageID: image.id)
            }

            Divider()

            Button("View Full Size") {
                lightboxImageID = image.id
            }
        }
    }
}

// MARK: - Lightbox Controller

enum LightboxController {
    private static var currentWindow: NSPanel?

    static func show(
        document: LoRAForgeDocument,
        promptID: UUID,
        showingTrash: Bool,
        startingImageID: UUID
    ) {
        currentWindow?.close()

        let view = LightboxContentView(
            document: document,
            promptID: promptID,
            showingTrash: showingTrash,
            currentImageID: startingImageID
        )
        let hostingController = NSHostingController(rootView: view)

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let winW = screen.width * 0.8
        let winH = screen.height * 0.85

        hostingController.sizingOptions = []

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: winW, height: winH))
        window.title = "Lightbox"
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        currentWindow = window
    }
}

// MARK: - Lightbox Content View

struct LightboxContentView: View {
    @ObservedObject var document: LoRAForgeDocument
    let promptID: UUID
    let showingTrash: Bool
    @State var currentImageID: UUID

    private var promptIndex: Int? {
        document.project.prompts.firstIndex(where: { $0.id == promptID })
    }

    private var visibleImages: [GeneratedImage] {
        guard let idx = promptIndex else { return [] }
        let all = document.project.prompts[idx].generatedImages
        return showingTrash
            ? all.filter { $0.rank == .discarded }
            : all.filter { $0.rank != .discarded }
    }

    private var currentIndex: Int? {
        visibleImages.firstIndex(where: { $0.id == currentImageID })
    }

    private var currentImage: GeneratedImage? {
        visibleImages.first(where: { $0.id == currentImageID })
    }

    private var currentImageModelIndex: Int? {
        guard let idx = promptIndex else { return nil }
        return document.project.prompts[idx].generatedImages.firstIndex(where: { $0.id == currentImageID })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Image area
            imageDisplay
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Controls bar
            controlsBar
                .padding(.horizontal)
                .padding(.vertical, 10)
        }
        .background(Color.black)
    }

    // MARK: - Image Display

    private var imageDisplay: some View {
        ZStack {
            if let image = currentImage,
               let url = document.generatedImageURL(promptID: promptID, image: image),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            } else {
                Text("Image not found")
                    .foregroundStyle(.secondary)
            }

            // Navigation arrows
            HStack {
                navButton(systemImage: "chevron.left") {
                    navigatePrevious()
                }
                .disabled(currentIndex == nil || currentIndex == 0)

                Spacer()

                navButton(systemImage: "chevron.right") {
                    navigateNext()
                }
                .disabled(currentIndex == nil || currentIndex == visibleImages.count - 1)
            }
            .padding(.horizontal, 8)
        }
    }

    private func navButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 16) {
            // Navigation position
            if let idx = currentIndex {
                Text("\(idx + 1) / \(visibleImages.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            // Rank controls
            if let image = currentImage {
                rankControls(image: image)
            }

            Spacer()

            // Caption editor
            captionEditor
                .frame(maxWidth: 400)
        }
    }

    @ViewBuilder
    private func rankControls(image: GeneratedImage) -> some View {
        if showingTrash {
            Button("Restore") {
                document.restoreImage(promptID: promptID, imageID: image.id)
            }
            .buttonStyle(.bordered)

            Button("Delete Permanently") {
                let next = navigateAfterRemoval()
                document.deleteImagePermanently(promptID: promptID, imageID: image.id)
                if let next { currentImageID = next } else { closeWindow() }
            }
            .buttonStyle(.bordered)
            .tint(.red)
        } else {
            HStack(spacing: 4) {
                rankBadge(image.rank)
            }

            Button {
                document.promoteImage(promptID: promptID, imageID: image.id)
            } label: {
                Label("Promote", systemImage: "arrow.up.circle")
            }
            .disabled(image.rank == .final_)
            .buttonStyle(.bordered)

            Button {
                document.demoteImage(promptID: promptID, imageID: image.id)
            } label: {
                Label("Demote", systemImage: "arrow.down.circle")
            }
            .disabled(image.rank == .candidate)
            .buttonStyle(.bordered)

            Button {
                let next = navigateAfterRemoval()
                document.discardImage(promptID: promptID, imageID: image.id)
                if let next { currentImageID = next } else { closeWindow() }
            } label: {
                Label("Discard", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    private func rankBadge(_ rank: ImageRank) -> some View {
        Text(rankLabel(rank))
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(rankColor(rank).opacity(0.85))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func rankLabel(_ rank: ImageRank) -> String {
        switch rank {
        case .candidate: "Candidate"
        case .shortlisted: "Shortlisted"
        case .final_: "Final"
        case .discarded: "Discarded"
        }
    }

    private func rankColor(_ rank: ImageRank) -> Color {
        switch rank {
        case .candidate: .gray
        case .shortlisted: .blue
        case .final_: .green
        case .discarded: .red
        }
    }

    // MARK: - Caption Editor

    private var captionEditor: some View {
        TextField(
            "Caption…",
            text: Binding(
                get: {
                    guard let pIdx = document.project.prompts.firstIndex(where: { $0.id == promptID }),
                          let iIdx = document.project.prompts[pIdx].generatedImages.firstIndex(where: { $0.id == currentImageID }) else {
                        return ""
                    }
                    return document.project.prompts[pIdx].generatedImages[iIdx].caption ?? ""
                },
                set: { newValue in
                    guard let pIdx = document.project.prompts.firstIndex(where: { $0.id == promptID }),
                          let iIdx = document.project.prompts[pIdx].generatedImages.firstIndex(where: { $0.id == currentImageID }) else {
                        return
                    }
                    document.project.prompts[pIdx].generatedImages[iIdx].caption = newValue.isEmpty ? nil : newValue
                    document.updateChangeCount(.changeDone)
                }
            ),
            axis: .vertical
        )
        .textFieldStyle(.roundedBorder)
        .lineLimit(2...4)
    }

    // MARK: - Navigation

    private func navigatePrevious() {
        guard let idx = currentIndex, idx > 0 else { return }
        currentImageID = visibleImages[idx - 1].id
    }

    private func navigateNext() {
        guard let idx = currentIndex, idx < visibleImages.count - 1 else { return }
        currentImageID = visibleImages[idx + 1].id
    }

    private func navigateAfterRemoval() -> UUID? {
        guard let idx = currentIndex else { return nil }
        if visibleImages.count <= 1 { return nil }
        if idx < visibleImages.count - 1 {
            return visibleImages[idx + 1].id
        }
        return visibleImages[idx - 1].id
    }

    private func closeWindow() {
        NSApp.keyWindow?.close()
    }
}

// MARK: - Source Image Picker Sheet

struct SourceImagePickerSheet: View {
    @ObservedObject var document: LoRAForgeDocument
    @Binding var isPresented: Bool
    var onSelect: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Select Source Image")
                .font(.headline)
                .padding()

            Divider()

            if document.project.sourceImages.isEmpty {
                Text("No source images imported yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                        ForEach(document.project.sourceImages) { source in
                            Button {
                                onSelect(source.id)
                                isPresented = false
                            } label: {
                                VStack(spacing: 4) {
                                    if let url = document.sourceImageURL(for: source),
                                       let nsImage = NSImage(contentsOf: url) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        Image(systemName: "photo")
                                            .frame(width: 72, height: 72)
                                            .background(Color.secondary.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    Text(source.label ?? source.filename)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .frame(width: 72)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 350, height: 300)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Prompt Detail") {
    let doc = PreviewData.sampleDocument
    PromptDetailView(
        document: doc,
        promptID: PreviewData.promptID1,
        generationService: GenerationService(),
        captionService: CaptionService(),
        showingTrash: false
    )
    .frame(width: 600, height: 500)
}

#Preview("Prompt Detail — Trash") {
    let doc = PreviewData.sampleDocument
    PromptDetailView(
        document: doc,
        promptID: PreviewData.promptID1,
        generationService: GenerationService(),
        captionService: CaptionService(),
        showingTrash: true
    )
    .frame(width: 600, height: 500)
}

#Preview("Prompt Detail — Empty Prompt") {
    let doc = PreviewData.sampleDocument
    PromptDetailView(
        document: doc,
        promptID: PreviewData.promptID3,
        generationService: GenerationService(),
        captionService: CaptionService(),
        showingTrash: false
    )
    .frame(width: 600, height: 500)
}

#Preview("Lightbox") {
    let doc = PreviewData.sampleDocument
    let imageID = doc.project.prompts[0].generatedImages[0].id
    LightboxContentView(
        document: doc,
        promptID: PreviewData.promptID1,
        showingTrash: false,
        currentImageID: imageID
    )
    .frame(width: 800, height: 600)
}

#Preview("Source Image Picker") {
    let doc = PreviewData.sampleDocument
    SourceImagePickerSheet(
        document: doc,
        isPresented: .constant(true),
        onSelect: { _ in }
    )
}
#endif

