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

        DispatchQueue.main.sync {
            self.project = loadedProject
        }
    }

    // MARK: - Writing (URL-based, for package documents)

    nonisolated override func write(to url: URL, ofType typeName: String) throws {
        let fm = FileManager.default

        // Create the package directory if needed
        try fm.createDirectory(at: url, withIntermediateDirectories: true)

        // Ensure subdirectories exist
        for subdir in ["sources", "generated", "trash"] {
            let dirURL = url.appendingPathComponent(subdir)
            if !fm.fileExists(atPath: dirURL.path) {
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
        }

        var projectToSave: Project!
        DispatchQueue.main.sync {
            self.project.modifiedAt = Date()
            projectToSave = self.project
        }

        // Write project.json
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(projectToSave)
        try data.write(to: url.appendingPathComponent("project.json"), options: .atomic)
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
