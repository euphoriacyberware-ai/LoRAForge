import Foundation
import TaggingCore

enum ExportScope: String, Codable, CaseIterable {
    case finalsOnly
    case finalsAndShortlist
    case allImages

    var label: String {
        switch self {
        case .finalsOnly: return "Finals only"
        case .finalsAndShortlist: return "Finals and shortlist"
        case .allImages: return "All images"
        }
    }
}

struct ExportResult {
    let exportedEntries: Int
    let skippedEntries: Int
    let exportedImages: Int
    let exportedCaptions: Int
}

enum ExportManager {

    static func export(
        document: ProjectDocument,
        bundleURL: URL,
        to destination: URL,
        baseName: String,
        scope: ExportScope,
        categories: [TagCategory],
        allTags: [UUID: Tag]
    ) throws -> ExportResult {
        let fm = FileManager.default
        let sanitized = sanitizeBaseName(baseName)
        var exportedEntries = 0
        var skippedEntries = 0
        var exportedImages = 0
        var exportedCaptions = 0

        for entry in document.entries {
            guard let finalImg = entry.finalImage else {
                skippedEntries += 1
                continue
            }

            let posStr = positionString(entry.position)
            exportedEntries += 1

            // Export the final image
            let finalSrc = bundleURL.appending(path: "images/\(finalImg.filename)")
            let ext = fileExtension(finalImg.filename)
            let finalDest = destination.appending(path: "\(sanitized)_\(posStr).\(ext)")
            try? fm.copyItem(at: finalSrc, to: finalDest)
            exportedImages += 1

            // Export the caption sidecar
            let captionText = captionForExport(entry: entry, categories: categories, allTags: allTags)
            let sidecarDest = destination.appending(path: "\(sanitized)_\(posStr).txt")
            let sidecarData = Data((captionText + "\n").utf8)
            try sidecarData.write(to: sidecarDest)
            exportedCaptions += 1

            // Export additional images based on scope
            if scope != .finalsOnly {
                let additional = additionalImages(for: entry, scope: scope)
                for (index, img) in additional.enumerated() {
                    let imgSrc = bundleURL.appending(path: "images/\(img.filename)")
                    let imgExt = fileExtension(img.filename)
                    let imgDest = destination.appending(
                        path: "\(sanitized)_\(posStr)-\(index + 1).\(imgExt)"
                    )
                    try? fm.copyItem(at: imgSrc, to: imgDest)
                    exportedImages += 1
                }
            }
        }

        return ExportResult(
            exportedEntries: exportedEntries,
            skippedEntries: skippedEntries,
            exportedImages: exportedImages,
            exportedCaptions: exportedCaptions
        )
    }

    static func captionForExport(
        entry: EntryDocument,
        categories: [TagCategory],
        allTags: [UUID: Tag]
    ) -> String {
        if let locked = entry.lockedCaptionText {
            return locked
        }
        switch entry.captionMode {
        case .tagged:
            let assignments = entry.assignments.map {
                TagAssignment(tagID: $0.tagID, selectionOrder: $0.selectionOrder)
            }
            return CaptionRenderer.render(
                assignments: assignments, tags: allTags, categories: categories
            )
        case .manual, .ollama:
            return entry.manualCaptionText
        }
    }

    static func sanitizeBaseName(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>| ")
        let cleaned = name.unicodeScalars.filter { !illegal.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned))
            .trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "export" : result
    }

    static func clearExistingExport(at directory: URL, baseName: String) throws {
        let fm = FileManager.default
        let sanitized = sanitizeBaseName(baseName)
        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for url in contents where url.lastPathComponent.hasPrefix(sanitized + "_") {
            try fm.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    private static func positionString(_ position: Int) -> String {
        if position > 999 {
            return String(format: "%04d", position)
        }
        return String(format: "%03d", position)
    }

    private static func fileExtension(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension
        return ext.isEmpty ? "png" : ext
    }

    private static func additionalImages(for entry: EntryDocument, scope: ExportScope) -> [ImageDocument] {
        var result: [ImageDocument] = []
        let finalID = entry.finalImage?.id

        // Shortlist first (sorted by addedAt), then candidates
        if scope == .finalsAndShortlist || scope == .allImages {
            let shortlist = entry.images
                .filter { $0.rank == .shortlist && $0.id != finalID }
                .sorted { $0.addedAt < $1.addedAt }
            result.append(contentsOf: shortlist)
        }

        if scope == .allImages {
            let candidates = entry.images
                .filter { $0.rank == .candidate && $0.id != finalID }
                .sorted { $0.addedAt < $1.addedAt }
            result.append(contentsOf: candidates)
        }

        // Discarded never exported
        return result
    }
}
