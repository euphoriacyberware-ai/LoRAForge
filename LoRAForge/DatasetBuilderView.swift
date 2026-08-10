import SwiftUI
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

            if document.discardedImageCount > 0 {
                Button { showingEmptyTrash = true } label: {
                    Label("Empty trash (\(document.discardedImageCount))", systemImage: "trash")
                }
            }

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
        ScrollView {
            LazyVStack(spacing: 1) {
                headerBar
                ForEach(filteredEntries) { entry in
                    EntryRow(
                        entry: entry,
                        bundleURL: bundleURL,
                        visibleRanks: rankVisibility,
                        onSweep: { sweepEntry(id: entry.id) },
                        onImport: { importingForEntryID = entry.id },
                        onCaption: { captioningEntryID = entry.id },
                        onSetRank: { imageID, rank in
                            handleRankChange(imageID: imageID, entryID: entry.id, newRank: rank)
                        },
                        onDeleteEntry: { deleteEntry(id: entry.id) }
                    )
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
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

    private func addEntry() {
        let position = document.entries.count + 1
        let entry = EntryDocument(name: "Entry \(position)", position: position)
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
    let onSweep: () -> Void
    let onImport: () -> Void
    let onCaption: () -> Void
    let onSetRank: (UUID, ImageRank) -> Void
    let onDeleteEntry: () -> Void

    private var visibleImages: [ImageDocument] {
        entry.images.filter { visibleRanks.contains($0.rank) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            entryHeader
                .frame(width: 200)
                .padding(8)
            Divider()
            imageStrip
                .padding(.vertical, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var entryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(format: "%03d", entry.position))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(entry.name)
                    .font(.headline)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Label("\(entry.activeImageCount)", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.finalImage != nil {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onCaption) {
                    Label("Caption", systemImage: "text.bubble")
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Button(action: onImport) {
                    Label("Add", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Button(action: onSweep) {
                    Label("Sweep", systemImage: "wind")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Move all candidates to discarded")
            }
        }
        .contextMenu {
            Button("Add images...", action: onImport)
            Button("Sweep candidates", action: onSweep)
            Divider()
            Button("Delete entry", role: .destructive, action: onDeleteEntry)
        }
    }

    private var imageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(visibleImages) { image in
                    ImageThumbnail(
                        image: image,
                        bundleURL: bundleURL,
                        onSetRank: { rank in onSetRank(image.id, rank) }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Image Thumbnail

private struct ImageThumbnail: View {
    let image: ImageDocument
    let bundleURL: URL
    let onSetRank: (ImageRank) -> Void

    private var imageURL: URL {
        bundleURL.appending(path: "images/\(image.filename)")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            loadedImage
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if let icon = image.rank.badgeIcon {
                Image(systemName: icon)
                    .font(.caption)
                    .padding(4)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(image.rank == .final ? .yellow : .secondary)
                    .padding(4)
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
