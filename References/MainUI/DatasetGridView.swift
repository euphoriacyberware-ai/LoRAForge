//
//  DatasetGridView.swift
//  LoRA Dataset Builder — UI mockup
//
//  Static mockup for Xcode previews. No trainer, no image backend.
//  Requires macOS 13+ / Xcode 15+.
//

import SwiftUI
import Combine

// MARK: - Caption model

/// One category's contribution to a caption. Mirrors the category model in the
/// design notes: a name, an optional prefix, single or multi select.
struct CaptionSegment: Identifiable, Hashable {
    let id: UUID
    var categoryName: String
    var prefix: String?
    var isMulti: Bool
    var values: [String]

    init(id: UUID = UUID(), _ categoryName: String, prefix: String? = nil,
         isMulti: Bool = false, values: [String] = []) {
        self.id = id
        self.categoryName = categoryName
        self.prefix = prefix
        self.isMulti = isMulti
        self.values = values
    }
}

/// Tags are the source of truth; the caption string is a render target.
struct CaptionSettings: Hashable {
    var segments: [CaptionSegment]
    /// When set, replaces the rendered caption entirely.
    var manualOverride: String?

    var rendered: String {
        if let manualOverride, !manualOverride.isEmpty { return manualOverride }
        return segments.compactMap { segment -> String? in
            guard !segment.values.isEmpty else { return nil }
            let joined = segment.values.joined(separator: " and ")
            if let prefix = segment.prefix, !prefix.isEmpty { return "\(prefix) \(joined)" }
            return joined
        }
        .joined(separator: ", ")
    }

    var isEmpty: Bool { rendered.isEmpty }

    /// Number of categories carrying at least one tag.
    var filledCount: Int { segments.filter { !$0.values.isEmpty }.count }

    /// The built-in category template, in default order.
    static func template(trigger: String = "") -> CaptionSettings {
        CaptionSettings(segments: [
            CaptionSegment("Subject", values: trigger.isEmpty ? [] : [trigger]),
            CaptionSegment("Framing"),
            CaptionSegment("Camera Angle"),
            CaptionSegment("Pose"),
            CaptionSegment("Gaze"),
            CaptionSegment("Expression"),
            CaptionSegment("Lighting"),
            CaptionSegment("Hairstyle"),
            CaptionSegment("Clothing", prefix: "wearing", isMulti: true),
            CaptionSegment("Held-Items", prefix: "holding", isMulti: true),
            CaptionSegment("Background-Location")
        ], manualOverride: nil)
    }

    func setting(_ category: String, to values: [String]) -> CaptionSettings {
        var copy = self
        if let index = copy.segments.firstIndex(where: { $0.categoryName == category }) {
            copy.segments[index].values = values
        }
        return copy
    }
}

// MARK: - Generation model

struct GenerationSettings: Hashable {
    var prompt: String = ""
    var negativePrompt: String = ""
    var usesCustomSeed: Bool = false
    var seed: Int = 0
    var referenceImageCount: Int = 0
    var usesCustomConfig: Bool = false
    var configJSON: String = """
    {
      "steps": 30,
      "cfg_scale": 7.0,
      "sampler": "dpmpp_2m",
      "scheduler": "karras",
      "width": 1024,
      "height": 1024,
      "batch_size": 4
    }
    """
}

// MARK: - Image + entry

struct DatasetImage: Identifiable, Hashable {
    let id = UUID()
    /// Stands in for a real asset in the mockup.
    var artSeed: Int
    var symbol: String = "person.crop.rectangle"
    /// nil means "inherit the entry caption".
    var captionOverride: CaptionSettings?
    var isApproved: Bool = true
}

struct DatasetEntry: Identifiable {
    let id = UUID()
    var name: String
    var caption: CaptionSettings
    var generation: GenerationSettings
    var images: [DatasetImage]

    var coverArtSeed: Int { images.first?.artSeed ?? 0 }
    var coverSymbol: String { images.first?.symbol ?? "person.crop.rectangle" }

    /// Stand-in for the coverage audit in the design notes.
    var flagCount: Int {
        caption.segments.filter { $0.values.isEmpty && !$0.isMulti }.count > 6 ? 2 : 0
    }
}

// MARK: - Store

final class DatasetStore: ObservableObject {
    @Published var projectName: String
    @Published var entries: [DatasetEntry]

    init(projectName: String, entries: [DatasetEntry]) {
        self.projectName = projectName
        self.entries = entries
    }

    var totalImages: Int { entries.reduce(0) { $0 + $1.images.count } }

    func index(of id: DatasetEntry.ID) -> Int? {
        entries.firstIndex { $0.id == id }
    }
}

// MARK: - Which editor is open

enum EditorSheet: Identifiable {
    case generation(DatasetEntry.ID)
    case caption(DatasetEntry.ID, DatasetImage.ID?)

    var id: String {
        switch self {
        case .generation(let entry):
            return "generation-\(entry.uuidString)"
        case .caption(let entry, let image):
            return "caption-\(entry.uuidString)-\(image?.uuidString ?? "entry")"
        }
    }
}

// MARK: - Root

struct DatasetGridView: View {
    @StateObject private var store = DatasetStore.sample
    @State private var cellHeight: CGFloat = 148
    @State private var selection: DatasetImage.ID?
    @State private var sheet: EditorSheet?
    @State private var search: String = ""

    private let headerWidth: CGFloat = 268

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            grid
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $sheet) { sheet in
            editor(for: sheet)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.projectName)
                    .font(.headline)
                Text("\(store.entries.count) entries · \(store.totalImages) images")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            TextField("Filter entries", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Slider(value: $cellHeight, in: 96...240)
                    .frame(width: 110)
                Image(systemName: "photo")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 20)

            Button {
            } label: {
                Label("Audit", systemImage: "chart.bar.doc.horizontal")
            }

            Button {
            } label: {
                Label("New entry", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach($store.entries) { $entry in
                    DatasetEntryRow(
                        entry: $entry,
                        headerWidth: headerWidth,
                        cellHeight: cellHeight,
                        selection: $selection,
                        openEditor: { sheet = $0 }
                    )
                    Divider()
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: Sheets

    @ViewBuilder
    private func editor(for sheet: EditorSheet) -> some View {
        switch sheet {
        case .generation(let entryID):
            if let index = store.index(of: entryID) {
                EntryGenerationEditor(
                    name: $store.entries[index].name,
                    settings: $store.entries[index].generation
                )
            }
        case .caption(let entryID, let imageID):
            if let index = store.index(of: entryID) {
                EntryCaptionEditor(
                    entry: $store.entries[index],
                    focusedImageID: imageID ?? store.entries[index].images.first?.id
                )
            }
        }
    }
}

// MARK: - One entry = one row

struct DatasetEntryRow: View {
    @Binding var entry: DatasetEntry
    let headerWidth: CGFloat
    let cellHeight: CGFloat
    @Binding var selection: DatasetImage.ID?
    var openEditor: (EditorSheet) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            EntryHeaderCell(entry: $entry, openEditor: openEditor)
                .frame(width: headerWidth)
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(entry.images) { image in
                        DatasetImageCell(
                            image: image,
                            height: cellHeight,
                            isSelected: selection == image.id
                        )
                        .onTapGesture { selection = image.id }
                        .onTapGesture(count: 2) {
                            openEditor(.caption(entry.id, image.id))
                        }
                        .contextMenu {
                            Button("Edit caption…") { openEditor(.caption(entry.id, image.id)) }
                            Button("Use as cover") {}
                            Divider()
                            Button("Remove from entry", role: .destructive) {}
                        }
                    }

                    AddImagesCell(height: cellHeight)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .frame(height: cellHeight + 24)
    }
}

// MARK: - Header cell

struct EntryHeaderCell: View {
    @Binding var entry: DatasetEntry
    var openEditor: (EditorSheet) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PlaceholderArt(seed: entry.coverArtSeed, symbol: entry.coverSymbol)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.black.opacity(0.12))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Text(entry.caption.isEmpty ? "No caption yet" : entry.caption.rendered)
                    .font(.system(size: 11))
                    .foregroundStyle(entry.caption.isEmpty ? .tertiary : .secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 2)

                HStack(spacing: 6) {
                    Chip(text: "\(entry.images.count) images", systemImage: "square.grid.2x2")
                    Chip(text: "\(entry.caption.filledCount)/\(entry.caption.segments.count)",
                         systemImage: "tag")
                    if entry.flagCount > 0 {
                        Chip(text: "\(entry.flagCount)",
                             systemImage: "exclamationmark.triangle",
                             tint: .orange)
                    }
                }
            }

            VStack(spacing: 2) {
                EntryIconButton(systemName: "wand.and.stars", help: "Generation settings") {
                    openEditor(.generation(entry.id))
                }
                EntryIconButton(systemName: "text.bubble", help: "Caption settings") {
                    openEditor(.caption(entry.id, nil))
                }
                EntryIconButton(systemName: "photo.badge.plus", help: "Add images") {}
                EntryIconButton(systemName: "square.and.arrow.up", help: "Export entry") {}

                Menu {
                    Button("Rename…") {}
                    Button("Duplicate entry") {}
                    Divider()
                    Button("Delete entry", role: .destructive) {}
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26, height: 26)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

// MARK: - Image cell

struct DatasetImageCell: View {
    let image: DatasetImage
    let height: CGFloat
    let isSelected: Bool

    var body: some View {
        PlaceholderArt(seed: image.artSeed, symbol: image.symbol)
            .frame(width: height * 0.78, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if image.captionOverride != nil {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .padding(5)
                        .help("Caption overridden for this image")
                }
            }
            .overlay(alignment: .topTrailing) {
                if !image.isApproved {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .padding(5)
                        .help("Excluded from export")
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .black.opacity(0.12),
                                  lineWidth: isSelected ? 2.5 : 1)
            }
            .opacity(image.isApproved ? 1 : 0.45)
    }
}

struct AddImagesCell: View {
    let height: CGFloat
    @State private var hovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(hovering ? Color.accentColor : Color.secondary.opacity(0.4))
            .frame(width: height * 0.78, height: height)
            .overlay {
                VStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                    Text("Drop images")
                        .font(.system(size: 10))
                }
                .foregroundStyle(hovering ? Color.accentColor : Color.secondary)
            }
            .onHover { hovering = $0 }
    }
}

// MARK: - Small parts

struct EntryIconButton: View {
    let systemName: String
    let help: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.09) : .clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9))
            }
            Text(text).font(.system(size: 10))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(0.12))
        }
    }
}

/// Stands in for real image data so the mockup renders without assets.
struct PlaceholderArt: View {
    let seed: Int
    var symbol: String = "person.crop.rectangle"

    private var hue: Double {
        Double((seed &* 53) % 360) / 360.0
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.28, brightness: 0.86),
                    Color(hue: (hue + 0.07).truncatingRemainder(dividingBy: 1.0),
                          saturation: 0.42, brightness: 0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Flow layout for tag chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Sample data

extension DatasetStore {
    static var sample: DatasetStore {
        DatasetStore(projectName: "Maya — character LoRA", entries: [
            DatasetEntry(
                name: "Hotel lobby set",
                caption: CaptionSettings.template(trigger: "m4y4")
                    .setting("Framing", to: ["medium shot"])
                    .setting("Camera Angle", to: ["three-quarter view"])
                    .setting("Pose", to: ["standing"])
                    .setting("Gaze", to: ["looking at viewer"])
                    .setting("Expression", to: ["smiling"])
                    .setting("Lighting", to: ["warm overhead lighting"])
                    .setting("Hairstyle", to: ["hair down"])
                    .setting("Clothing", to: ["yellow sundress", "white hat"])
                    .setting("Held-Items", to: ["black purse"])
                    .setting("Background-Location", to: ["hotel lobby background"]),
                generation: GenerationSettings(
                    prompt: "m4y4 standing in a hotel lobby, warm overhead light",
                    negativePrompt: "blurry, extra fingers, watermark",
                    referenceImageCount: 2
                ),
                images: (0..<9).map { DatasetImage(artSeed: $0 + 2, symbol: "person.crop.rectangle") }
            ),
            DatasetEntry(
                name: "Close-ups — neutral light",
                caption: CaptionSettings.template(trigger: "m4y4")
                    .setting("Framing", to: ["close-up"])
                    .setting("Gaze", to: ["looking away"])
                    .setting("Expression", to: ["neutral expression"])
                    .setting("Lighting", to: ["soft window light"])
                    .setting("Hairstyle", to: ["ponytail"])
                    .setting("Background-Location", to: ["plain grey backdrop"]),
                generation: GenerationSettings(
                    prompt: "m4y4 close-up portrait, soft window light",
                    negativePrompt: "harsh shadows, oversharpened",
                    usesCustomSeed: true,
                    seed: 884_213
                ),
                images: [
                    DatasetImage(artSeed: 21, symbol: "face.smiling"),
                    DatasetImage(artSeed: 22, symbol: "face.smiling",
                                 captionOverride: CaptionSettings.template(trigger: "m4y4")),
                    DatasetImage(artSeed: 23, symbol: "face.smiling"),
                    DatasetImage(artSeed: 24, symbol: "face.smiling", isApproved: false),
                    DatasetImage(artSeed: 25, symbol: "face.smiling"),
                    DatasetImage(artSeed: 26, symbol: "face.smiling")
                ]
            ),
            DatasetEntry(
                name: "Full body — street",
                caption: CaptionSettings.template(trigger: "m4y4")
                    .setting("Framing", to: ["full shot"])
                    .setting("Camera Angle", to: ["low angle"])
                    .setting("Pose", to: ["walking"])
                    .setting("Clothing", to: ["denim jacket", "black jeans"])
                    .setting("Background-Location", to: ["city street at dusk"]),
                generation: GenerationSettings(
                    prompt: "m4y4 walking down a city street at dusk, low angle",
                    negativePrompt: "motion blur, distorted limbs",
                    referenceImageCount: 4,
                    usesCustomConfig: true
                ),
                images: (0..<12).map { DatasetImage(artSeed: $0 + 40, symbol: "figure.stand") }
            ),
            DatasetEntry(
                name: "Untitled entry",
                caption: CaptionSettings.template(),
                generation: GenerationSettings(),
                images: []
            )
        ])
    }
}

// MARK: - Preview

#Preview("Dataset grid") {
    DatasetGridView()
        .frame(width: 1180, height: 700)
}
