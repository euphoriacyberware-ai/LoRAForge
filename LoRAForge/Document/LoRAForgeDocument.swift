import AppKit
import SwiftUI
import Combine

final class LoRAForgeDocument: NSDocument, ObservableObject {

    @Published var project: Project

    // MARK: - Initialisation

    override init() {
        let now = Date()
        self.project = Project(
            id: UUID(),
            name: "Untitled",
            createdAt: now,
            modifiedAt: now,
            generationConnectionID: nil,
            captionConnectionID: nil,
            baseConfigurationJSON: "{}",
            sourceImages: [],
            prompts: []
        )
        super.init()
    }

    // MARK: - Document Type

    nonisolated override class var autosavesInPlace: Bool { true }

    override func defaultDraftName() -> String { "LoRAForge Project" }

    // MARK: - Reading (URL-based, for package documents)

    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        let projectFileURL = url.appendingPathComponent("project.json")

        guard FileManager.default.fileExists(atPath: projectFileURL.path) else {
            throw CocoaError(.fileReadNoSuchFile,
                             userInfo: [NSURLErrorKey: projectFileURL])
        }

        let data = try Data(contentsOf: projectFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loadedProject = try decoder.decode(Project.self, from: data)

        if Thread.isMainThread {
            self.project = loadedProject
        } else {
            DispatchQueue.main.sync {
                self.project = loadedProject
            }
        }
    }

    // MARK: - Writing (URL-based, for package documents)

    nonisolated override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, originalContentsURL: URL?) throws {
        let fm = FileManager.default

        // If saving to a new location and we have original content, copy the package first
        if let originalURL = originalContentsURL,
           originalURL.standardizedFileURL != url.standardizedFileURL,
           fm.fileExists(atPath: originalURL.path) {
            // Copy subdirectories with their content from original to destination
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
            for subdir in ["sources", "generated", "trash"] {
                let srcDir = originalURL.appendingPathComponent(subdir)
                let dstDir = url.appendingPathComponent(subdir)
                if fm.fileExists(atPath: srcDir.path) && !fm.fileExists(atPath: dstDir.path) {
                    try fm.copyItem(at: srcDir, to: dstDir)
                }
            }
        }

        // Create the package directory if needed
        try fm.createDirectory(at: url, withIntermediateDirectories: true)

        // Ensure subdirectories exist
        for subdir in ["sources", "generated", "trash"] {
            let dirURL = url.appendingPathComponent(subdir)
            if !fm.fileExists(atPath: dirURL.path) {
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
        }

        let projectToSave: Project
        if Thread.isMainThread {
            self.project.modifiedAt = Date()
            projectToSave = self.project
        } else {
            projectToSave = DispatchQueue.main.sync {
                self.project.modifiedAt = Date()
                return self.project
            }
        }

        // Write project.json
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(projectToSave)
        try data.write(to: url.appendingPathComponent("project.json"), options: .atomic)
    }

    // MARK: - Save with Completion

    func ensureSaved(then completion: @escaping () -> Void) {
        if fileURL != nil {
            completion()
            return
        }
        let helper = SaveCompletionHelper(completion: completion)
        // Keep a strong reference until the callback fires
        objc_setAssociatedObject(self, "saveHelper", helper, .OBJC_ASSOCIATION_RETAIN)
        save(withDelegate: helper,
             didSave: #selector(SaveCompletionHelper.document(_:didSave:contextInfo:)),
             contextInfo: nil)
    }

    // MARK: - Source Image Management

    func importSourceImages(from urls: [URL]) {
        guard let packageURL = fileURL else { return }
        let fm = FileManager.default
        let sourcesDir = packageURL.appendingPathComponent("sources")
        try? fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        for url in urls {
            let id = UUID()
            let ext = url.pathExtension.lowercased()
            let filename = "\(id.uuidString).\(ext.isEmpty ? "png" : ext)"
            let destURL = sourcesDir.appendingPathComponent(filename)
            do {
                try fm.copyItem(at: url, to: destURL)
                let source = SourceImage(
                    id: id,
                    filename: filename,
                    label: url.deletingPathExtension().lastPathComponent
                )
                project.sourceImages.append(source)
            } catch {
                Swift.print("Failed to import \(url.lastPathComponent): \(error)")
            }
        }
        updateChangeCount(.changeDone)
    }

    func removeSourceImage(id: UUID) {
        guard let packageURL = fileURL else { return }
        guard let index = project.sourceImages.firstIndex(where: { $0.id == id }) else { return }

        let source = project.sourceImages[index]
        let fileURL = packageURL.appendingPathComponent("sources").appendingPathComponent(source.filename)
        try? FileManager.default.removeItem(at: fileURL)

        project.sourceImages.remove(at: index)
        updateChangeCount(.changeDone)
    }

    func sourceImageURL(for source: SourceImage) -> URL? {
        fileURL?.appendingPathComponent("sources").appendingPathComponent(source.filename)
    }

    func isSourceImageReferenced(_ id: UUID) -> Bool {
        project.prompts.contains { $0.sourceImageIDs.contains(id) }
    }

    // MARK: - Generated Image Management

    func generatedImageURL(promptID: UUID, image: GeneratedImage) -> URL? {
        guard let packageURL = fileURL else { return nil }
        let folder = image.rank == .discarded ? "trash" : "generated"
        return packageURL
            .appendingPathComponent(folder)
            .appendingPathComponent(promptID.uuidString)
            .appendingPathComponent(image.filename)
    }

    func promoteImage(promptIndex: Int, imageIndex: Int) {
        let current = project.prompts[promptIndex].generatedImages[imageIndex].rank
        let next: ImageRank? = switch current {
        case .candidate: .shortlisted
        case .shortlisted: .final_
        case .final_: nil
        case .discarded: nil
        }
        guard let next else { return }
        project.prompts[promptIndex].generatedImages[imageIndex].rank = next
        updateChangeCount(.changeDone)
    }

    func demoteImage(promptIndex: Int, imageIndex: Int) {
        let current = project.prompts[promptIndex].generatedImages[imageIndex].rank
        let next: ImageRank? = switch current {
        case .candidate: nil
        case .shortlisted: .candidate
        case .final_: .shortlisted
        case .discarded: nil
        }
        guard let next else { return }
        project.prompts[promptIndex].generatedImages[imageIndex].rank = next
        updateChangeCount(.changeDone)
    }

    func discardImage(promptIndex: Int, imageIndex: Int) {
        guard let packageURL = fileURL else { return }
        let promptID = project.prompts[promptIndex].id
        let image = project.prompts[promptIndex].generatedImages[imageIndex]
        guard image.rank != .discarded else { return }

        let srcDir = packageURL.appendingPathComponent("generated").appendingPathComponent(promptID.uuidString)
        let dstDir = packageURL.appendingPathComponent("trash").appendingPathComponent(promptID.uuidString)
        let fm = FileManager.default
        try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true)

        let src = srcDir.appendingPathComponent(image.filename)
        let dst = dstDir.appendingPathComponent(image.filename)
        try? fm.moveItem(at: src, to: dst)

        project.prompts[promptIndex].generatedImages[imageIndex].rank = .discarded
        updateChangeCount(.changeDone)
    }

    func restoreImage(promptIndex: Int, imageIndex: Int) {
        guard let packageURL = fileURL else { return }
        let promptID = project.prompts[promptIndex].id
        let image = project.prompts[promptIndex].generatedImages[imageIndex]
        guard image.rank == .discarded else { return }

        let srcDir = packageURL.appendingPathComponent("trash").appendingPathComponent(promptID.uuidString)
        let dstDir = packageURL.appendingPathComponent("generated").appendingPathComponent(promptID.uuidString)
        let fm = FileManager.default
        try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true)

        let src = srcDir.appendingPathComponent(image.filename)
        let dst = dstDir.appendingPathComponent(image.filename)
        try? fm.moveItem(at: src, to: dst)

        project.prompts[promptIndex].generatedImages[imageIndex].rank = .candidate
        updateChangeCount(.changeDone)
    }

    func deleteImagePermanently(promptIndex: Int, imageIndex: Int) {
        guard let packageURL = fileURL else { return }
        let promptID = project.prompts[promptIndex].id
        let image = project.prompts[promptIndex].generatedImages[imageIndex]

        let trashDir = packageURL.appendingPathComponent("trash").appendingPathComponent(promptID.uuidString)
        let fileURL = trashDir.appendingPathComponent(image.filename)
        try? FileManager.default.removeItem(at: fileURL)

        project.prompts[promptIndex].generatedImages.remove(at: imageIndex)
        updateChangeCount(.changeDone)
    }

    // MARK: - Prompt Deletion (with Undo)

    func trashPrompt(id: UUID) {
        guard let index = project.prompts.firstIndex(where: { $0.id == id }) else { return }
        let prompt = project.prompts[index]

        // Move all non-discarded images to trash on disk
        movePromptImagesToTrash(prompt)

        // Remove from model
        project.prompts.remove(at: index)

        // Register undo
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.restorePrompt(prompt, at: index)
        }
        undoManager?.setActionName("Delete Prompt")
        updateChangeCount(.changeDone)
    }

    func trashPrompts(ids: Set<UUID>) {
        // Collect prompts to remove, preserving order for undo
        var removed: [(index: Int, prompt: Prompt)] = []
        for (index, prompt) in project.prompts.enumerated() where ids.contains(prompt.id) {
            movePromptImagesToTrash(prompt)
            removed.append((index, prompt))
        }
        guard !removed.isEmpty else { return }

        project.prompts.removeAll { ids.contains($0.id) }

        undoManager?.registerUndo(withTarget: self) { doc in
            doc.restorePrompts(removed)
        }
        undoManager?.setActionName("Delete \(removed.count) Prompt(s)")
        updateChangeCount(.changeDone)
    }

    private func restorePrompt(_ prompt: Prompt, at index: Int) {
        // Move images back from trash to generated
        movePromptImagesFromTrash(prompt)

        // Re-insert at original position (clamped to valid range)
        let insertIndex = min(index, project.prompts.count)
        project.prompts.insert(prompt, at: insertIndex)

        undoManager?.registerUndo(withTarget: self) { doc in
            doc.trashPrompt(id: prompt.id)
        }
        undoManager?.setActionName("Delete Prompt")
        updateChangeCount(.changeDone)
    }

    private func restorePrompts(_ removed: [(index: Int, prompt: Prompt)]) {
        var ids = Set<UUID>()
        // Restore in reverse order so indices remain valid
        for (index, prompt) in removed.reversed() {
            movePromptImagesFromTrash(prompt)
            let insertIndex = min(index, project.prompts.count)
            project.prompts.insert(prompt, at: insertIndex)
            ids.insert(prompt.id)
        }

        undoManager?.registerUndo(withTarget: self) { doc in
            doc.trashPrompts(ids: ids)
        }
        undoManager?.setActionName("Delete \(removed.count) Prompt(s)")
        updateChangeCount(.changeDone)
    }

    private func movePromptImagesToTrash(_ prompt: Prompt) {
        guard let packageURL = fileURL else { return }
        let fm = FileManager.default
        let srcDir = packageURL.appendingPathComponent("generated").appendingPathComponent(prompt.id.uuidString)
        let dstDir = packageURL.appendingPathComponent("trash").appendingPathComponent(prompt.id.uuidString)

        for image in prompt.generatedImages where image.rank != .discarded {
            try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
            let src = srcDir.appendingPathComponent(image.filename)
            let dst = dstDir.appendingPathComponent(image.filename)
            try? fm.moveItem(at: src, to: dst)
        }

        // Clean up empty generated directory
        try? fm.removeItem(at: srcDir)
    }

    private func movePromptImagesFromTrash(_ prompt: Prompt) {
        guard let packageURL = fileURL else { return }
        let fm = FileManager.default
        let srcDir = packageURL.appendingPathComponent("trash").appendingPathComponent(prompt.id.uuidString)
        let dstDir = packageURL.appendingPathComponent("generated").appendingPathComponent(prompt.id.uuidString)

        for image in prompt.generatedImages where image.rank != .discarded {
            try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
            let src = srcDir.appendingPathComponent(image.filename)
            let dst = dstDir.appendingPathComponent(image.filename)
            try? fm.moveItem(at: src, to: dst)
        }

        // Clean up empty trash subdirectory
        if let contents = try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil), contents.isEmpty {
            try? fm.removeItem(at: srcDir)
        }
    }

    // MARK: - Empty Trash

    func emptyTrash() {
        guard let packageURL = fileURL else { return }
        let fm = FileManager.default
        let trashDir = packageURL.appendingPathComponent("trash")

        // Remove all discarded images from the model
        for pIdx in project.prompts.indices {
            project.prompts[pIdx].generatedImages.removeAll { $0.rank == .discarded }
        }

        // Delete the entire trash directory contents
        if let contents = try? fm.contentsOfDirectory(at: trashDir, includingPropertiesForKeys: nil) {
            for item in contents {
                try? fm.removeItem(at: item)
            }
        }

        updateChangeCount(.changeDone)
    }

    // MARK: - Package document support

    nonisolated override class func isNativeType(_ type: String) -> Bool {
        type == "com.euphoria-ai.lforge"
    }

    nonisolated override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        ["com.euphoria-ai.lforge"]
    }

    nonisolated override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        // We use URL-based reading for package documents
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    // MARK: - Window Controller

    override func makeWindowControllers() {
        let contentView = ContentView(document: self)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 900, height: 600))
        window.title = displayName
        let wc = NSWindowController(window: window)
        wc.shouldCascadeWindows = true
        addWindowController(wc)
    }
}
