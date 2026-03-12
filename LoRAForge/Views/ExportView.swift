import SwiftUI
import AppKit
import CoreImage

struct ExportView: View {
    @ObservedObject var document: LoRAForgeDocument
    @Binding var isPresented: Bool

    @State private var sourceFilter: SourceFilter = .finalsOnly
    @State private var resizeMode: ResizeMode = .none
    @State private var longestEdge: Int = 1024
    @State private var exactWidth: Int = 1024
    @State private var exactHeight: Int = 1024
    @State private var filenamePrefix: String = ""
    @State private var captionFallback: CaptionFallback = .usePromptText
    @State private var outputFolder: URL?
    @State private var isExporting = false
    @State private var exportMessage = ""

    enum SourceFilter: String, CaseIterable {
        case finalsOnly = "Finals Only"
        case shortlistedAndFinals = "Shortlisted + Finals"
        case allNonDiscarded = "All Non-Discarded"
    }

    enum ResizeMode: String, CaseIterable {
        case none = "None"
        case fitLongestEdge = "Fit Longest Edge"
        case exactSize = "Exact Size"
    }

    enum CaptionFallback: String, CaseIterable {
        case leaveEmpty = "Leave .txt Empty"
        case usePromptText = "Use Prompt Text"
        case skipFile = "Skip .txt File"
    }

    private var imageCount: Int {
        collectImages().count
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Export Images")
                .font(.headline)
                .padding()

            Divider()

            Form {
                // Source filter
                Picker("Source:", selection: $sourceFilter) {
                    ForEach(SourceFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }

                // Resize
                Picker("Resize:", selection: $resizeMode) {
                    ForEach(ResizeMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                if resizeMode == .fitLongestEdge {
                    HStack {
                        Text("Longest Edge:")
                        TextField("px", value: $longestEdge, format: .number)
                            .frame(width: 80)
                        Text("px")

                        Spacer()

                        // Presets
                        ForEach([512, 768, 1024], id: \.self) { size in
                            Button("\(size)") {
                                longestEdge = size
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                if resizeMode == .exactSize {
                    HStack {
                        Text("Size:")
                        TextField("W", value: $exactWidth, format: .number)
                            .frame(width: 60)
                        Text("×")
                        TextField("H", value: $exactHeight, format: .number)
                            .frame(width: 60)
                        Text("px")

                        Spacer()

                        ForEach([512, 768, 1024], id: \.self) { size in
                            Button("\(size)²") {
                                exactWidth = size
                                exactHeight = size
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                // Filename prefix
                TextField("Filename Prefix:", text: $filenamePrefix)

                // Caption fallback
                Picker("Caption Fallback:", selection: $captionFallback) {
                    ForEach(CaptionFallback.allCases, id: \.self) { fallback in
                        Text(fallback.rawValue).tag(fallback)
                    }
                }

                // Output folder
                HStack {
                    Text("Output Folder:")
                    Text(outputFolder?.lastPathComponent ?? "Not selected")
                        .foregroundStyle(outputFolder == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose…") {
                        chooseOutputFolder()
                    }
                }

                // Image count
                Text("\(imageCount) image(s) will be exported")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            if !exportMessage.isEmpty {
                Text(exportMessage)
                    .font(.caption)
                    .foregroundStyle(exportMessage.hasPrefix("Error") ? .red : .green)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Export") {
                    performExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(outputFolder == nil || imageCount == 0 || isExporting)
            }
            .padding()
        }
        .frame(width: 500, height: resizeMode == .none ? 380 : 420)
        .onAppear {
            filenamePrefix = document.project.name
        }
    }

    // MARK: - Collect Images

    private struct ExportItem {
        let image: GeneratedImage
        let promptID: UUID
        let promptText: String
    }

    private func collectImages() -> [ExportItem] {
        var items: [ExportItem] = []
        for prompt in document.project.prompts {
            for image in prompt.generatedImages {
                if shouldInclude(image) {
                    items.append(ExportItem(image: image, promptID: prompt.id, promptText: prompt.text))
                }
            }
        }
        return items
    }

    private func shouldInclude(_ image: GeneratedImage) -> Bool {
        switch sourceFilter {
        case .finalsOnly:
            return image.rank == .final_
        case .shortlistedAndFinals:
            return image.rank == .shortlisted || image.rank == .final_
        case .allNonDiscarded:
            return image.rank != .discarded
        }
    }

    // MARK: - Choose Output Folder

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose export destination"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputFolder = url
    }

    // MARK: - Export

    private func performExport() {
        guard let outputFolder else { return }
        isExporting = true
        exportMessage = ""

        let items = collectImages()
        let prefix = filenamePrefix.isEmpty ? "image" : filenamePrefix

        Task {
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)

                for (index, item) in items.enumerated() {
                    let number = String(format: "%03d", index + 1)
                    let pngFilename = "\(prefix)_\(number).png"
                    let txtFilename = "\(prefix)_\(number).txt"

                    // Load source image
                    guard let sourceURL = document.generatedImageURL(promptID: item.promptID, image: item.image),
                          let nsImage = NSImage(contentsOf: sourceURL) else {
                        continue
                    }

                    // Resize if needed
                    let exportImage = resizeImage(nsImage)

                    // Write PNG
                    guard let tiffData = exportImage.tiffRepresentation,
                          let bitmapRep = NSBitmapImageRep(data: tiffData),
                          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                        continue
                    }

                    try pngData.write(to: outputFolder.appendingPathComponent(pngFilename))

                    // Write caption
                    let caption = item.image.caption
                    switch captionFallback {
                    case .leaveEmpty:
                        let text = caption ?? ""
                        try text.write(to: outputFolder.appendingPathComponent(txtFilename), atomically: true, encoding: .utf8)
                    case .usePromptText:
                        let text = caption ?? item.promptText
                        try text.write(to: outputFolder.appendingPathComponent(txtFilename), atomically: true, encoding: .utf8)
                    case .skipFile:
                        if let caption {
                            try caption.write(to: outputFolder.appendingPathComponent(txtFilename), atomically: true, encoding: .utf8)
                        }
                    }
                }

                exportMessage = "Exported \(items.count) image(s)"
                isExporting = false
            } catch {
                exportMessage = "Error: \(error.localizedDescription)"
                isExporting = false
            }
        }
    }

    // MARK: - Resize

    private func resizeImage(_ image: NSImage) -> NSImage {
        switch resizeMode {
        case .none:
            return image
        case .fitLongestEdge:
            let size = image.pixelSize
            let longest = max(size.width, size.height)
            guard longest > CGFloat(longestEdge) else { return image }
            let scale = CGFloat(longestEdge) / longest
            let newW = size.width * scale
            let newH = size.height * scale
            return scaledImage(image, to: NSSize(width: newW, height: newH))
        case .exactSize:
            return scaledImage(image, to: NSSize(width: CGFloat(exactWidth), height: CGFloat(exactHeight)))
        }
    }

    private func scaledImage(_ image: NSImage, to targetSize: NSSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.pixelSize),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

// MARK: - NSImage Pixel Size (shared)

extension NSImage {
    var pixelSize: CGSize {
        guard let rep = representations.first else { return size }
        return CGSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
    }
}
