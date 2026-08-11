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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if document.referenceImages.isEmpty {
                ContentUnavailableView(
                    "No reference images",
                    systemImage: "photo.stack",
                    description: Text("Add reference images to use as moodboard hints during generation.")
                )
            } else {
                imageGrid
            }
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
                        onRemove: { imageToRemove = refImage }
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
}

// MARK: - Reference Image Cell

private struct ReferenceImageCell: View {
    let refImage: ReferenceImageDocument
    let bundleURL: URL
    let usageCount: Int
    let onRemove: () -> Void

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
