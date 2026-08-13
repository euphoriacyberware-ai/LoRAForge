import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

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
    @State private var showingSaveTemplate = false
    @State private var showingLoadTemplate = false
    @State private var selectedImageIDs: Set<UUID> = []
    @State private var lightboxTarget: LightboxTarget?
    #if os(macOS)
    @State private var lightboxManager = LightboxWindowManager()
    #endif
    @AppStorage("thumbnailSize") private var thumbnailSize: Double = 100
    @Environment(GenerationService.self) private var generation
    @Environment(TemplateManager.self) private var templateManager

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
        .sheet(isPresented: $showingSaveTemplate) {
            SaveTemplateSheet(
                entries: document.entries,
                projectName: document.name,
                templateManager: templateManager
            )
        }
        .sheet(isPresented: $showingLoadTemplate) {
            LoadTemplateSheet(
                templateManager: templateManager,
                onLoad: { template, replace in
                    loadTemplate(template, replace: replace)
                }
            )
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

            HStack(spacing: 4) {
                Image(systemName: "photo").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $thumbnailSize, in: 60...200).frame(width: 100)
                Image(systemName: "photo").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button { showingAudit = true } label: {
                Label("Audit", systemImage: "chart.bar")
            }
            
            
            
            Button { showingExport = true } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            
            Spacer()
            
            if document.discardedImageCount > 0 {
                Button { showingEmptyTrash = true } label: {
                    Label("Empty trash (\(document.discardedImageCount))", systemImage: "trash")
                }
            }
            
            Menu {
                Button("Save entries as template...") {
                    showingSaveTemplate = true
                }
                .disabled(document.entries.isEmpty)

                Button("Load template into project...") {
                    showingLoadTemplate = true
                }
                .disabled(templateManager.templates.isEmpty)
            } label: {
                Label("Templates", systemImage: "doc.on.doc")
            }

            Button {
                addEntry()
            } label: {
                Label("New Entry", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .help("New Entry")
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

    private var selectedImageInfo: (entry: EntryDocument, image: ImageDocument)? {
        guard selectedImageIDs.count == 1, let imageID = selectedImageIDs.first else { return nil }
        for entry in document.entries {
            if let image = entry.images.first(where: { $0.id == imageID }) {
                return (entry, image)
            }
        }
        return nil
    }

    private var entryList: some View {
        HStack(spacing: 0) {
            entryListContent

            if let info = selectedImageInfo {
                Divider()
                ImageInspectorView(
                    image: info.image,
                    entry: info.entry,
                    referenceImages: document.referenceImages,
                    bundleURL: bundleURL,
                    onCloneToEntry: info.image.provenance != nil ? {
                        cloneImageToEntry(imageID: info.image.id, entryID: info.entry.id)
                    } : nil,
                    onAddToReferences: info.image.provenance != nil ? {
                        addImageToReferences(imageID: info.image.id, entryID: info.entry.id)
                    } : nil
                )
                .frame(width: 280)
            }
        }
    }

    private var entryListContent: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 1) {
                    headerBar
                    ForEach(filteredEntries) { entry in
                        EntryRow(
                            entry: entry,
                            bundleURL: bundleURL,
                            visibleRanks: rankVisibility,
                            thumbnailSize: CGFloat(thumbnailSize),
                            captionPreview: entry.captionPreviewText.isEmpty ? "No caption" : entry.captionPreviewText,
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
                            onDeleteEntry: { deleteEntry(id: entry.id) },
                            onDoubleTapImage: { imageID in
                                lightboxTarget = LightboxTarget(entryID: entry.id, imageID: imageID)
                            },
                            onCloneToEntry: { imageID in
                                cloneImageToEntry(imageID: imageID, entryID: entry.id)
                            },
                            onAddToReferences: { imageID in
                                addImageToReferences(imageID: imageID, entryID: entry.id)
                            }
                        )
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedIDString = items.first,
                                  let draggedID = UUID(uuidString: draggedIDString),
                                  draggedID != entry.id,
                                  let fromIdx = document.entries.firstIndex(where: { $0.id == draggedID }),
                                  let toIdx = document.entries.firstIndex(where: { $0.id == entry.id })
                            else { return false }
                            document.entries.move(fromOffsets: IndexSet(integer: fromIdx), toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
                            reindexPositions()
                            onChanged()
                            return true
                        }
                    }
                }
            }
            .background(.background)

            // Bottom toolbar for selected images
            if !selectedImageIDs.isEmpty {
                selectionToolbar
            }
        }
        #if os(iOS)
        .fullScreenCover(item: $lightboxTarget) { target in
            LightboxView(
                document: $document,
                bundleURL: bundleURL,
                initialEntryID: target.entryID,
                initialImageID: target.imageID,
                visibleRanks: rankVisibility,
                onChanged: onChanged
            )
        }
        #else
        .onChange(of: lightboxTarget) { _, target in
            if let target {
                lightboxManager.show(
                    LightboxView(
                        document: $document,
                        bundleURL: bundleURL,
                        initialEntryID: target.entryID,
                        initialImageID: target.imageID,
                        visibleRanks: rankVisibility,
                        onChanged: onChanged,
                        onDismiss: { lightboxTarget = nil }
                    ),
                    onClose: { lightboxTarget = nil }
                )
            } else {
                lightboxManager.close()
            }
        }
        .onDisappear { lightboxManager.close() }
        #endif
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

            if let info = selectedImageInfo, info.image.provenance != nil {
                Divider().frame(height: 20)
                Button {
                    cloneImageToEntry(imageID: info.image.id, entryID: info.entry.id)
                } label: {
                    Label("Clone", systemImage: "doc.on.doc")
                }
                .help("Clone to new entry")
                Button {
                    addImageToReferences(imageID: info.image.id, entryID: info.entry.id)
                } label: {
                    Label("Add to references", systemImage: "photo.on.rectangle")
                }
                .help("Add to references")
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

    // MARK: - Actions

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
            referenceImageData: refData,
            referenceImageIDs: entry.referenceImageIDs
        )
    }

    private func loadTemplate(_ template: Template, replace: Bool) {
        if replace {
            for entry in document.entries {
                for image in entry.images {
                    let imageURL = bundleURL.appending(path: "images/\(image.filename)")
                    try? FileManager.default.removeItem(at: imageURL)
                }
            }
            document.entries.removeAll()
        }

        let startPosition = (document.entries.map(\.position).max() ?? 0) + 1
        for (index, tp) in template.prompts.sorted(by: { $0.order < $1.order }).enumerated() {
            let promptPrefix = String(tp.text.prefix(30)).trimmingCharacters(in: .whitespaces)
            let name = promptPrefix.isEmpty ? "Entry \(startPosition + index)" : promptPrefix
            var entry = EntryDocument(
                name: name,
                position: startPosition + index,
                defaultConfigJSON: document.defaultGenerationConfigJSON
            )
            entry.generationPrompt = tp.text
            document.entries.append(entry)
        }
        onChanged()
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

    private func cloneImageToEntry(imageID: UUID, entryID: UUID) {
        guard let entryIdx = document.entries.firstIndex(where: { $0.id == entryID }),
              let imgIdx = document.entries[entryIdx].images.firstIndex(where: { $0.id == imageID }),
              let provenance = document.entries[entryIdx].images[imgIdx].provenance
        else { return }

        // Name from prompt prefix or fallback
        let promptPrefix = String(provenance.prompt.prefix(30)).trimmingCharacters(in: .whitespaces)
        let name = promptPrefix.isEmpty ? "Entry \(document.entries.count + 1)" : promptPrefix

        var entry = EntryDocument(
            name: name,
            position: document.entries.count + 1,
            defaultConfigJSON: provenance.configJSON ?? document.defaultGenerationConfigJSON
        )
        entry.generationPrompt = provenance.prompt
        entry.generationNegativePrompt = provenance.negativePrompt
        entry.generationConfigJSON = provenance.configJSON ?? document.defaultGenerationConfigJSON
        entry.referenceImageIDs = provenance.referenceImageIDs ?? []
        entry.useCustomSeed = true
        entry.generationSeed = provenance.seed

        // Copy image file
        let sourceFilename = document.entries[entryIdx].images[imgIdx].filename
        let sourceURL = bundleURL.appending(path: "images/\(sourceFilename)")
        let ext = (sourceFilename as NSString).pathExtension.isEmpty ? "png" : (sourceFilename as NSString).pathExtension
        let newFilename = "\(UUID().uuidString).\(ext)"
        let destURL = bundleURL.appending(path: "images/\(newFilename)")

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            let imageDoc = ImageDocument(filename: newFilename, provenance: provenance)
            entry.images.append(imageDoc)
        } catch {
            importError = "Failed to clone image: \(error.localizedDescription)"
            return
        }

        document.entries.append(entry)
        onChanged()
    }

    private func addImageToReferences(imageID: UUID, entryID: UUID) {
        guard let entryIdx = document.entries.firstIndex(where: { $0.id == entryID }),
              let imgIdx = document.entries[entryIdx].images.firstIndex(where: { $0.id == imageID })
        else { return }

        let filename = document.entries[entryIdx].images[imgIdx].filename
        let sourceURL = bundleURL.appending(path: "images/\(filename)")
        guard let data = try? Data(contentsOf: sourceURL) else { return }

        // Deduplicate on content hash
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        if document.referenceImages.contains(where: { $0.contentHash == hash }) {
            return // silently skip duplicate
        }

        let refsDir = bundleURL.appending(path: "references")
        try? FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)

        let ext = (filename as NSString).pathExtension.isEmpty ? "png" : (filename as NSString).pathExtension
        let newFilename = "\(UUID().uuidString).\(ext)"
        let destURL = refsDir.appending(path: newFilename)

        do {
            try data.write(to: destURL)
            let refDoc = ReferenceImageDocument(filename: newFilename, contentHash: hash)
            document.referenceImages.append(refDoc)
            onChanged()
        } catch {
            importError = "Failed to add to references: \(error.localizedDescription)"
        }
    }

    private func reindexPositions() {
        for i in document.entries.indices {
            document.entries[i].position = i + 1
        }
    }

}

// MARK: - Entry Row

private struct EntryRow: View {
    let entry: EntryDocument
    let bundleURL: URL
    let visibleRanks: Set<ImageRank>
    let thumbnailSize: CGFloat
    let captionPreview: String
    @Binding var selectedImageIDs: Set<UUID>
    @Environment(GenerationService.self) private var generation
    let onImport: () -> Void
    let onCaption: () -> Void
    let onEditGeneration: () -> Void
    let onGenerate: () -> Void
    let onSweep: () -> Void
    let onInsertBefore: () -> Void
    let onInsertAfter: () -> Void
    let onSetRank: (UUID, ImageRank) -> Void
    let onDeleteEntry: () -> Void
    let onDoubleTapImage: (UUID) -> Void
    let onCloneToEntry: (UUID) -> Void
    let onAddToReferences: (UUID) -> Void

    private var visibleImages: [ImageDocument] {
        entry.images.filter { visibleRanks.contains($0.rank) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            entryHeader
                .frame(width: 320)
                .padding(8)
                .draggable(entry.id.uuidString) {
                    Text(entry.name)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            Divider()
            imageStrip
                .padding(.vertical, 4)
        }
        .background(.background)
    }

    private var entryHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            // Final image thumbnail
            finalThumbnail
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Center: name, caption, count
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(String(format: "%03d", entry.position))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(entry.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }

                Text(captionPreview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)

                Label("\(entry.activeImageCount)", systemImage: "photo")
                    .font(.caption)
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
            .font(.headline)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Generate", systemImage: "sparkles", action: onGenerate)
                .disabled(!generation.isConnected)
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
            ThumbnailView(url: imageURL, size: 44)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .overlay {
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
        }
    }

    private var imageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(visibleImages) { image in
                    ImageThumbnail(
                        image: image,
                        bundleURL: bundleURL,
                        size: thumbnailSize,
                        isSelected: selectedImageIDs.contains(image.id),
                        onTap: { multi in selectImage(image.id, multiSelect: multi) },
                        onDoubleTap: { onDoubleTapImage(image.id) },
                        onSetRank: { rank in onSetRank(image.id, rank) },
                        onCloneToEntry: { onCloneToEntry(image.id) },
                        onAddToReferences: { onAddToReferences(image.id) }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func selectImage(_ imageID: UUID, multiSelect: Bool) {
        if multiSelect {
            if selectedImageIDs.contains(imageID) {
                selectedImageIDs.remove(imageID)
            } else {
                selectedImageIDs.insert(imageID)
            }
        } else {
            if selectedImageIDs == [imageID] {
                selectedImageIDs.removeAll()
            } else {
                selectedImageIDs = [imageID]
            }
        }
    }
}

// MARK: - Image Thumbnail

private struct ImageThumbnail: View {
    let image: ImageDocument
    let bundleURL: URL
    let size: CGFloat
    let isSelected: Bool
    let onTap: (_ multiSelect: Bool) -> Void
    let onDoubleTap: () -> Void
    let onSetRank: (ImageRank) -> Void
    let onCloneToEntry: () -> Void
    let onAddToReferences: () -> Void

    @State private var lastTapTime = Date.distantPast

    private var imageURL: URL {
        bundleURL.appending(path: "images/\(image.filename)")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            loadedImage
                .frame(width: size, height: size)
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
        #if os(macOS)
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastTapTime) < 0.3 {
                onDoubleTap()
                lastTapTime = .distantPast
            } else {
                let multiSelect = NSEvent.modifierFlags.contains(.command)
                onTap(multiSelect)
                lastTapTime = now
            }
        }
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
            if image.provenance != nil {
                Divider()
                Button("Clone to new entry", systemImage: "doc.on.doc") { onCloneToEntry() }
                Button("Add to references", systemImage: "photo.on.rectangle") { onAddToReferences() }
            }
        }
        #else
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastTapTime) < 0.3 {
                onDoubleTap()
                lastTapTime = .distantPast
            } else {
                onTap(false)
                lastTapTime = now
            }
        }
        .onLongPressGesture {
            onTap(true)
        }
        #endif
    }

    private var loadedImage: some View {
        ThumbnailView(url: imageURL, size: size)
    }
}

// MARK: - Generate Unfilled Button

struct GenerateUnfilledButton: View {
    @Binding var count: Int
    var unfilledCount: Int
    var disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button {
                if count > 1 { count -= 1 }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(count <= 1 || disabled)
            .opacity(count > 1 && !disabled ? 1.0 : 0.4)

            Button(action: action) {
                HStack(spacing: 4) {
                    Label("Generate", systemImage: "sparkles")
                    Text("\(unfilledCount)")
                        .monospacedDigit()
                    if count > 1 {
                        Text("×\(count)")
                            .monospacedDigit()
                            .fontWeight(.bold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.25)))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.red))
                .foregroundColor(.white)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(disabled)

            Button {
                if count < 50 { count += 1 }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(count >= 50 || disabled)
            .opacity(count < 50 && !disabled ? 1.0 : 0.4)
        }
        .foregroundColor(.red)
        .opacity(disabled ? 0.6 : 1.0)
    }
}

// MARK: - Save Template Sheet

private struct SaveTemplateSheet: View {
    let entries: [EntryDocument]
    let projectName: String
    let templateManager: TemplateManager
    @Environment(\.dismiss) private var dismiss
    @State private var templateName = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Save as template")
                .font(.headline)

            TextField("Template name", text: $templateName)
                .textFieldStyle(.roundedBorder)

            Text("This will save \(entries.count) entr\(entries.count == 1 ? "y" : "ies") as a reusable template.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    saveTemplate()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(templateName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear { templateName = projectName }
    }

    private func saveTemplate() {
        let prompts = entries.enumerated().map { index, entry in
            TemplatePrompt(
                id: UUID(),
                order: index,
                text: entry.generationPrompt,
                sourceSlotIndex: nil,
                generateCount: 1
            )
        }
        let template = Template(
            id: UUID(),
            name: templateName.trimmingCharacters(in: .whitespaces),
            createdAt: Date(),
            prompts: prompts
        )
        templateManager.add(template)
    }
}

// MARK: - Load Template Sheet

private struct LoadTemplateSheet: View {
    let templateManager: TemplateManager
    let onLoad: (Template, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplateID: UUID?

    private var selectedTemplate: Template? {
        guard let id = selectedTemplateID else { return nil }
        return templateManager.templates.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Load template")
                .font(.headline)
                .padding()

            Divider()

            List(templateManager.templates, selection: $selectedTemplateID) { template in
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.headline)
                    HStack {
                        Text("\(template.prompts.count) prompt(s)")
                        Text("—")
                        Text(template.createdAt, style: .date)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .tag(template.id)
            }
            .frame(minHeight: 200)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Replace entries") {
                    if let template = selectedTemplate {
                        onLoad(template, true)
                        dismiss()
                    }
                }
                .disabled(selectedTemplateID == nil)

                Button("Append entries") {
                    if let template = selectedTemplate {
                        onLoad(template, false)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedTemplateID == nil)
            }
            .padding()
        }
        .frame(minWidth: 420, idealWidth: 500, minHeight: 350, idealHeight: 400)
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
