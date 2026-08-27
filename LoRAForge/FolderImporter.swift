import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Ingests a folder of images from an existing dataset — one new entry per image, with a
/// sidecar `<stem>.txt` becoming that entry's manual caption.
///
/// Everything here is `nonisolated` and must be called from `Task.detached`. The project
/// builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` *and*
/// `SWIFT_APPROACHABLE_CONCURRENCY = YES`; under the latter a `nonisolated async` function
/// awaited from a main-actor context runs on the main actor, so `nonisolated` alone does
/// not get this work off the UI thread.
enum FolderImporter {

    // MARK: - Types

    struct Candidate: Sendable {
        let sourceURL: URL
        let stem: String
        let sidecarURL: URL?
    }

    struct ScanResult: Sendable {
        var candidates: [Candidate] = []
        /// Subfolders present but not descended into. Reported rather than swallowed —
        /// silent non-recursion is the likeliest source of confusion here.
        var subfoldersIgnored = 0
        /// `.txt` files with no matching image.
        var orphanSidecars = 0

        var captionCount: Int {
            candidates.filter { $0.sidecarURL != nil }.count
        }
    }

    struct ImportedItem: Sendable {
        let filename: String
        let stem: String
        let caption: String?
    }

    struct SkippedFile: Sendable {
        let name: String
        let reason: String
    }

    struct Summary: Sendable {
        var items: [ImportedItem] = []
        var skipped: [SkippedFile] = []
        var wasCancelled = false

        var captionCount: Int {
            items.filter { !($0.caption ?? "").isEmpty }.count
        }
    }

    // MARK: - Type support

    /// Image types ImageIO can actually rasterize. `conforms(to: .image)` alone is too
    /// broad — `public.svg-image` conforms to it but ImageIO will not decode it.
    private nonisolated static let readableTypes: [UTType] = {
        ((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []).compactMap(UTType.init)
    }()

    nonisolated static func isSupportedImageType(_ type: UTType?) -> Bool {
        guard let type, type.conforms(to: .image) else { return false }
        // Conformance rather than equality, so vendor RAW subtypes are included.
        return readableTypes.contains { type.conforms(to: $0) }
    }

    // MARK: - Scan

    /// Images directly inside `folder`, sorted naturally, each paired with its sidecar.
    ///
    /// `contentsOfDirectory` is shallow, which is what implements the top-level-only rule —
    /// there is no recursion to suppress. `.skipsHiddenFiles` drops `.DS_Store` and dotfiles.
    nonisolated static func scan(folder: URL) -> ScanResult {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .contentTypeKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return ScanResult() }

        var result = ScanResult()
        var imageURLs: [URL] = []
        var sidecars: [String: URL] = [:]

        for url in contents {
            let values = try? url.resourceValues(forKeys: keys)

            if values?.isDirectory == true {
                result.subfoldersIgnored += 1
                continue
            }
            guard values?.isRegularFile == true else { continue }

            if isSupportedImageType(values?.contentType) {
                imageURLs.append(url)
            } else if url.pathExtension.lowercased() == "txt" {
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                if sidecars[stem] == nil { sidecars[stem] = url }
            }
        }

        imageURLs.sort {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        var usedSidecars = Set<String>()
        result.candidates = imageURLs.map { url in
            let stem = url.deletingPathExtension().lastPathComponent
            let key = stem.lowercased()
            if sidecars[key] != nil { usedSidecars.insert(key) }
            return Candidate(sourceURL: url, stem: stem, sidecarURL: sidecars[key])
        }
        result.orphanSidecars = sidecars.count - usedSidecars.count

        return result
    }

    /// Reads a sidecar and normalizes it into caption text.
    ///
    /// `ExportManager` writes `caption + "\n"`, so a round-tripped file always carries a
    /// trailing newline that would otherwise end up inside the caption. Interior blank
    /// lines are preserved, so multi-line captions survive.
    nonisolated static func decodeCaption(_ data: Data) -> String? {
        var text = String(data: data, encoding: .utf8)
        if text == nil {
            var converted: NSString?
            let encoding = NSString.stringEncoding(
                for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil
            )
            if encoding != 0, let converted { text = converted as String }
        }
        guard var result = text else { return nil }

        // String(data:encoding:.utf8) succeeds on a BOM and hands back a leading U+FEFF,
        // which would silently prefix every caption with an invisible character.
        if result.hasPrefix("\u{FEFF}") { result.removeFirst() }

        return result
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func readSidecar(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decodeCaption(data)
    }

    // MARK: - Ingest

    /// Copies or transcodes every candidate into `imagesDir` as PNG.
    ///
    /// Must be called from `Task.detached` — see the type comment.
    ///
    /// On cancellation the files written so far are removed and nothing is imported. That
    /// cleanup matters: `LibraryManager.stripOrphanedImages` prunes records whose files are
    /// missing, never files whose records are missing, so abandoned images would linger in
    /// the bundle with nothing to ever collect them.
    nonisolated static func ingest(
        _ candidates: [Candidate],
        into imagesDir: URL,
        isCancelled: @Sendable () -> Bool = { Task.isCancelled },
        onProgress: @MainActor @Sendable (Int) -> Void = { _ in }
    ) async -> Summary {
        var summary = Summary()
        var written: [URL] = []

        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        for (index, candidate) in candidates.enumerated() {
            if isCancelled() {
                for url in written { try? FileManager.default.removeItem(at: url) }
                return Summary(items: [], skipped: summary.skipped, wasCancelled: true)
            }

            let filename = "\(UUID().uuidString).png"
            let destURL = imagesDir.appending(path: filename)

            if let reason = writePNG(from: candidate.sourceURL, to: destURL) {
                summary.skipped.append(
                    SkippedFile(name: candidate.sourceURL.lastPathComponent, reason: reason)
                )
            } else {
                written.append(destURL)
                summary.items.append(
                    ImportedItem(
                        filename: filename,
                        stem: candidate.stem,
                        caption: candidate.sidecarURL.flatMap { readSidecar(at: $0) }
                    )
                )
            }

            await onProgress(index + 1)
        }

        return summary
    }

    /// Writes `source` to `destination` as PNG. Returns a skip reason on failure, nil on success.
    nonisolated static func writePNG(from source: URL, to destination: URL) -> String? {
        // Not caching decoded bitmaps keeps memory flat across a large folder.
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let imageSource = CGImageSourceCreateWithURL(
            source as CFURL, sourceOptions as CFDictionary
        ) else {
            return "Could not be read as an image"
        }

        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 0 else { return "Contains no image data" }

        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let pixelWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let pixelHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0

        // A PNG that needs nothing done to it is copied byte-for-byte. All three guards
        // earn their place: the type comes from ImageIO's sniff rather than the extension
        // (a JPEG named .png is common in scraped datasets), a multi-frame file is an APNG
        // and must not reach a training set animated, and PNG 1.5's eXIf chunk means even a
        // PNG can carry an orientation that has to be baked in.
        if (CGImageSourceGetType(imageSource) as String?) == UTType.png.identifier,
           frameCount == 1, orientation == 1 {
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                return nil
            } catch {
                return "Could not be copied: \(error.localizedDescription)"
            }
        }

        let cgImage: CGImage
        if orientation != 1, pixelWidth > 0, pixelHeight > 0 {
            // Let ImageIO bake the transform. PNG has no orientation tag, so without this
            // a rotated JPEG lands sideways in the training set. Setting the max pixel size
            // to the source's longest edge means "full size, no downscale".
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight),
                kCGImageSourceShouldCache: false,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                imageSource, 0, options as CFDictionary
            ) else {
                return "Image could not be decoded"
            }
            cgImage = image
        } else {
            // Straight decode of frame 0, which preserves bit depth and colour space.
            // ImageIO handles CMYK to RGB itself, since PNG cannot store CMYK.
            let options: [CFString: Any] = [
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceShouldAllowFloat: true,
            ]
            guard let image = CGImageSourceCreateImageAtIndex(
                imageSource, 0, options as CFDictionary
            ) else {
                return "Image could not be decoded"
            }
            cgImage = image
        }

        guard let dest = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            return "Could not create the destination file"
        }

        // nil properties: no EXIF, no orientation, no GPS carried into the bundle.
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: destination)
            return "Could not be converted to PNG"
        }

        return nil
    }

    // MARK: - Entries

    /// Builds the entries to append. Pure, so the caption-mode rule is directly testable.
    ///
    /// An item with a sidecar becomes a manual-mode entry holding that text. An item
    /// without one keeps the default tagged mode, which leaves it taggable and — unlike an
    /// empty manual caption — inside audit scope (design §7).
    nonisolated static func makeEntries(
        from items: [ImportedItem],
        startPosition: Int,
        defaultConfigJSON: String
    ) -> [EntryDocument] {
        items.enumerated().map { index, item in
            let position = startPosition + index
            let trimmed = item.stem.trimmingCharacters(in: .whitespacesAndNewlines)

            var entry = EntryDocument(
                name: trimmed.isEmpty ? "Entry \(position)" : trimmed,
                position: position,
                defaultConfigJSON: defaultConfigJSON
            )
            entry.images = [ImageDocument(filename: item.filename, rank: .final)]

            if let caption = item.caption, !caption.isEmpty {
                entry.captionMode = .manual
                entry.manualCaptionText = caption
                entry.captionPreviewText = caption
            }
            return entry
        }
    }
}
