import SwiftUI
import UniformTypeIdentifiers

struct DatasetBuilderView: View {
    @ObservedObject var document: LoRAForgeDocument
    @Environment(\.undoManager) private var undoManager

    // Filters
    @State private var filterText = ""
    @State private var filterNoFinal = false
    @State private var visibleRanks: Set<ImageRank> = [.final, .shortlist, .candidate]

    // Entry creation
    @State private var showNewEntry = false
    @State private var newEntryName = ""

    // Empty trash
    @State private var showEmptyTrashWarning = false

    // Image import
    @State private var importTargetEntryID: UUID?
    @State private var showImagePicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                Divider()
                entryList
            }
            .navigationTitle(document.metadata.name)
            .withSettingsAccess()
            .toolbar { toolbarContent }
            .sheet(isPresented: $showNewEntry) { newEntrySheet }
            .fileImporter(
                isPresented: $showImagePicker,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result, let entryID = importTargetEntryID {
                    importImages(urls: urls, to: entryID)
                }
            }
            .alert(
                "Empty trash?",
                isPresented: $showEmptyTrashWarning
            ) {
                Button("Delete", role: .destructive) { emptyTrash() }
                Button("Cancel", role: .cancel) {}
            } message: {
                let stats = trashStats
                Text("Permanently delete \(stats.images) images across \(stats.entries) entries. This cannot be undone.")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showNewEntry = true } label: {
                Label("New entry", systemImage: "plus")
            }
        }
        ToolbarItem {
            Button {
                showEmptyTrashWarning = true
            } label: {
                Label("Empty trash", systemImage: "trash")
            }
            .disabled(trashStats.images == 0)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(document.entries.count) entries · \(totalImageCount) images")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter entries", text: $filterText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 250)

                Toggle("No final", isOn: $filterNoFinal)
                    .toggleStyle(.button)
                    .controlSize(.small)

                Spacer()

                rankToggles
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var rankToggles: some View {
        HStack(spacing: 4) {
            ForEach(ImageRank.allCases, id: \.self) { rank in
                Button {
                    if visibleRanks.contains(rank) {
                        visibleRanks.remove(rank)
                    } else {
                        visibleRanks.insert(rank)
                    }
                } label: {
                    Image(systemName: rank.systemImage ?? "circle")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .tint(visibleRanks.contains(rank) ? .accentColor : .secondary)
            }
        }
    }

    // MARK: - Entry List

    private var entryList: some View {
        List {
            ForEach(Array(filteredEntryIndices.enumerated()), id: \.element) { _, entryIndex in
                NavigationLink(value: document.entries[entryIndex].id) {
                    EntryRowView(
                        document: document,
                        entryIndex: entryIndex,
                        visibleRanks: visibleRanks,
                        onSweep: { sweep(entryIndex: entryIndex) }
                    )
                }
                .swipeActions(edge: .leading) {
                    Button { sweep(entryIndex: entryIndex) } label: {
                        Label("Sweep", systemImage: "wind")
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        importTargetEntryID = document.entries[entryIndex].id
                        showImagePicker = true
                    } label: {
                        Label("Add images", systemImage: "photo.badge.plus")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button { sweep(entryIndex: entryIndex) } label: {
                        Label("Sweep candidates", systemImage: "wind")
                    }
                    Button {
                        importTargetEntryID = document.entries[entryIndex].id
                        showImagePicker = true
                    } label: {
                        Label("Add images", systemImage: "photo.badge.plus")
                    }
                    Divider()
                    Button(role: .destructive) {
                        document.entries.remove(at: entryIndex)
                    } label: {
                        Label("Delete entry", systemImage: "trash")
                    }
                }
                .dropDestination(for: Data.self) { items, _ in
                    let entryID = document.entries[entryIndex].id
                    for data in items {
                        document.addImage(data: data, extension: "png", to: entryID)
                    }
                    return !items.isEmpty
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: UUID.self) { entryID in
            if let idx = document.entries.firstIndex(where: { $0.id == entryID }) {
                CaptionEditorView(document: document, entryIndex: idx)
            }
        }
        .overlay {
            if document.entries.isEmpty {
                ContentUnavailableView(
                    "No entries",
                    systemImage: "square.grid.2x2",
                    description: Text("Create an entry to get started.")
                )
            }
        }
    }

    private var filteredEntryIndices: [Int] {
        document.entries.indices.filter { idx in
            let entry = document.entries[idx]
            if filterNoFinal && entry.finalImage != nil { return false }
            if !filterText.isEmpty {
                return entry.name.localizedCaseInsensitiveContains(filterText)
            }
            return true
        }
    }

    private var totalImageCount: Int {
        document.entries.reduce(0) { $0 + $1.imageCount }
    }

    // MARK: - New Entry

    private var newEntrySheet: some View {
        NavigationStack {
            Form {
                TextField("Entry name", text: $newEntryName)
            }
            .navigationTitle("New entry")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNewEntry = false; newEntryName = "" }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addEntry() }
                        .disabled(newEntryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func addEntry() {
        let name = newEntryName.trimmingCharacters(in: .whitespaces)
        document.entries.append(DatasetEntry(name: name))
        showNewEntry = false
        newEntryName = ""
    }

    private func sweep(entryIndex: Int) {
        let entry = document.entries[entryIndex]
        let candidateIndices = entry.images.indices.filter { entry.images[$0].rank == .candidate }
        guard !candidateIndices.isEmpty else { return }

        // Save for undo
        let entryID = entry.id
        let saved: [(Int, ImageRank)] = candidateIndices.map { ($0, entry.images[$0].rank) }

        for i in candidateIndices {
            document.entries[entryIndex].images[i].rank = .discarded
        }

        undoManager?.registerUndo(withTarget: document) { doc in
            guard let idx = doc.entries.firstIndex(where: { $0.id == entryID }) else { return }
            for (imgIdx, rank) in saved where imgIdx < doc.entries[idx].images.count {
                doc.entries[idx].images[imgIdx].rank = rank
            }
        }
        undoManager?.setActionName("Sweep")
    }

    private func emptyTrash() {
        for ei in document.entries.indices.reversed() {
            for ii in document.entries[ei].images.indices.reversed() {
                if document.entries[ei].images[ii].rank == .discarded {
                    let filename = document.entries[ei].images[ii].filename
                    document.entries[ei].images.remove(at: ii)
                    document.removeImageFile(filename)
                }
            }
        }
    }

    private func importImages(urls: [URL], to entryID: UUID) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let ext = url.pathExtension.lowercased()
            document.addImage(data: data, extension: ext, to: entryID)
        }
    }

    private var trashStats: (images: Int, entries: Int) {
        var images = 0
        var entries = 0
        for entry in document.entries {
            let discarded = entry.images.filter { $0.rank == .discarded }.count
            if discarded > 0 {
                images += discarded
                entries += 1
            }
        }
        return (images, entries)
    }
}
