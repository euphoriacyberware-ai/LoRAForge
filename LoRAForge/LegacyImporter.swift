import Foundation
import CryptoKit
import TaggingCore

enum LegacyImporter {

    // MARK: - Legacy Data Model (decode-only)

    private struct LegacyProject: Decodable {
        let id: UUID
        let name: String
        let createdAt: Date
        let baseConfigurationJSON: String
        let sourceImages: [LegacySourceImage]
        let prompts: [LegacyPrompt]
    }

    private struct LegacySourceImage: Decodable {
        let id: UUID
        let filename: String
    }

    private struct LegacyPrompt: Decodable {
        let id: UUID
        let order: Int
        let text: String
        let sourceImageIDs: [UUID]
        let configurationOverrideJSON: String?
        let generatedImages: [LegacyGeneratedImage]
        let seedOverride: Int?
    }

    private struct LegacyGeneratedImage: Decodable {
        let id: UUID
        let filename: String
        let rank: LegacyImageRank
        let caption: String?
        let generatedAt: Date
        let seed: Int?
        let prompt: String?
    }

    private enum LegacyImageRank: String, Decodable {
        case candidate
        case shortlisted
        case final_
        case discarded
    }

    // MARK: - Result Types

    struct ImportResult {
        let name: String
        let success: Bool
        let error: String?
        let entryCount: Int
        let imageCount: Int
        let referenceCount: Int
    }

    struct BatchImportResult {
        let results: [ImportResult]

        var successCount: Int { results.filter(\.success).count }
        var failureCount: Int { results.filter { !$0.success }.count }
    }

    // MARK: - Discovery

    static func discoverLegacyBundles(at url: URL) -> [URL] {
        if url.pathExtension == "lforge" {
            return [url]
        }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.filter { $0.pathExtension == "lforge" }
    }

    // MARK: - Batch Import

    static func importLegacyProjects(
        at urls: [URL],
        libraryURL: URL,
        existingNames: Set<String>,
        categories: [TagCategory],
        tags: [Tag]
    ) -> BatchImportResult {
        var results: [ImportResult] = []
        var usedNames = existingNames
        for url in urls {
            let result = importLegacyProject(
                at: url,
                libraryURL: libraryURL,
                existingNames: usedNames,
                categories: categories,
                tags: tags
            )
            if result.success {
                usedNames.insert(result.name)
            }
            results.append(result)
        }
        return BatchImportResult(results: results)
    }

    // MARK: - Single Project Import

    static func importLegacyProject(
        at url: URL,
        libraryURL: URL,
        existingNames: Set<String>,
        categories: [TagCategory],
        tags: [Tag]
    ) -> ImportResult {
        let fm = FileManager.default

        // 1. Read and decode old project.json
        let projectFileURL = url.appendingPathComponent("project.json")
        guard fm.fileExists(atPath: projectFileURL.path) else {
            return ImportResult(name: url.lastPathComponent, success: false, error: "No project.json found", entryCount: 0, imageCount: 0, referenceCount: 0)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let legacyProject: LegacyProject
        do {
            let data = try Data(contentsOf: projectFileURL)
            legacyProject = try decoder.decode(LegacyProject.self, from: data)
        } catch {
            return ImportResult(name: url.lastPathComponent, success: false, error: "Failed to decode: \(error.localizedDescription)", entryCount: 0, imageCount: 0, referenceCount: 0)
        }

        // 2. Check duplicate name
        if existingNames.contains(legacyProject.name) {
            return ImportResult(name: legacyProject.name, success: false, error: "A project named '\(legacyProject.name)' already exists", entryCount: 0, imageCount: 0, referenceCount: 0)
        }

        // 3. Build source image ID map and ReferenceImageDocuments
        var sourceIDMap: [UUID: UUID] = [:]  // old ID → new ID
        var referenceImages: [ReferenceImageDocument] = []
        var refFileCopies: [(source: URL, dest: URL)] = []

        for source in legacyProject.sourceImages {
            let newID = UUID()
            sourceIDMap[source.id] = newID
            let ext = (source.filename as NSString).pathExtension
            let newFilename = "\(newID.uuidString).\(ext.isEmpty ? "png" : ext)"

            let sourceFileURL = url.appendingPathComponent("sources").appendingPathComponent(source.filename)
            let contentHash: String
            if let data = try? Data(contentsOf: sourceFileURL) {
                contentHash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            } else {
                contentHash = ""
            }

            let refDoc = ReferenceImageDocument(
                id: newID,
                filename: newFilename,
                contentHash: contentHash,
                addedAt: legacyProject.createdAt
            )
            referenceImages.append(refDoc)
            refFileCopies.append((source: sourceFileURL, dest: URL(filePath: newFilename)))
        }

        // 4. Map prompts → entries
        var entries: [EntryDocument] = []
        var imageFileCopies: [(source: URL, dest: URL)] = []
        var totalImageCount = 0

        let sortedPrompts = legacyProject.prompts.sorted { $0.order < $1.order }
        for (index, prompt) in sortedPrompts.enumerated() {
            let position = index + 1

            // Entry name: first 30 chars of prompt text
            let nameSource = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let entryName = nameSource.isEmpty
                ? "Entry \(position)"
                : String(nameSource.prefix(30))

            // Map source image IDs
            let mappedRefIDs = prompt.sourceImageIDs.compactMap { sourceIDMap[$0] }

            // Map generated images
            var images: [ImageDocument] = []
            var finalCaption: String?

            for genImage in prompt.generatedImages {
                let newImageID = UUID()
                let ext = (genImage.filename as NSString).pathExtension
                let newFilename = "\(newImageID.uuidString).\(ext.isEmpty ? "png" : ext)"

                let newRank: ImageRank
                switch genImage.rank {
                case .candidate: newRank = .candidate
                case .shortlisted: newRank = .shortlist
                case .final_: newRank = .final
                case .discarded: newRank = .discarded
                }

                let provenance = ImageProvenance(
                    prompt: genImage.prompt ?? prompt.text,
                    negativePrompt: "",
                    seed: Int64(genImage.seed ?? 0),
                    configJSON: prompt.configurationOverrideJSON ?? legacyProject.baseConfigurationJSON,
                    referenceImageIDs: mappedRefIDs.isEmpty ? nil : mappedRefIDs
                )

                let imageDoc = ImageDocument(
                    id: newImageID,
                    filename: newFilename,
                    rank: newRank,
                    addedAt: genImage.generatedAt,
                    provenance: provenance
                )
                images.append(imageDoc)

                // Track final image caption
                if newRank == .final, let caption = genImage.caption, !caption.isEmpty {
                    finalCaption = caption
                }

                // Determine source path: generated/ or trash/ based on rank
                let folder = genImage.rank == .discarded ? "trash" : "generated"
                let sourceFilePath = url
                    .appendingPathComponent(folder)
                    .appendingPathComponent(prompt.id.uuidString)
                    .appendingPathComponent(genImage.filename)
                imageFileCopies.append((source: sourceFilePath, dest: URL(filePath: newFilename)))
                totalImageCount += 1
            }

            // Build entry
            let captionMode: CaptionMode = (finalCaption != nil) ? .manual : .tagged
            let manualCaptionText = finalCaption ?? ""

            var entry = EntryDocument(name: entryName, position: position, defaultConfigJSON: prompt.configurationOverrideJSON ?? legacyProject.baseConfigurationJSON)
            // Override the auto-generated fields
            entry.images = images
            entry.captionMode = captionMode
            entry.manualCaptionText = manualCaptionText
            entry.generationPrompt = prompt.text
            entry.referenceImageIDs = mappedRefIDs

            if let seed = prompt.seedOverride {
                entry.generationSeed = Int64(seed)
                entry.useCustomSeed = true
            }

            entries.append(entry)
        }

        // 5. Build new ProjectDocument
        let categoryOrder = categories.sorted { $0.position < $1.position }.map(\.id)
        let categoryEnabled = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.isEnabled) })

        let newDoc = ProjectDocument(
            id: UUID(),
            name: legacyProject.name,
            createdAt: legacyProject.createdAt,
            categoryOrder: categoryOrder,
            categoryEnabled: categoryEnabled,
            entries: entries,
            referenceImages: referenceImages,
            defaultGenerationConfigJSON: legacyProject.baseConfigurationJSON
        )

        let schema = SchemaSnapshot(categories: categories, tags: tags)

        // 6. Create bundle
        let sanitized = sanitizeFilename(legacyProject.name)
        var bundleURL = libraryURL.appending(path: "\(sanitized).loraforge")
        var counter = 2
        while fm.fileExists(atPath: bundleURL.path) {
            bundleURL = libraryURL.appending(path: "\(sanitized) \(counter).loraforge")
            counter += 1
        }

        do {
            try ProjectBundle.create(at: bundleURL, project: newDoc, schema: schema)

            // Copy reference images
            for copy in refFileCopies {
                if fm.fileExists(atPath: copy.source.path) {
                    let destURL = bundleURL.appending(path: "references").appending(path: copy.dest.lastPathComponent)
                    try fm.copyItem(at: copy.source, to: destURL)
                }
            }

            // Copy generated images
            for copy in imageFileCopies {
                if fm.fileExists(atPath: copy.source.path) {
                    let destURL = bundleURL.appending(path: "images").appending(path: copy.dest.lastPathComponent)
                    try fm.copyItem(at: copy.source, to: destURL)
                }
            }
        } catch {
            // Clean up partial bundle on failure
            try? fm.removeItem(at: bundleURL)
            return ImportResult(name: legacyProject.name, success: false, error: "Failed to create project: \(error.localizedDescription)", entryCount: 0, imageCount: 0, referenceCount: 0)
        }

        return ImportResult(
            name: legacyProject.name,
            success: true,
            error: nil,
            entryCount: entries.count,
            imageCount: totalImageCount,
            referenceCount: referenceImages.count
        )
    }

    // MARK: - Helpers

    private static func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\")
        let cleaned = name.unicodeScalars.filter { !illegal.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned))
            .trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "Untitled" : result
    }
}
