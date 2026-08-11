import SwiftUI
import UniformTypeIdentifiers
import TaggingCore

struct DatasetBuilderView: View {
    @Binding var document: ProjectDocument
    let bundleURL: URL
    let onChanged: () -> Void

    @State private var entryFilter = ""
    @State private var rankVisibility: Set<ImageRank> = [.final, .shortlist, .candidate]
    @State private var showingEmptyTrash = false
    @State private var discardFinalAlert: DiscardFinalAlert?
    @State private var importingForEntryID: UUID?
    @State private var captioningEntryID: UUID?
    @State private var showingExport = false
    @State private var importError: String?
    @State private var editingGenerationEntryID: UUID?
    @State private var showingAudit = false
    @State private var selectedImageIDs: Set<UUID> = []
    @Environment(GenerationService.self) private var generation
    @Environment(TagRepository.self) private var repo

    private var filteredEntries: [EntryDocument] {
        if entryFilter.isEmpty { return document.entries }
        let query = entryFilter.lowercased()
        return document.entries.filter {
            $0.name.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            entryList
        }
        .navigationTitle("Dataset Builder")
        .alert("Empty trash?", isPresented: $showingEmptyTrash) {
            Button("Empty trash", role: .destructive) { emptyTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let counts = trashCounts
            Text("\(counts.images) image\(counts.images == 1 ? "" : "s") across \(counts.entries) entr\(counts.entries == 1 ? "y" : "ies") will be permanently deleted.")
        }
        .alert(item: $discardFinalAlert) { alert in
            Alert(
                title: Text("Discard final image?"),
                message: Text("This entry will have no final image and will not be exported."),
                primaryButton: .destructive(Text("Discard")) {
                    setRank(imageID: alert.imageID, entryID: alert.entryID, to: .discarded)
                },
                secondaryButton: .cancel()
            )
        }
        .fileImporter(
            isPresented: .init(
                get: { importingForEntryID != nil },
                set: { _ in } // cleared in result handler to avoid race
            ),
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if let entryID = importingForEntryID, case .success(let urls) = result {
                importImages(urls, to: entryID)
            }
            importingForEntryID = nil
        }
        .alert("Import error", isPresented: .init(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(isPresented: $showingExport) {
            ExportDialogView(document: $document, bundleURL: bundleURL, onChanged: onChanged)
        }
        .sheet(isPresented: $showingAudit) {
            AuditView(document: document, bundleURL: bundleURL)
        }
        .sheet(item: $editingGenerationEntryID) { entryID in
            if let idx = document.entries.firstIndex(where: { $0.id == entryID }) {
                GenerationEditorView(
                    entry: $document.entries[idx],
                    referenceImages: document.referenceImages,
                    bundleURL: bundleURL,
                    onChanged: onChanged
                )
            }
        }
        .sheet(item: $captioningEntryID) { entryID in
            if let idx = document.entries.firstIndex(where: { $0.id == entryID }) {
                CaptionEditorView(
                    entry: $document.entries[idx],
                    bundleURL: bundleURL,
                    projectCategoryOrder: document.categoryOrder,
                    projectCategoryEnabled: document.categoryEnabled,
                    onChanged: onChanged
                )
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            TextField("Filter entries", text: $entryFilter)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            Spacer()

            rankToggles

            Spacer()

            Button { showingAudit = true } label: {
                Label("Audit", systemImage: "chart.bar")
            }

            if document.discardedImageCount > 0 {
                Button { showingEmptyTrash = true } label: {
                    Label("Empty trash (\(document.discardedImageCount))", systemImage: "trash")
                }
            }

            Button { generateUnfilled() } label: {
                Label("Generate unfilled", systemImage: "sparkles")
            }
            .disabled(!generation.isConnected || entriesWithoutFinal.isEmpty)
            .help(entriesWithoutFinal.isEmpty
                  ? "All entries have a final image"
                  : "Generate for \(entriesWithoutFinal.count) entr\(entriesWithoutFinal.count == 1 ? "y" : "ies") without a final")

            Button { showingExport = true } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Button { addEntry() } label: {
                Label("New entry", systemImage: "plus")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var rankToggles: some View {
        HStack(spacing: 4) {
            ForEach(ImageRank.allCases, id: \.self) { rank in
                Toggle(isOn: Binding(
                    get: { rankVisibility.contains(rank) },
                    set: { if $0 { rankVisibility.insert(rank) } else { rankVisibility.remove(rank) } }
                )) {
                    if let icon = rank.badgeIcon {
                        Image(systemName: icon)
                    } else {
                        Image(systemName: "circle")
                    }
                }
                .toggleStyle(.button)
                .help(rank.label)
            }
        }
    }

    // MARK: - Entry List

    private var entryList: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 1) {
                    headerBar
                    ForEach(filteredEntries) { entry in
                        EntryRow(
                            entry: entry,
                            bundleURL: bundleURL,
                            visibleRanks: rankVisibility,
                            captionPreview: captionPreviewFor(entry),
                            selectedImageIDs: $selectedImageIDs,
                            onImport: { importingForEntryID = entry.id },
                            onCaption: { captioningEntryID = entry.id },
                            onEditGeneration: { editingGenerationEntryID = entry.id },
                            onGenerate: { generateForEntry(entry) },
                            onSweep: { sweepEntry(id: entry.id) },
                            onInsertBefore: { insertEntry(before: entry.id) },
                            onInsertAfter: { insertEntry(after: entry.id) },
                            onSetRank: { imageID, rank in
                                setRankForSelection(imageID: imageID, entryID: entry.id, rank: rank)
                            },
                            onDeleteEntry: { deleteEntry(id: entry.id) }
                        )
                    }
                }
            }
            .background(.background)

            // Bottom toolbar for selected images
            if !selectedImageIDs.isEmpty {
                selectionToolbar
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 16) {
            Text("\(selectedImageIDs.count) selected")
                .font(.subheadline.weight(.medium))

            Spacer()

            ForEach(ImageRank.allCases, id: \.self) { rank in
                Button {
                    applyRankToSelection(rank)
                } label: {
                    if let icon = rank.badgeIcon {
                        Label(rank.label, systemImage: icon)
                    } else {
                        Text(rank.label)
                    }
                }
                .help(rank.label)
            }

            Spacer()

            Button("Deselect") {
                selectedImageIDs.removeAll()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var headerBar: some View {
        HStack {
            let showing = filteredEntries.count
            let total = document.entries.count
            if showing < total {
                Text("Showing \(showing) of \(total) entries · \(document.totalImageCount) images")
            } else {
                Text("\(total) entr\(total == 1 ? "y" : "ies") · \(document.totalImageCount) images")
            }
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var entriesWithoutFinal: [EntryDocument] {
        document.entries.filter { $0.finalImage == nil && !$0.generationPrompt.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Actions

    private func generateUnfilled() {
        for entry in entriesWithoutFinal {
            generateForEntry(entry)
        }
    }

    private func generateForEntry(_ entry: EntryDocument) {
        let prompt = entry.generationPrompt
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else {
            importError = "Set a prompt in the generation settings before generating."
            return
        }
        let seed: Int64? = entry.useCustomSeed ? entry.generationSeed : nil

        // Load reference image data for moodboard hints
        let refData: [Data] = entry.referenceImageIDs.compactMap { refID in
            guard let ref = document.referenceImages.first(where: { $0.id == refID }) else { return nil }
            let url = bundleURL.appending(path: "references/\(ref.filename)")
            return try? Data(contentsOf: url)
        }

        generation.generate(
            prompt: prompt,
            negativePrompt: entry.generationNegativePrompt,
            seed: seed,
            configJSON: entry.generationConfigJSON,
            projectConfigJSON: document.defaultGenerationConfigJSON,
            projectID: document.id,
            entryID: entry.id,
            referenceImageData: refData
        )
    }

    private func addEntry() {
        let position = document.entries.count + 1
        let entry = EntryDocument(
            name: "Entry \(position)",
            position: position,
            defaultConfigJSON: document.defaultGenerationConfigJSON
        )
        document.entries.append(entry)
        onChanged()
    }

    private func deleteEntry(id: UUID) {
        // Remove image files
        if let entry = document.entries.first(where: { $0.id == id }) {
            for image in entry.images {
                let imageURL = bundleURL.appending(path: "images/\(image.filename)")
                try? FileManager.default.removeItem(at: imageURL)
            }
        }
        document.entries.removeAll { $0.id == id }
        reindexPositions()
        onChanged()
    }

    private func sweepEntry(id: UUID) {
        guard let idx = document.entries.firstIndex(where: { $0.id == id }) else { return }
        for i in document.entries[idx].images.indices {
            if document.entries[idx].images[i].rank == .candidate {
                document.entries[idx].images[i].rank = .discarded
            }
        }
        onChanged()
    }

    private func handleRankChange(imageID: UUID, entryID: UUID, newRank: ImageRank) {
        guard let entryIdx = document.entries.firstIndex(where: { $0.id == entryID }) else { return }
        guard let imgIdx = document.entries[entryIdx].images.firstIndex(where: { $0.id == imageID }) else { return }

        let currentRank = document.entries[entryIdx].images[imgIdx].rank

        // Warn when discarding the final
        if newRank == .discarded && currentRank == .final {
            discardFinalAlert = DiscardFinalAlert(imageID: imageID, entryID: entryID)
            return
        }

        setRank(imageID: imageID, entryID: entryID, to: newRank)
    }

    private func setRank(imageID: UUID, entryID: UUID, to newRank: ImageRank) {
        guard let entryIdx = document.entries.firstIndex(where: { $0.id == entryID }) else { return }
        guard let imgIdx = document.entries[entryIdx].images.firstIndex(where: { $0.id == imageID }) else { return }

        // Promoting to final demotes the previous final to shortlist
        if newRank == .final {
            for i in document.entries[entryIdx].images.indices {
                if document.entries[entryIdx].images[i].rank == .final {
                    document.entries[entryIdx].images[i].rank = .shortlist
                }
            }
        }

        document.entries[entryIdx].images[imgIdx].rank = newRank
        onChanged()
    }

    private func emptyTrash() {
        for entryIdx in document.entries.indices {
            let discarded = document.entries[entryIdx].images.filter { $0.rank == .discarded }
            for image in discarded {
                let imageURL = bundleURL.appending(path: "images/\(image.filename)")
                try? FileManager.default.removeItem(at: imageURL)
            }
            document.entries[entryIdx].images.removeAll { $0.rank == .discarded }
        }
        onChanged()
    }

    private var trashCounts: (images: Int, entries: Int) {
        var images = 0
        var entries = 0
        for entry in document.entries {
            let count = entry.images.filter { $0.rank == .discarded }.count
            if count > 0 {
                images += count
                entries += 1
            }
        }
        return (images, entries)
    }

    private func importImages(_ urls: [URL], to entryID: UUID) {
        guard let entryIdx = document.entries.firstIndex(where: { $0.id == entryID }) else { return }
        let imagesDir = bundleURL.appending(path: "images")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            let filename = "\(UUID().uuidString).\(ext)"
            let dest = imagesDir.appending(path: filename)

            do {
                try FileManager.default.copyItem(at: url, to: dest)
                let imageDoc = ImageDocument(filename: filename)
                document.entries[entryIdx].images.append(imageDoc)
            } catch {
                importError = "Failed to import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        onChanged()
    }

    private func setRankForSelection(imageID: UUID, entryID: UUID, rank: ImageRank) {
        // If the image is in the selection, apply to all selected
        if selectedImageIDs.contains(imageID) {
            applyRankToSelection(rank)
        } else {
            handleRankChange(imageID: imageID, entryID: entryID, newRank: rank)
        }
    }

    private func applyRankToSelection(_ rank: ImageRank) {
        for entryIdx in document.entries.indices {
            for imgIdx in document.entries[entryIdx].images.indices {
                let img = document.entries[entryIdx].images[imgIdx]
                guard selectedImageIDs.contains(img.id) else { continue }

                if rank == .final {
                    // Demote existing final in this entry
                    for i in document.entries[entryIdx].images.indices {
                        if document.entries[entryIdx].images[i].rank == .final {
                            document.entries[entryIdx].images[i].rank = .shortlist
                        }
                    }
                }
                document.entries[entryIdx].images[imgIdx].rank = rank
            }
        }
        selectedImageIDs.removeAll()
        onChanged()
    }

    private func insertEntry(before id: UUID) {
        guard let idx = document.entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = EntryDocument(name: "Entry \(document.entries.count + 1)", position: 0)
        document.entries.insert(entry, at: idx)
        reindexPositions()
        onChanged()
    }

    private func insertEntry(after id: UUID) {
        guard let idx = document.entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = EntryDocument(name: "Entry \(document.entries.count + 1)", position: 0)
        document.entries.insert(entry, at: idx + 1)
        reindexPositions()
        onChanged()
    }

    private func moveEntries(from source: IndexSet, to destination: Int) {
        document.entries.move(fromOffsets: source, toOffset: destination)
        reindexPositions()
        onChanged()
    }

    private func reindexPositions() {
        for i in document.entries.indices {
            document.entries[i].position = i + 1
        }
    }

    private func captionPreviewFor(_ entry: EntryDocument) -> String {
        if let locked = entry.lockedCaptionText, !locked.isEmpty {
            return locked
        }
        switch entry.captionMode {
        case .manual, .ollama:
            return entry.manualCaptionText.isEmpty ? "No caption" : entry.manualCaptionText
        case .tagged:
            if entry.assignments.isEmpty { return "No caption" }
            let categories = (try? repo.allCategories()) ?? []
            let allTags = (try? repo.allTags()) ?? []
            let tagDict = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
            let domainAssignments = entry.assignments.map {
                TagAssignment(tagID: $0.tagID, selectionOrder: $0.selectionOrder)
            }
            let rendered = CaptionRenderer.render(
                assignments: domainAssignments, tags: tagDict, categories: categories
            )
            return rendered.isEmpty ? "No caption" : rendered
        }
    }
}

// MARK: - Entry Row

private struct EntryRow: View {
    let entry: EntryDocument
    let bundleURL: URL
    let visibleRanks: Set<ImageRank>
    let captionPreview: String
    @Binding var selectedImageIDs: Set<UUID>
    let onImport: () -> Void
    let onCaption: () -> Void
    let onEditGeneration: () -> Void
    let onGenerate: () -> Void
    let onSweep: () -> Void
    let onInsertBefore: () -> Void
    let onInsertAfter: () -> Void
    let onSetRank: (UUID, ImageRank) -> Void
    let onDeleteEntry: () -> Void

    private var visibleImages: [ImageDocument] {
        entry.images.filter { visibleRanks.contains($0.rank) }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            entryHeader
                .frame(width: 240)
                .padding(8)
            Divider()
            imageStrip
                .padding(.vertical, 4)
        }
        .background(.background)
    }

    private var entryHeader: some View {
        HStack(alignment: .top, spacing: 6) {
            // Final image thumbnail
            finalThumbnail
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Center: name, caption, count
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(String(format: "%03d", entry.position))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(entry.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }

                Text(captionPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Label("\(entry.activeImageCount)", systemImage: "photo")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            // Right: vertical icon buttons
            VStack(spacing: 4) {
                Button(action: onEditGeneration) {
                    Label("Generation settings", systemImage: "slider.horizontal.3")
                }
                .help("Generation settings")

                Button(action: onCaption) {
                    Label("Caption", systemImage: "text.bubble")
                }
                .help("Edit caption")

                Button(action: onImport) {
                    Label("Add images", systemImage: "photo.badge.plus")
                }
                .help("Import images")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .contextMenu {
            Button("Generate", systemImage: "sparkles", action: onGenerate)
            Button("Sweep candidates", systemImage: "wind", action: onSweep)
            Divider()
            Button("Insert entry before", systemImage: "arrow.up", action: onInsertBefore)
            Button("Insert entry after", systemImage: "arrow.down", action: onInsertAfter)
            Divider()
            Button("Add images...", systemImage: "photo.badge.plus", action: onImport)
            Divider()
            Button("Delete entry", systemImage: "trash", role: .destructive, action: onDeleteEntry)
        }
    }

    @ViewBuilder
    private var finalThumbnail: some View {
        if let finalImg = entry.finalImage {
            let imageURL = bundleURL.appending(path: "images/\(finalImg.filename)")
            #if os(macOS)
            if let nsImage = NSImage(contentsOf: imageURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                thumbnailPlaceholder
            }
            #else
            if let data = try? Data(contentsOf: imageURL),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                thumbnailPlaceholder
            }
            #endif
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
    }

    private var imageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(visibleImages) { image in
                    ImageThumbnail(
                        image: image,
                        bundleURL: bundleURL,
                        isSelected: selectedImageIDs.contains(image.id),
                        onTap: { toggleSelection(image.id) },
                        onSetRank: { rank in onSetRank(image.id, rank) }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func toggleSelection(_ imageID: UUID) {
        if selectedImageIDs.contains(imageID) {
            selectedImageIDs.remove(imageID)
        } else {
            selectedImageIDs.insert(imageID)
        }
    }
}

// MARK: - Image Thumbnail

private struct ImageThumbnail: View {
    let image: ImageDocument
    let bundleURL: URL
    let isSelected: Bool
    let onTap: () -> Void
    let onSetRank: (ImageRank) -> Void

    private var imageURL: URL {
        bundleURL.appending(path: "images/\(image.filename)")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            loadedImage
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                )

            if let icon = image.rank.badgeIcon {
                Image(systemName: icon)
                    .font(.caption)
                    .padding(4)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(image.rank == .final ? .yellow : .secondary)
                    .padding(4)
            }
        }
        .onTapGesture { onTap() }
        .contextMenu {
            ForEach(ImageRank.allCases, id: \.self) { rank in
                if rank != image.rank {
                    Button {
                        onSetRank(rank)
                    } label: {
                        if let icon = rank.badgeIcon {
                            Label(rank.label, systemImage: icon)
                        } else {
                            Text(rank.label)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var loadedImage: some View {
        #if os(macOS)
        if let nsImage = NSImage(contentsOf: imageURL) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            placeholder
        }
        #else
        if let data = try? Data(contentsOf: imageURL),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            placeholder
        }
        #endif
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - Alert Type

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

private struct DiscardFinalAlert: Identifiable {
    let id = UUID()
    let imageID: UUID
    let entryID: UUID
}
