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

        // 2. Derive name: prefer filename over stored name when stored name is generic
        let filenameBase = url.deletingPathExtension().lastPathComponent
        let projectName = (legacyProject.name == "Untitled" || legacyProject.name.isEmpty)
            ? filenameBase
            : legacyProject.name

        // 3. Check duplicate name
        if existingNames.contains(projectName) {
            return ImportResult(name: projectName, success: false, error: "A project named '\(projectName)' already exists", entryCount: 0, imageCount: 0, referenceCount: 0)
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
            entry.captionPreviewText = manualCaptionText
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
            name: projectName,
            createdAt: legacyProject.createdAt,
            categoryOrder: categoryOrder,
            categoryEnabled: categoryEnabled,
            entries: entries,
            referenceImages: referenceImages,
            defaultGenerationConfigJSON: legacyProject.baseConfigurationJSON
        )

        let schema = SchemaSnapshot(categories: categories, tags: tags)

        // 6. Create bundle
        let sanitized = sanitizeFilename(projectName)
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
            return ImportResult(name: projectName, success: false, error: "Failed to create project: \(error.localizedDescription)", entryCount: 0, imageCount: 0, referenceCount: 0)
        }

        return ImportResult(
            name: projectName,
            success: true,
            error: nil,
            entryCount: entries.count,
            imageCount: totalImageCount,
            referenceCount: referenceImages.count
        )
    }

    // MARK: - .loraforge Discovery

    static func discoverLoRAForgeBundles(at url: URL) -> [URL] {
        if url.pathExtension == "loraforge" {
            return [url]
        }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.filter { $0.pathExtension == "loraforge" }
    }

    // MARK: - .loraforge Import

    static func importLoRAForgeProject(
        at url: URL,
        libraryURL: URL,
        existingNames: Set<String>,
        repo: TagRepository
    ) -> ImportResult {
        let fm = FileManager.default
        let bundle = ProjectBundle(url: url)

        // 1. Read schema.json
        let schema: SchemaSnapshot
        do {
            schema = try bundle.readSchema()
        } catch {
            return ImportResult(name: url.deletingPathExtension().lastPathComponent, success: false,
                                error: "Failed to read schema.json: \(error.localizedDescription)",
                                entryCount: 0, imageCount: 0, referenceCount: 0)
        }

        // 2. Read project.json
        var project: ProjectDocument
        do {
            project = try bundle.readProject()
        } catch {
            return ImportResult(name: url.deletingPathExtension().lastPathComponent, success: false,
                                error: "Failed to read project.json: \(error.localizedDescription)",
                                entryCount: 0, imageCount: 0, referenceCount: 0)
        }

        // 3. Check duplicate name
        let projectName = project.name
        if existingNames.contains(projectName) {
            return ImportResult(name: projectName, success: false,
                                error: "A project named '\(projectName)' already exists",
                                entryCount: 0, imageCount: 0, referenceCount: 0)
        }

        // 4. Reconcile categories
        var categoryRemap: [UUID: UUID] = [:]  // source UUID → local UUID
        do {
            for cat in schema.categories {
                // Already exists by UUID?
                if try repo.category(id: cat.id) != nil {
                    continue
                }
                // Exists by name?
                if let local = try repo.category(name: cat.name) {
                    categoryRemap[cat.id] = local.id
                    continue
                }
                // Insert with original UUID
                let maxPosition = (try repo.allCategories().map(\.position).max() ?? -1) + 1
                let newCat = TagCategory(
                    id: cat.id,
                    name: cat.name,
                    selectMode: TagCategory.SelectMode(rawValue: cat.selectMode) ?? .single,
                    prefix: cat.prefix,
                    position: maxPosition,
                    isEnabled: true,
                    highThreshold: cat.highThreshold,
                    lowThreshold: cat.lowThreshold,
                    isBuiltIn: false
                )
                try repo.insertCategory(newCat)
            }
        } catch {
            return ImportResult(name: projectName, success: false,
                                error: "Failed to reconcile categories: \(error.localizedDescription)",
                                entryCount: 0, imageCount: 0, referenceCount: 0)
        }

        // 5. Reconcile tags
        var tagRemap: [UUID: UUID] = [:]  // source UUID → local UUID
        do {
            for tag in schema.tags {
                let resolvedCategoryID = categoryRemap[tag.categoryID] ?? tag.categoryID

                // Already exists by UUID?
                let tagID = tag.id
                let existingByID = try repo.allTags().first { $0.id == tagID }
                if existingByID != nil {
                    continue
                }
                // Exists by normalized string in resolved category?
                let normalized = DuplicateDetector.normalize(tag.canonicalString)
                if let local = try repo.tag(normalizedString: normalized, inCategoryID: resolvedCategoryID) {
                    tagRemap[tag.id] = local.id
                    continue
                }
                // Insert with original UUID
                _ = try repo.insertTag(id: tag.id, canonicalString: tag.canonicalString, categoryID: resolvedCategoryID)
            }
        } catch {
            return ImportResult(name: projectName, success: false,
                                error: "Failed to reconcile tags: \(error.localizedDescription)",
                                entryCount: 0, imageCount: 0, referenceCount: 0)
        }

        // 6. Apply remaps to project document (only if any occurred)
        let hasRemaps = !categoryRemap.isEmpty || !tagRemap.isEmpty
        if hasRemaps {
            // Remap categoryOrder
            project.categoryOrder = project.categoryOrder.map { categoryRemap[$0] ?? $0 }

            // Remap categoryEnabled
            var newEnabled: [UUID: Bool] = [:]
            for (key, value) in project.categoryEnabled {
                newEnabled[categoryRemap[key] ?? key] = value
            }
            project.categoryEnabled = newEnabled

            // Remap entry assignments
            for i in project.entries.indices {
                project.entries[i].assignments = project.entries[i].assignments.map { assignment in
                    AssignmentDocument(
                        tagID: tagRemap[assignment.tagID] ?? assignment.tagID,
                        selectionOrder: assignment.selectionOrder
                    )
                }
            }
        }

        // 7. Copy the bundle into the library
        let sanitized = sanitizeFilename(projectName)
        var destURL = libraryURL.appending(path: "\(sanitized).loraforge")
        var counter = 2
        while fm.fileExists(atPath: destURL.path) {
            destURL = libraryURL.appending(path: "\(sanitized) \(counter).loraforge")
            counter += 1
        }

        do {
            try fm.copyItem(at: url, to: destURL)

            // Write remapped project.json and updated schema into the copy
            let destBundle = ProjectBundle(url: destURL)
            try destBundle.writeProjectAtomic(project)

            let allCategories = try repo.allCategories()
            let allTags = try repo.allTags()
            let updatedSchema = SchemaSnapshot(categories: allCategories, tags: allTags)
            try destBundle.writeSchemaAtomic(updatedSchema)
        } catch {
            try? fm.removeItem(at: destURL)
            return ImportResult(name: projectName, success: false,
                                error: "Failed to copy project: \(error.localizedDescription)",
                                entryCount: 0, imageCount: 0, referenceCount: 0)
        }

        return ImportResult(
            name: projectName,
            success: true,
            error: nil,
            entryCount: project.entries.count,
            imageCount: project.entries.reduce(0) { $0 + $1.images.count },
            referenceCount: project.referenceImages.count
        )
    }

    static func importLoRAForgeProjects(
        at urls: [URL],
        libraryURL: URL,
        existingNames: Set<String>,
        repo: TagRepository
    ) -> BatchImportResult {
        var results: [ImportResult] = []
        var usedNames = existingNames
        for url in urls {
            let result = importLoRAForgeProject(
                at: url,
                libraryURL: libraryURL,
                existingNames: usedNames,
                repo: repo
            )
            if result.success {
                usedNames.insert(result.name)
            }
            results.append(result)
        }
        return BatchImportResult(results: results)
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

#if os(macOS)
import AppKit

final class ImportPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    static let shared = ImportPanelDelegate()

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        let ext = url.pathExtension
        if ext == "lforge" || ext == "loraforge" { return true }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }
}
#endif
