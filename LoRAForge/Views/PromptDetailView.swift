import SwiftUI
import AppKit

struct PromptDetailView: View {
    @ObservedObject var document: LoRAForgeDocument
    let promptID: UUID
    @ObservedObject var generationService: GenerationService
    let showingTrash: Bool
    @State private var showingSlotPicker = false
    @State private var editingSlotIndex: Int?
    @State private var lightboxImage: GeneratedImage?

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
                    configOverrideSection(prompt: prompt, index: index)
                    baseConfigSection()
                    generatedImagesSection(prompt: prompt, promptIndex: index)
                }
                .padding()
            }
            .sheet(item: $lightboxImage) { image in
                LightboxView(document: document, promptID: promptID, image: image)
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
            Text("Generate Count")
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
                JSONEditorView(
                    jsonString: Binding(
                        get: { document.project.prompts[index].configurationOverrideJSON ?? "{}" },
                        set: {
                            document.project.prompts[index].configurationOverrideJSON = $0
                            document.updateChangeCount(.changeDone)
                        }
                    ),
                    label: "Override JSON"
                )
            }
        }
    }

    // MARK: - Base Configuration

    @State private var showBaseConfig = false

    private func baseConfigSection() -> some View {
        DisclosureGroup("Base Configuration", isExpanded: $showBaseConfig) {
            JSONEditorView(
                jsonString: Binding(
                    get: { document.project.baseConfigurationJSON },
                    set: {
                        document.project.baseConfigurationJSON = $0
                        document.updateChangeCount(.changeDone)
                    }
                ),
                label: "Draw Things Configuration"
            )
        }
        .font(.headline)
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
        let imageIndex = document.project.prompts[promptIndex].generatedImages.firstIndex(where: { $0.id == image.id })

        return VStack(spacing: 4) {
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

            // Caption field
            if let idx = imageIndex {
                TextField(
                    "Caption…",
                    text: Binding(
                        get: {
                            document.project.prompts[promptIndex].generatedImages[idx].caption ?? ""
                        },
                        set: { newValue in
                            document.project.prompts[promptIndex].generatedImages[idx].caption = newValue.isEmpty ? nil : newValue
                            document.updateChangeCount(.changeDone)
                        }
                    ),
                    axis: .vertical
                )
                .font(.caption)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            }
        }
        .contextMenu {
            if let idx = imageIndex {
                imageContextMenu(promptIndex: promptIndex, imageIndex: idx, image: image)
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
    private func imageContextMenu(promptIndex: Int, imageIndex: Int, image: GeneratedImage) -> some View {
        if !showingTrash {
            // Normal view actions
            if image.rank != .final_ {
                Button("Promote Rank") {
                    document.promoteImage(promptIndex: promptIndex, imageIndex: imageIndex)
                }
            }
            if image.rank != .candidate {
                Button("Demote Rank") {
                    document.demoteImage(promptIndex: promptIndex, imageIndex: imageIndex)
                }
            }

            Button("Discard") {
                document.discardImage(promptIndex: promptIndex, imageIndex: imageIndex)
            }

            Divider()

            Button("View Full Size") {
                lightboxImage = image
            }

            Button("Reveal in Finder") {
                if let url = document.generatedImageURL(promptID: promptID, image: image) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        } else {
            // Trash view actions
            Button("Restore") {
                document.restoreImage(promptIndex: promptIndex, imageIndex: imageIndex)
            }

            Button("Delete Permanently") {
                document.deleteImagePermanently(promptIndex: promptIndex, imageIndex: imageIndex)
            }

            Divider()

            Button("View Full Size") {
                lightboxImage = image
            }
        }
    }
}

// MARK: - Lightbox View

struct LightboxView: View {
    let document: LoRAForgeDocument
    let promptID: UUID
    let image: GeneratedImage

    var body: some View {
        VStack(spacing: 0) {
            if let url = document.generatedImageURL(promptID: promptID, image: image),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 800, maxHeight: 800)
            } else {
                Text("Image not found")
                    .foregroundStyle(.secondary)
                    .frame(width: 400, height: 300)
            }

            if let caption = image.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding()
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
