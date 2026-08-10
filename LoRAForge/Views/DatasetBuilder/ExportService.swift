import Foundation
import SwiftData
import TaggingCore

enum ExportScope: String, CaseIterable, Sendable {
    case finalsOnly = "Finals only"
    case finalsAndShortlist = "Finals and shortlist"
    case allImages = "All images"
}

struct ExportReport: Sendable {
    let exported: Int
    let skipped: Int
    let skippedNoFinal: Int
    let totalImages: Int
    let totalSidecars: Int
}

struct ExportService {
    let document: LoRAForgeDocument
    let modelContext: ModelContext

    /// Export the project to the given directory.
    func export(
        to directory: URL,
        baseName: String,
        scope: ExportScope,
        clearFirst: Bool
    ) throws -> ExportReport {
        let fm = FileManager.default

        if clearFirst {
            // Remove existing files matching the base name pattern
            if let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let sanitized = sanitizeBaseName(baseName)
                for url in contents where url.lastPathComponent.hasPrefix(sanitized + "_") {
                    try? fm.removeItem(at: url)
                }
            }
        }

        let sanitized = sanitizeBaseName(baseName)
        let digits = document.entries.count > 999 ? 4 : 3
        var exportedEntries = 0
        var skippedNoFinal = 0
        var totalImages = 0
        var totalSidecars = 0

        for (index, entry) in document.entries.enumerated() {
            let position = String(format: "%0\(digits)d", index + 1)

            guard let finalImage = entry.finalImage else {
                skippedNoFinal += 1
                continue
            }

            // Export the final image
            let finalBasename = "\(sanitized)_\(position)"
            let finalExt = fileExtension(for: finalImage.filename)
            let finalURL = directory.appendingPathComponent("\(finalBasename).\(finalExt)")

            if let data = document.imageData(for: finalImage.filename) {
                try data.write(to: finalURL)
                totalImages += 1
            }

            // Export the caption sidecar
            let captionText = captionForExport(entry: entry)
            let sidecarURL = directory.appendingPathComponent("\(finalBasename).txt")
            let sidecarContent = captionText + (captionText.isEmpty ? "" : "\n")
            try sidecarContent.write(to: sidecarURL, atomically: true, encoding: .utf8)
            totalSidecars += 1

            // Export additional images if scope includes them
            if scope != .finalsOnly {
                let additional = additionalImages(for: entry, scope: scope)
                for (suffix, image) in additional.enumerated() {
                    let addBasename = "\(finalBasename)-\(suffix + 1)"
                    let addExt = fileExtension(for: image.filename)
                    let addURL = directory.appendingPathComponent("\(addBasename).\(addExt)")
                    if let data = document.imageData(for: image.filename) {
                        try data.write(to: addURL)
                        totalImages += 1
                    }
                }
            }

            exportedEntries += 1
        }

        return ExportReport(
            exported: exportedEntries,
            skipped: skippedNoFinal,
            skippedNoFinal: skippedNoFinal,
            totalImages: totalImages,
            totalSidecars: totalSidecars
        )
    }

    // MARK: - Helpers

    /// Caption text for export: locked entries use stored text, unlocked tagged-mode render fresh.
    private func captionForExport(entry: DatasetEntry) -> String {
        if entry.isLocked, let locked = entry.lockedText {
            return locked
        }

        if entry.captionMode == .tagged {
            // Render fresh from current tags
            let catRepo = SwiftDataCategoryRepository(modelContext: modelContext)
            let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
            let allCats = (try? catRepo.allCategories()) ?? []
            let allTags = (try? tagRepo.allTags()) ?? []

            var ordered: [TagCategory] = []
            for id in document.metadata.categoryOrder {
                if var cat = allCats.first(where: { $0.id == id }) {
                    if document.metadata.disabledCategories.contains(id) { cat.isEnabled = false }
                    ordered.append(cat)
                }
            }
            for cat in allCats where !document.metadata.categoryOrder.contains(cat.id) {
                ordered.append(cat)
            }

            let assignments = entry.tagAssignments.map {
                TagAssignment(tagID: $0.tagID, selectionOrder: $0.selectionOrder)
            }
            return CaptionRenderer.render(assignments: assignments, tags: allTags, categories: ordered)
        }

        return entry.captionText
    }

    /// Additional images beyond the final, ordered deterministically: shortlist then candidates.
    private func additionalImages(for entry: DatasetEntry, scope: ExportScope) -> [EntryImage] {
        var result: [EntryImage] = []

        // Shortlist first (stable order by image ID)
        let shortlisted = entry.images
            .filter { $0.rank == .shortlist }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        result.append(contentsOf: shortlisted)

        // Then candidates if scope includes all
        if scope == .allImages {
            let candidates = entry.images
                .filter { $0.rank == .candidate }
                .sorted { $0.id.uuidString < $1.id.uuidString }
            result.append(contentsOf: candidates)
        }

        return result
    }

    private func sanitizeBaseName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(name.unicodeScalars.filter { allowed.contains($0) })
    }

    private func fileExtension(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ext.isEmpty ? "png" : ext
    }
}
