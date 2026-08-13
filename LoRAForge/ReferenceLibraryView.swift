import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import ImageIO

struct ReferenceLibraryView: View {
    @Binding var document: ProjectDocument
    let bundleURL: URL
    let onChanged: () -> Void

    @State private var showingFilePicker = false
    @State private var imageToRemove: ReferenceImageDocument?
    @State private var imagesToRemove: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var isDropTargeted = false
    @State private var selectedImageIDs: Set<UUID> = []
    @State private var lightboxRefID: UUID?
    #if os(macOS)
    @State private var lightboxManager = LightboxWindowManager()
    #endif

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
                contentArea
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
        .alert("Remove \(imagesToRemove.count) reference images?", isPresented: .init(
            get: { !imagesToRemove.isEmpty },
            set: { if !$0 { imagesToRemove.removeAll() } }
        )) {
            Button("Remove", role: .destructive) { performBulkRemove() }
            Button("Cancel", role: .cancel) { imagesToRemove.removeAll() }
        } message: {
            let totalUsage = imagesToRemove.reduce(0) { $0 + entriesUsing($1) }
            if totalUsage > 0 {
                Text("These images are referenced by entries. Removing them will clear those references.")
            } else {
                Text("These images are not referenced by any entries.")
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

    // MARK: - Content Area

    private var selectedRefInfo: ReferenceImageDocument? {
        guard selectedImageIDs.count == 1, let refID = selectedImageIDs.first else { return nil }
        return document.referenceImages.first { $0.id == refID }
    }

    private var contentArea: some View {
        ZStack(alignment: .bottom) {
            imageGrid

            if !selectedImageIDs.isEmpty {
                selectionToolbar
            }
        }
        .overlay(alignment: .trailing) {
            if let ref = selectedRefInfo {
                HStack(spacing: 0) {
                    Divider()
                    ReferenceInspectorView(
                        refImage: ref,
                        bundleURL: bundleURL,
                        usageCount: entriesUsing(ref.id),
                        onAppendToAll: { appendReferenceToAllEntries(ref.id) },
                        onReplaceInAll: { replaceReferenceInAllEntries(ref.id) },
                        onExport: { exportReferenceImages(Set([ref.id])) },
                        onRemove: { imageToRemove = ref }
                    )
                    .frame(width: 280)
                    .background(.background)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            guard !selectedImageIDs.isEmpty else { return .ignored }
            selectedImageIDs.removeAll()
            return .handled
        }
        #if os(iOS)
        .fullScreenCover(item: $lightboxRefID) { refID in
            ReferenceLightboxView(
                referenceImages: document.referenceImages,
                bundleURL: bundleURL,
                initialRefID: refID
            )
        }
        #else
        .onChange(of: lightboxRefID) { _, refID in
            if let refID {
                lightboxManager.show(
                    ReferenceLightboxView(
                        referenceImages: document.referenceImages,
                        bundleURL: bundleURL,
                        initialRefID: refID,
                        onDismiss: { lightboxRefID = nil }
                    ),
                    onClose: { lightboxRefID = nil }
                )
            } else {
                lightboxManager.close()
            }
        }
        .onDisappear { lightboxManager.close() }
        #endif
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
                        isSelected: selectedImageIDs.contains(refImage.id),
                        onTap: { multi in selectImage(refImage.id, multiSelect: multi) },
                        onDoubleTap: { lightboxRefID = refImage.id },
                        onRemove: { imageToRemove = refImage },
                        onAppendToAll: { appendReferenceToAllEntries(refImage.id) },
                        onReplaceInAll: { replaceReferenceInAllEntries(refImage.id) },
                        onExport: { exportReferenceImages(Set([refImage.id])) }
                    )
                }
            }
            .padding()
        }
        .onTapGesture {
            selectedImageIDs.removeAll()
        }
    }

    // MARK: - Selection Toolbar

    private var selectionToolbar: some View {
        HStack(spacing: 16) {
            Text("\(selectedImageIDs.count) selected")
                .font(.subheadline.weight(.medium))

            Button("Append to all entries", systemImage: "plus.rectangle.on.rectangle") {
                if let refID = selectedImageIDs.first {
                    appendReferenceToAllEntries(refID)
                }
            }
            .disabled(selectedImageIDs.count > 1)

            Button("Replace in all entries", systemImage: "arrow.triangle.2.circlepath") {
                for refID in selectedImageIDs {
                    replaceReferenceInAllEntries(refID)
                }
            }
            .disabled(selectedImageIDs.count > 4)

            Button("Remove", systemImage: "trash", role: .destructive) {
                if selectedImageIDs.count == 1, let refID = selectedImageIDs.first,
                   let ref = document.referenceImages.first(where: { $0.id == refID }) {
                    imageToRemove = ref
                } else {
                    imagesToRemove = selectedImageIDs
                }
            }

            Divider().frame(height: 20)

            Button {
                exportReferenceImages(selectedImageIDs)
            } label: {
                Label(
                    selectedImageIDs.count == 1 ? "Export" : "Export \(selectedImageIDs.count) images",
                    systemImage: "square.and.arrow.up"
                )
            }
            .help("Export selected images")

            Spacer()

            Button("Deselect") {
                selectedImageIDs.removeAll()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - Selection

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
        selectedImageIDs.remove(img.id)
        imageToRemove = nil
        onChanged()
    }

    private func performBulkRemove() {
        for refID in imagesToRemove {
            guard let ref = document.referenceImages.first(where: { $0.id == refID }) else { continue }

            for i in document.entries.indices {
                document.entries[i].referenceImageIDs.removeAll { $0 == refID }
            }

            let fileURL = bundleURL.appending(path: "references/\(ref.filename)")
            try? FileManager.default.removeItem(at: fileURL)

            document.referenceImages.removeAll { $0.id == refID }
        }
        selectedImageIDs.subtract(imagesToRemove)
        imagesToRemove.removeAll()
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

    private func exportReferenceImages(_ ids: Set<UUID>) {
        var fileURLs: [URL] = []
        for ref in document.referenceImages where ids.contains(ref.id) {
            fileURLs.append(bundleURL.appending(path: "references/\(ref.filename)"))
        }
        guard !fileURLs.isEmpty else { return }

        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Choose export folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            for fileURL in fileURLs {
                let dest = folder.appending(path: fileURL.lastPathComponent)
                try? FileManager.default.copyItem(at: fileURL, to: dest)
            }
        }
        #else
        let controller = UIActivityViewController(activityItems: fileURLs, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.keyWindow?.rootViewController {
            root.present(controller, animated: true)
        }
        #endif
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
    let isSelected: Bool
    let onTap: (_ multiSelect: Bool) -> Void
    let onDoubleTap: () -> Void
    let onRemove: () -> Void
    let onAppendToAll: () -> Void
    let onReplaceInAll: () -> Void
    let onExport: () -> Void

    @State private var lastTapTime = Date.distantPast

    private var imageURL: URL {
        bundleURL.appending(path: "references/\(refImage.filename)")
    }

    var body: some View {
        VStack(spacing: 4) {
            ThumbnailView(url: imageURL, size: 140)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                )

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
        .contextMenu {
            Button("Append to all entries", systemImage: "plus.rectangle.on.rectangle") {
                onAppendToAll()
            }
            Button("Replace in all entries", systemImage: "arrow.triangle.2.circlepath") {
                onReplaceInAll()
            }
            Divider()
            Button("Export image", systemImage: "square.and.arrow.up") {
                onExport()
            }
            Divider()
            Button("Remove", systemImage: "trash", role: .destructive) {
                onRemove()
            }
        }
    }
}

// MARK: - Reference Inspector View

private struct ReferenceInspectorView: View {
    let refImage: ReferenceImageDocument
    let bundleURL: URL
    let usageCount: Int
    let onAppendToAll: () -> Void
    let onReplaceInAll: () -> Void
    let onExport: () -> Void
    let onRemove: () -> Void

    private var imageURL: URL {
        bundleURL.appending(path: "references/\(refImage.filename)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                fileInfoSection
                usageSection
                actionSection
            }
            .padding()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(refImage.filename)
                .font(.headline)
                .lineLimit(2)
        }
    }

    // MARK: - File Info

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("File details")

            if let dimensions = imageDimensions {
                settingRow("Dimensions", value: "\(dimensions.width) \u{00D7} \(dimensions.height)")
            }

            if let fileSize = formattedFileSize {
                settingRow("File size", value: fileSize)
            }

            settingRow("Date added", value: refImage.addedAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    // MARK: - Usage

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Usage")
            if usageCount > 0 {
                Text("Used by \(usageCount) entr\(usageCount == 1 ? "y" : "ies")")
                    .font(.caption)
            } else {
                Text("Unused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack {
            Divider()

            Button(action: onAppendToAll) {
                Label("Append to all entries", systemImage: "plus.rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: onReplaceInAll) {
                Label("Replace in all entries", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: onExport) {
                Label("Export image", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            #if os(macOS)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([imageURL])
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            #else
            ShareLink(item: imageURL) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            #endif

            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private var imageDimensions: (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }

    private var formattedFileSize: String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: imageURL.path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func settingRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
    }
}
