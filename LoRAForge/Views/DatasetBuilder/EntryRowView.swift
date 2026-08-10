import SwiftUI

struct EntryRowView: View {
    @ObservedObject var document: LoRAForgeDocument
    let entryIndex: Int
    let visibleRanks: Set<ImageRank>
    var onSweep: () -> Void
    var onAddImages: () -> Void
    var onDelete: () -> Void

    private var entry: DatasetEntry { document.entries[entryIndex] }
    private var position: String {
        String(format: "%03d", entryIndex + 1)
    }

    var body: some View {
        HStack(spacing: 0) {
            entryHeader
                .frame(width: 180, alignment: .leading)
                .padding(.trailing, 8)
                .contextMenu { headerContextMenu }
            Divider()
            imageStrip
                .padding(.leading, 8)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header

    private var entryHeader: some View {
        HStack(spacing: 8) {
            Text(position)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            if let finalImg = entry.finalImage,
               let data = document.imageData(for: finalImg.filename),
               let image = Image(imageData: data) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.name)
                        .lineLimit(1)
                    if entry.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.captionText.isEmpty ? "\(entry.imageCount) images" : entry.captionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                NavigationLink(value: document.entries[entryIndex].id) {
                    Image(systemName: "text.bubble")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Caption")

                NavigationLink(value: EntryDestination.generate(document.entries[entryIndex].id)) {
                    Image(systemName: "wand.and.stars")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Generate")
            }
        }
    }

    @ViewBuilder
    private var headerContextMenu: some View {
        NavigationLink(value: EntryDestination.generate(entry.id)) {
            Label("Generate", systemImage: "wand.and.stars")
        }
        Button { onSweep() } label: {
            Label("Sweep candidates", systemImage: "wind")
        }
        Button { onAddImages() } label: {
            Label("Add images", systemImage: "photo.badge.plus")
        }
        Divider()
        Button(role: .destructive) { onDelete() } label: {
            Label("Delete entry", systemImage: "trash")
        }
    }

    // MARK: - Image Strip

    private var imageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(visibleImages) { image in
                    ImageThumbnailView(
                        document: document,
                        image: image,
                        entryIndex: entryIndex
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var visibleImages: [EntryImage] {
        entry.images.filter { visibleRanks.contains($0.rank) }
    }
}

// MARK: - Image Thumbnail

struct ImageThumbnailView: View {
    @ObservedObject var document: LoRAForgeDocument
    let image: EntryImage
    let entryIndex: Int

    @State private var showDiscardFinalWarning = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailImage
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(image.rank == .final ? .yellow : .clear, lineWidth: 2)
                )

            if let symbol = image.rank.systemImage {
                Image(systemName: symbol)
                    .font(.caption2)
                    .padding(3)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(2)
            }
        }
        .contextMenu { rankMenu }
        .alert("Discard final image?", isPresented: $showDiscardFinalWarning) {
            Button("Discard", role: .destructive) { setRank(.discarded) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This entry will have no final image and will not be exported.")
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let data = document.imageData(for: image.filename),
           let img = Image(imageData: data) {
            img.resizable().aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(.quaternary)
                .overlay { Image(systemName: "questionmark").foregroundStyle(.tertiary) }
        }
    }

    @ViewBuilder
    private var rankMenu: some View {
        Button { setRank(.final) } label: {
            Label("Final", systemImage: "star.fill")
        }
        .disabled(image.rank == .final)

        Button { setRank(.shortlist) } label: {
            Label("Shortlist", systemImage: "star")
        }
        .disabled(image.rank == .shortlist)

        Button { setRank(.candidate) } label: {
            Label("Candidate", systemImage: "circle")
        }
        .disabled(image.rank == .candidate)

        Divider()

        Button(role: .destructive) {
            if image.rank == .final {
                showDiscardFinalWarning = true
            } else {
                setRank(.discarded)
            }
        } label: {
            Label("Discard", systemImage: "trash")
        }
        .disabled(image.rank == .discarded)

        if image.provenance != nil {
            Divider()
            Button { recallSettings() } label: {
                Label("Recall settings", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private func setRank(_ newRank: ImageRank) {
        guard let imgIdx = document.entries[entryIndex].images.firstIndex(where: { $0.id == image.id }) else { return }

        // Promoting to final demotes current final to shortlist
        if newRank == .final {
            if let currentFinalIdx = document.entries[entryIndex].images.firstIndex(where: { $0.rank == .final }) {
                document.entries[entryIndex].images[currentFinalIdx].rank = .shortlist
            }
        }

        document.entries[entryIndex].images[imgIdx].rank = newRank
    }

    private func recallSettings() {
        guard let prov = image.provenance else { return }
        document.entries[entryIndex].generationSettings = GenerationSettings(
            prompt: prov.prompt,
            negativePrompt: prov.negativePrompt,
            useCustomSeed: true,
            customSeed: prov.seed,
            configurationJSON: prov.configurationJSON
        )
    }
}
