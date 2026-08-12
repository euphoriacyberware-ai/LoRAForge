import SwiftUI

struct LightboxTarget: Identifiable {
    let id = UUID()
    let entryID: UUID
    let imageID: UUID
}

struct LightboxView: View {
    @Binding var document: ProjectDocument
    let bundleURL: URL
    let initialEntryID: UUID
    let initialImageID: UUID
    let visibleRanks: Set<ImageRank>
    let onChanged: () -> Void

    @State private var currentEntryID: UUID
    @State private var currentImageID: UUID
    @State private var zoomLevel: Int = 0 // 0 = fit, 1..5 = zoom steps
    @State private var nativeImageSize: CGSize = .zero
    @State private var discardFinalAlert: LightboxDiscardAlert?
    @State private var lastKnownSize: CGSize = .zero
    #if os(macOS)
    @AppStorage("lightboxWidth") private var savedWidth: Double = 1100
    @AppStorage("lightboxHeight") private var savedHeight: Double = 800
    #endif
    @Environment(\.dismiss) private var dismiss

    // zoomLevel 1 = 50%, 2 = 75%, 3 = 100%, 4 = 150%, 5 = 200%
    private static let zoomSteps: [CGFloat] = [0.5, 0.75, 1.0, 1.5, 2.0]

    init(document: Binding<ProjectDocument>, bundleURL: URL, initialEntryID: UUID, initialImageID: UUID, visibleRanks: Set<ImageRank>, onChanged: @escaping () -> Void) {
        self._document = document
        self.bundleURL = bundleURL
        self.initialEntryID = initialEntryID
        self.initialImageID = initialImageID
        self.visibleRanks = visibleRanks
        self.onChanged = onChanged
        self._currentEntryID = State(initialValue: initialEntryID)
        self._currentImageID = State(initialValue: initialImageID)
    }

    private var filteredEntries: [EntryDocument] {
        document.entries.filter { entry in
            entry.images.contains { visibleRanks.contains($0.rank) }
        }
    }

    private var currentEntry: EntryDocument? {
        document.entries.first { $0.id == currentEntryID }
    }

    private var currentVisibleImages: [ImageDocument] {
        currentEntry?.images.filter { visibleRanks.contains($0.rank) } ?? []
    }

    private var currentImage: ImageDocument? {
        currentEntry?.images.first { $0.id == currentImageID }
    }

    private var currentImageIndex: Int? {
        currentVisibleImages.firstIndex { $0.id == currentImageID }
    }

    private var imagePositionLabel: String {
        guard let entry = currentEntry, let idx = currentImageIndex else { return "" }
        return "\(entry.name) \u{00B7} Image \(idx + 1) of \(currentVisibleImages.count)"
    }

    private var currentImageURL: URL? {
        guard let image = currentImage else { return nil }
        return bundleURL.appending(path: "images/\(image.filename)")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            imageArea
            Divider()
            bottomBar
        }
        #if os(macOS)
        .frame(minWidth: 800, idealWidth: savedWidth, maxWidth: .infinity,
               minHeight: 600, idealHeight: savedHeight, maxHeight: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear.onChange(of: geo.size) { _, newSize in
                    lastKnownSize = newSize
                }
            }
        )
        .onDisappear {
            if lastKnownSize.width > 0 {
                savedWidth = lastKnownSize.width
                savedHeight = lastKnownSize.height
            }
        }
        #endif
        .alert(item: $discardFinalAlert) { alert in
            Alert(
                title: Text("Discard final image?"),
                message: Text("This entry will have no final image and will not be exported."),
                primaryButton: .destructive(Text("Discard")) {
                    applyRank(.discarded)
                },
                secondaryButton: .cancel()
            )
        }
        .task(id: currentImageID) {
            loadNativeSize()
        }
        #if os(macOS)
        .onKeyPress(.leftArrow) { navigateLeft(); return .handled }
        .onKeyPress(.rightArrow) { navigateRight(); return .handled }
        .onKeyPress(.upArrow) { navigateUp(); return .handled }
        .onKeyPress(.downArrow) { navigateDown(); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(imagePositionLabel)
                .font(.headline)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Image Area

    private var imageArea: some View {
        HStack(spacing: 0) {
            navButton(systemName: "chevron.left", action: navigateLeft, disabled: !canNavigateLeft)

            VStack(spacing: 0) {
                navButton(systemName: "chevron.up", action: navigateUp, disabled: !canNavigateUp)
                mainImageView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                navButton(systemName: "chevron.down", action: navigateDown, disabled: !canNavigateDown)
            }

            navButton(systemName: "chevron.right", action: navigateRight, disabled: !canNavigateRight)
        }
    }

    private func navButton(systemName: String, action: @escaping () -> Void, disabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
    }

    @ViewBuilder
    private var mainImageView: some View {
        if let url = currentImageURL {
            if zoomLevel == 0 {
                loadImage(from: url)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let factor = Self.zoomSteps[zoomLevel - 1]
                ScrollView([.horizontal, .vertical]) {
                    loadImage(from: url)
                        .frame(
                            width: nativeImageSize.width * factor,
                            height: nativeImageSize.height * factor
                        )
                }
            }
        } else {
            imagePlaceholder
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func loadImage(from url: URL) -> some View {
        #if os(macOS)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
        } else {
            imagePlaceholder
        }
        #else
        if let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
        } else {
            imagePlaceholder
        }
        #endif
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            zoomControls
            Spacer()
            rankButtons
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button("Fit") { zoomLevel = 0 }
                .buttonStyle(.bordered)
                .font(.caption)

            Button { if zoomLevel > 1 { zoomLevel -= 1 } } label: {
                Image(systemName: "minus")
            }
            .disabled(zoomLevel <= 1)

            Text(zoomLevel == 0 ? "Fit" : "\(Int(Self.zoomSteps[zoomLevel - 1] * 100))%")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 40)

            Button {
                if zoomLevel == 0 { zoomLevel = 1 }
                else if zoomLevel < Self.zoomSteps.count { zoomLevel += 1 }
            } label: {
                Image(systemName: "plus")
            }
            .disabled(zoomLevel >= Self.zoomSteps.count)

            Button("100%") { zoomLevel = 3 }
                .buttonStyle(.bordered)
                .font(.caption)
        }
    }

    private var rankButtons: some View {
        HStack(spacing: 4) {
            ForEach([ImageRank.candidate, .shortlist, .final], id: \.self) { rank in
                Button {
                    handleRankChange(rank)
                } label: {
                    if let icon = rank.badgeIcon {
                        Label(rank.label, systemImage: icon)
                    } else {
                        Text(rank.label)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(currentImage?.rank == rank)
            }

            if let image = currentImage, image.rank != .discarded {
                Button { handleRankChange(.discarded) } label: {
                    Image(systemName: "trash")
                }
                .help("Discard")
            }
        }
    }

    // MARK: - Navigation

    private var canNavigateLeft: Bool {
        guard let idx = currentImageIndex else { return false }
        return idx > 0
    }

    private var canNavigateRight: Bool {
        guard let idx = currentImageIndex else { return false }
        return idx < currentVisibleImages.count - 1
    }

    private var canNavigateUp: Bool {
        guard let entryIdx = filteredEntries.firstIndex(where: { $0.id == currentEntryID }) else { return false }
        return entryIdx > 0
    }

    private var canNavigateDown: Bool {
        guard let entryIdx = filteredEntries.firstIndex(where: { $0.id == currentEntryID }) else { return false }
        return entryIdx < filteredEntries.count - 1
    }

    private func navigateLeft() {
        guard let idx = currentImageIndex, idx > 0 else { return }
        currentImageID = currentVisibleImages[idx - 1].id
        zoomLevel = 0
    }

    private func navigateRight() {
        guard let idx = currentImageIndex, idx < currentVisibleImages.count - 1 else { return }
        currentImageID = currentVisibleImages[idx + 1].id
        zoomLevel = 0
    }

    private func navigateUp() {
        guard let entryIdx = filteredEntries.firstIndex(where: { $0.id == currentEntryID }),
              entryIdx > 0 else { return }
        let newEntry = filteredEntries[entryIdx - 1]
        let newImages = newEntry.images.filter { visibleRanks.contains($0.rank) }
        guard !newImages.isEmpty else { return }
        let targetIdx = min(currentImageIndex ?? 0, newImages.count - 1)
        currentEntryID = newEntry.id
        currentImageID = newImages[targetIdx].id
        zoomLevel = 0
    }

    private func navigateDown() {
        guard let entryIdx = filteredEntries.firstIndex(where: { $0.id == currentEntryID }),
              entryIdx < filteredEntries.count - 1 else { return }
        let newEntry = filteredEntries[entryIdx + 1]
        let newImages = newEntry.images.filter { visibleRanks.contains($0.rank) }
        guard !newImages.isEmpty else { return }
        let targetIdx = min(currentImageIndex ?? 0, newImages.count - 1)
        currentEntryID = newEntry.id
        currentImageID = newImages[targetIdx].id
        zoomLevel = 0
    }

    // MARK: - Ranking

    private func handleRankChange(_ newRank: ImageRank) {
        guard let image = currentImage else { return }
        if newRank == .discarded && image.rank == .final {
            discardFinalAlert = LightboxDiscardAlert(imageID: image.id, entryID: currentEntryID)
            return
        }
        applyRank(newRank)
    }

    private func applyRank(_ newRank: ImageRank) {
        guard let entryIdx = document.entries.firstIndex(where: { $0.id == currentEntryID }),
              let imgIdx = document.entries[entryIdx].images.firstIndex(where: { $0.id == currentImageID }) else { return }

        let oldVisibleIndex = currentImageIndex ?? 0

        if newRank == .final {
            for i in document.entries[entryIdx].images.indices {
                if document.entries[entryIdx].images[i].rank == .final {
                    document.entries[entryIdx].images[i].rank = .shortlist
                }
            }
        }

        document.entries[entryIdx].images[imgIdx].rank = newRank
        onChanged()

        if !visibleRanks.contains(newRank) {
            let remaining = currentVisibleImages
            if !remaining.isEmpty {
                let targetIdx = min(oldVisibleIndex, remaining.count - 1)
                currentImageID = remaining[targetIdx].id
            } else {
                let entries = filteredEntries
                if let nextEntry = entries.first,
                   let firstImage = nextEntry.images.first(where: { visibleRanks.contains($0.rank) }) {
                    currentEntryID = nextEntry.id
                    currentImageID = firstImage.id
                } else {
                    dismiss()
                }
            }
            zoomLevel = 0
        }
    }

    // MARK: - Helpers

    private func loadNativeSize() {
        guard let url = currentImageURL else {
            nativeImageSize = .zero
            return
        }
        #if os(macOS)
        guard let nsImage = NSImage(contentsOf: url),
              let rep = nsImage.representations.first else {
            nativeImageSize = .zero
            return
        }
        nativeImageSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        #else
        guard let data = try? Data(contentsOf: url),
              let uiImage = UIImage(data: data) else {
            nativeImageSize = .zero
            return
        }
        nativeImageSize = CGSize(width: uiImage.size.width * uiImage.scale, height: uiImage.size.height * uiImage.scale)
        #endif
    }
}

private struct LightboxDiscardAlert: Identifiable {
    let id = UUID()
    let imageID: UUID
    let entryID: UUID
}
