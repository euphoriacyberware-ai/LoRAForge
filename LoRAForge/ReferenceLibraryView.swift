import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

struct ReferenceLibraryView: View {
    @Binding var document: ProjectDocument
    let bundleURL: URL
    let onChanged: () -> Void

    @State private var showingFilePicker = false
    @State private var imageToRemove: ReferenceImageDocument?
    @State private var errorMessage: String?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if document.referenceImages.isEmpty {
                ContentUnavailableView(
                    "No reference images",
                    systemImage: "photo.stack",
                    description: Text("Drop images here or use the + button to add reference images.")
                )
            } else {
                imageGrid
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.1))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .navigationTitle("Reference Library")
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                importImages(urls)
            }
        }
        .alert("Remove reference image?", isPresented: .init(
            get: { imageToRemove != nil },
            set: { if !$0 { imageToRemove = nil } }
        )) {
            Button("Remove", role: .destructive) { performRemove() }
            Button("Cancel", role: .cancel) { imageToRemove = nil }
        } message: {
            if let img = imageToRemove {
                let usage = entriesUsing(img.id)
                if usage > 0 {
                    Text("This image is referenced by \(usage) entr\(usage == 1 ? "y" : "ies"). Removing it will clear those references.")
                } else {
                    Text("This image is not referenced by any entries.")
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("\(document.referenceImages.count) reference image\(document.referenceImages.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Spacer()
            Button { showingFilePicker = true } label: {
                Label("Add images", systemImage: "plus")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Grid

    private var imageGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(document.referenceImages) { refImage in
                    ReferenceImageCell(
                        refImage: refImage,
                        bundleURL: bundleURL,
                        usageCount: entriesUsing(refImage.id),
                        onRemove: { imageToRemove = refImage },
                        onAppendToAll: { appendReferenceToAllEntries(refImage.id) },
                        onReplaceInAll: { replaceReferenceInAllEntries(refImage.id) }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func importImages(_ urls: [URL]) {
        let refsDir = bundleURL.appending(path: "references")
        try? FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let data = try? Data(contentsOf: url) else { continue }

            // Deduplicate on content hash
            let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            if document.referenceImages.contains(where: { $0.contentHash == hash }) {
                continue // silently skip duplicate
            }

            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            let filename = "\(UUID().uuidString).\(ext)"
            let dest = refsDir.appending(path: filename)

            do {
                try data.write(to: dest)
                let refDoc = ReferenceImageDocument(filename: filename, contentHash: hash)
                document.referenceImages.append(refDoc)
            } catch {
                errorMessage = "Failed to import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        onChanged()
    }

    private func performRemove() {
        guard let img = imageToRemove else { return }

        // Remove from entries' reference slots
        for i in document.entries.indices {
            document.entries[i].referenceImageIDs.removeAll { $0 == img.id }
        }

        // Remove file
        let fileURL = bundleURL.appending(path: "references/\(img.filename)")
        try? FileManager.default.removeItem(at: fileURL)

        // Remove from library
        document.referenceImages.removeAll { $0.id == img.id }
        imageToRemove = nil
        onChanged()
    }

    private func entriesUsing(_ refID: UUID) -> Int {
        document.entries.filter { $0.referenceImageIDs.contains(refID) }.count
    }

    private func appendReferenceToAllEntries(_ refID: UUID) {
        for i in document.entries.indices {
            if !document.entries[i].referenceImageIDs.contains(refID) {
                document.entries[i].referenceImageIDs.append(refID)
            }
        }
        onChanged()
    }

    private func replaceReferenceInAllEntries(_ refID: UUID) {
        for i in document.entries.indices {
            document.entries[i].referenceImageIDs = [refID]
        }
        onChanged()
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            // Try file URL first (Finder drag)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    Task { @MainActor in
                        importImages([url])
                    }
                }
            }
            // Try image data (Photos app, other apps)
            else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        importImageData(data)
                    }
                }
            }
        }
    }

    private func importImageData(_ data: Data) {
        let refsDir = bundleURL.appending(path: "references")
        try? FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)

        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        if document.referenceImages.contains(where: { $0.contentHash == hash }) {
            return // duplicate
        }

        let filename = "\(UUID().uuidString).png"
        let dest = refsDir.appending(path: filename)

        do {
            try data.write(to: dest)
            let refDoc = ReferenceImageDocument(filename: filename, contentHash: hash)
            document.referenceImages.append(refDoc)
            onChanged()
        } catch {
            errorMessage = "Failed to import dropped image: \(error.localizedDescription)"
        }
    }
}

// MARK: - Reference Image Cell

private struct ReferenceImageCell: View {
    let refImage: ReferenceImageDocument
    let bundleURL: URL
    let usageCount: Int
    let onRemove: () -> Void
    let onAppendToAll: () -> Void
    let onReplaceInAll: () -> Void

    private var imageURL: URL {
        bundleURL.appending(path: "references/\(refImage.filename)")
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                loadedImage
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .padding(4)
            }

            if usageCount > 0 {
                Text("Used by \(usageCount) entr\(usageCount == 1 ? "y" : "ies")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Unused")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            Button("Append to all entries", systemImage: "plus.rectangle.on.rectangle") {
                onAppendToAll()
            }
            Button("Replace in all entries", systemImage: "arrow.triangle.2.circlepath") {
                onReplaceInAll()
            }
            Divider()
            Button("Remove", systemImage: "trash", role: .destructive) {
                onRemove()
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
            imagePlaceholder
        }
        #else
        if let data = try? Data(contentsOf: imageURL),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            imagePlaceholder
        }
        #endif
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
    }
}
