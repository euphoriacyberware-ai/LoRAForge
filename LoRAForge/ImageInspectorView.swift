import SwiftUI
import DrawThingsClient
import DTConfigBridge

struct ImageInspectorView: View {
    let image: ImageDocument
    let entry: EntryDocument
    let referenceImages: [ReferenceImageDocument]
    let bundleURL: URL
    var onCloneToEntry: (() -> Void)?
    var onAddToReferences: (() -> Void)?
    var onRecallSettings: (() -> Void)?
    var onExport: (() -> Void)?

    private var imageURL: URL {
        bundleURL.appending(path: "images/\(image.filename)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                if let provenance = image.provenance {
                    generationSection(provenance)
                    loraSection(provenance)
                    referenceSection(provenance)
                } else {
                    Text("No generation data")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
                fileActionSection
            }
            .padding()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.name)
                .font(.headline)
            HStack(spacing: 4) {
                if let icon = image.rank.badgeIcon {
                    Image(systemName: icon)
                        .foregroundStyle(image.rank == .final ? .yellow : .secondary)
                }
                Text(image.rank.label)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
    }

    // MARK: - Generation Settings

    private func generationSection(_ provenance: ImageProvenance) -> some View {
        let config = provenance.configJSON.flatMap {
            ConfigurationInterop.configuration(from: $0)
        }

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Generation settings")
            promptRow("Prompt", value: provenance.prompt)
            if !provenance.negativePrompt.isEmpty {
                promptRow("Negative", value: provenance.negativePrompt)
            }
            settingRow("Model", value: config?.model.truncatedFilename ?? dash)
            settingRow("Sampler", value: config.map { samplerDisplayName($0.sampler) } ?? dash)
            settingRow("Size", value: config.map { "\($0.width) \u{00D7} \($0.height)" } ?? dash)
            settingRow("Seed", value: "\(provenance.seed)")
            settingRow("Steps", value: config.map { "\($0.steps)" } ?? dash)
            settingRow("Guidance", value: config.map { String(format: "%.1f", $0.guidanceScale) } ?? dash)
            settingRow("Shift", value: config.map { String(format: "%.1f", $0.shift) } ?? dash)
        }
    }

    // MARK: - LoRAs

    private func loraSection(_ provenance: ImageProvenance) -> some View {
        let config = provenance.configJSON.flatMap {
            ConfigurationInterop.configuration(from: $0)
        }
        let loras = config?.loras ?? []

        return Group {
            if !loras.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("LoRAs")
                    ForEach(Array(loras.enumerated()), id: \.offset) { _, lora in
                        HStack {
                            Text(lora.file.truncatedFilename)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("[\(Int(lora.weight * 100))%]")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reference Images

    private func referenceSection(_ provenance: ImageProvenance) -> some View {
        let refIDs = provenance.referenceImageIDs ?? []

        return Group {
            if !refIDs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Reference images")
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 60), spacing: 6)
                    ], spacing: 6) {
                        ForEach(refIDs, id: \.self) { refID in
                            referenceThumbnail(refID)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func referenceThumbnail(_ refID: UUID) -> some View {
        if let ref = referenceImages.first(where: { $0.id == refID }) {
            let url = bundleURL.appending(path: "references/\(ref.filename)")
            #if os(macOS)
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                refPlaceholder
            }
            #else
            if let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                refPlaceholder
            }
            #endif
        } else {
            refPlaceholder
        }
    }

    private var refPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.gray.opacity(0.15))
            .frame(width: 60, height: 60)
            .overlay {
                Image(systemName: "questionmark")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
    }

    // MARK: - File Actions

    private var fileActionSection: some View {
        VStack {
            Divider()
            if let onRecallSettings {
                Button(action: onRecallSettings) {
                    Label("Recall settings", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if let onCloneToEntry {
                Button(action: onCloneToEntry) {
                    Label("Clone to new entry", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if let onAddToReferences {
                Button(action: onAddToReferences) {
                    Label("Add to references", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if let onExport {
                Button(action: onExport) {
                    Label("Export image", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
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
        }
    }

    // MARK: - Helpers

    private var dash: String { "\u{2014}" }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func promptRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private func settingRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private func samplerDisplayName(_ sampler: SamplerType) -> String {
        switch sampler {
        case .dpmpp2mkarras: return "DPM++ 2M Karras"
        case .eulera: return "Euler a"
        case .ddim: return "DDIM"
        case .plms: return "PLMS"
        case .dpmppsdekarras: return "DPM++ SDE Karras"
        case .unipc: return "UniPC"
        case .lcm: return "LCM"
        case .eulerasubstep: return "Euler a substep"
        case .dpmppsdesubstep: return "DPM++ SDE substep"
        case .tcd: return "TCD"
        case .euleratrailing: return "Euler a trailing"
        case .dpmppsdetrailing: return "DPM++ SDE trailing"
        case .dpmpp2mays: return "DPM++ 2M AYS"
        case .euleraays: return "Euler a AYS"
        case .dpmppsdeays: return "DPM++ SDE AYS"
        case .dpmpp2mtrailing: return "DPM++ 2M trailing"
        case .ddimtrailing: return "DDIM trailing"
        case .unipctrailing: return "UniPC trailing"
        case .unipcays: return "UniPC AYS"
        case .tcdtrailing: return "TCD trailing"
        @unknown default: return "Unknown"
        }
    }
}

private extension String {
    var truncatedFilename: String {
        let name = (self as NSString).lastPathComponent
        if name.count <= 28 { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        let keep = 24 - ext.count
        return stem.prefix(max(keep, 8)) + "..." + (ext.isEmpty ? "" : ".\(ext)")
    }
}
