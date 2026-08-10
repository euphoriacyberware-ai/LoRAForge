import SwiftUI
import UniformTypeIdentifiers

struct ReferenceLibraryView: View {
    @ObservedObject var document: LoRAForgeDocument

    @State private var showImagePicker = false
    @State private var pendingDeleteRef: ReferenceImage?
    @State private var showDeleteWarning = false
    @State private var selectedRefID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if document.referenceImages.isEmpty {
                    ContentUnavailableView(
                        "Reference library",
                        systemImage: "photo.on.rectangle",
                        description: Text("Add reference images for generation moodboard hints.\nDrag and drop images or use the add button.")
                    )
                } else {
                    imageGrid
                }
            }
            .navigationTitle("Reference library")
            .withSettingsAccess()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showImagePicker = true } label: {
                        Label("Add images", systemImage: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImagePicker,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { importImages(urls: urls) }
            }
            .dropDestination(for: Data.self) { items, _ in
                for data in items {
                    document.addReferenceImage(data: data, extension: "png")
                }
                return !items.isEmpty
            }
            .alert("Remove reference image?", isPresented: $showDeleteWarning) {
                Button("Remove", role: .destructive) { performDelete() }
                Button("Cancel", role: .cancel) { pendingDeleteRef = nil }
            } message: {
                if let ref = pendingDeleteRef {
                    let entryCount = document.entriesUsing(referenceID: ref.id).count
                    let provCount = document.provenanceCount(for: ref.id)
                    Text("Used by \(entryCount) entries, referenced by \(provCount) stored images.")
                }
            }
        }
    }

    // MARK: - Grid

    private var imageGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(document.referenceImages) { ref in
                    refCard(ref)
                }
            }
            .padding()
        }
    }

    private func refCard(_ ref: ReferenceImage) -> some View {
        VStack(spacing: 4) {
            if let data = document.imageData(for: ref.filename),
               let image = Image(imageData: data) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 130, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 130, height: 130)
                    .overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
            }

            let usageCount = document.entriesUsing(referenceID: ref.id).count
            Text(usageCount == 0 ? "Unused" : "\(usageCount) entries")
                .font(.caption2)
                .foregroundStyle(usageCount == 0 ? .orange : .secondary)
        }
        .overlay(alignment: .topTrailing) {
            // Slot count badge for entries using this image
            let count = document.entriesUsing(referenceID: ref.id).count
            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .padding(4)
                    .background(.blue, in: Circle())
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDeleteRef = ref
                showDeleteWarning = true
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func importImages(urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let ext = url.pathExtension.lowercased()
            document.addReferenceImage(data: data, extension: ext)
        }
    }

    private func performDelete() {
        guard let ref = pendingDeleteRef else { return }
        document.removeReferenceImage(id: ref.id)
        pendingDeleteRef = nil
    }
}
