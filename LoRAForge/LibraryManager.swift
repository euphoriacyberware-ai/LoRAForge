import Foundation
import TaggingCore

@Observable
final class LibraryManager {
    struct ProjectInfo: Identifiable, Hashable {
        let id: UUID
        var name: String
        let url: URL
        /// Sidebar folder containing the bundle, or nil at the library's top level.
        var folder: String?
        // Synthesized equality compares every field. An id-only == made SwiftUI treat a
        // moved or renamed project as unchanged and skip redrawing the sidebar.
    }

    private(set) var projects: [ProjectInfo] = []
    /// Folder names at the library's top level, including empty ones. One level deep only.
    private(set) var folders: [String] = []
    private(set) var libraryURL: URL
    struct ExternalUpdate: Equatable {
        let projectID: UUID
        private let nonce = UUID()
    }

    private(set) var lastExternalUpdate: ExternalUpdate?

    @ObservationIgnored private var loadedDocuments: [UUID: ProjectDocument] = [:]
    @ObservationIgnored private var saveTask: [UUID: Task<Void, Never>] = [:]

    private static let libraryURLKey = "customLibraryURL"

    private static var defaultLibraryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "LoRAForge Library")
    }

    init() {
        if let bookmark = UserDefaults.standard.data(forKey: Self.libraryURLKey),
           let resolved = Self.resolveBookmark(bookmark) {
            self.libraryURL = resolved
        } else {
            self.libraryURL = Self.defaultLibraryURL
        }
        ensureLibraryExists()
        refresh()
    }

    init(libraryURL: URL) {
        self.libraryURL = libraryURL
        ensureLibraryExists()
        refresh()
    }

    // MARK: - Library migration

    func migrateLibrary(to destination: URL) throws {
        let fm = FileManager.default
        let oldURL = libraryURL

        // Ensure destination exists
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        // Save all dirty documents before moving
        saveAllDirty()

        // Move each top-level .loraforge bundle and sidebar folder to the new location
        let items = Self.libraryItems(in: oldURL)

        for itemURL in items.bundles + items.folders {
            let destURL = destination.appending(path: itemURL.lastPathComponent)
            if fm.fileExists(atPath: destURL.path) {
                // Skip items that already exist at destination
                continue
            }
            try fm.moveItem(at: itemURL, to: destURL)
        }

        // Persist the new location as a security-scoped bookmark
        if let bookmark = try? destination.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: Self.libraryURLKey)
        }

        // Clear in-memory state that referenced old URLs
        loadedDocuments.removeAll()
        saveTask.values.forEach { $0.cancel() }
        saveTask.removeAll()

        ThumbnailStore.shared.clearAll()
        libraryURL = destination
        refresh()
    }

    private static func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }

    private func ensureLibraryExists() {
        try? FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
    }

    // MARK: - Scanning

    /// Scans the library root and one level of folders beneath it. Bundles nested any
    /// deeper are not part of the library.
    func refresh() {
        let top = Self.libraryItems(in: libraryURL)

        var infos: [ProjectInfo] = []
        func addBundle(_ url: URL, folder: String?) {
            if let doc = try? ProjectBundle(url: url).readProject() {
                infos.append(ProjectInfo(id: doc.id, name: doc.name, url: url, folder: folder))
            }
        }
        for url in top.bundles { addBundle(url, folder: nil) }

        var folderNames: [String] = []
        for folderURL in top.folders {
            let name = folderURL.lastPathComponent
            folderNames.append(name)
            for url in Self.libraryItems(in: folderURL).bundles { addBundle(url, folder: name) }
        }

        infos.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        folderNames.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        projects = infos
        folders = folderNames
    }

    /// Visible `.loraforge` bundles and plain directories directly inside `directory`.
    private static func libraryItems(in directory: URL) -> (bundles: [URL], folders: [URL]) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return ([], []) }

        var bundles: [URL] = []
        var folders: [URL] = []
        for url in contents {
            if url.pathExtension == "loraforge" {
                bundles.append(url)
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                folders.append(url)
            }
        }
        return (bundles, folders)
    }

    // MARK: - Create / Delete / Rename

    func createProject(name: String, folder: String? = nil, repo: TagRepository) throws -> ProjectInfo {
        let categories = try repo.allCategories()
        let tags = try repo.allTags()
        let doc = ProjectDocument(name: name, categories: categories)
        let schema = SchemaSnapshot(categories: categories, tags: tags)

        let bundleURL = uniqueBundleURL(named: name, in: directoryURL(forFolder: folder))

        try ProjectBundle.create(at: bundleURL, project: doc, schema: schema)
        loadedDocuments[doc.id] = doc

        let info = ProjectInfo(id: doc.id, name: doc.name, url: bundleURL, folder: folder)
        refresh()
        return info
    }

    func deleteProject(id: UUID) throws {
        guard let info = projects.first(where: { $0.id == id }) else { return }
        saveTask[id]?.cancel()
        saveTask.removeValue(forKey: id)
        loadedDocuments.removeValue(forKey: id)
        try FileManager.default.removeItem(at: info.url)
        refresh()
    }

    func renameProject(id: UUID, to newName: String) throws {
        guard var doc = try loadDocument(id: id) else { return }
        guard let info = projects.first(where: { $0.id == id }) else { return }

        doc.name = newName
        loadedDocuments[id] = doc
        try saveImmediately(id: id)

        // Attempt to rename bundle directory to match, staying in the same folder
        let sanitized = sanitizeFilename(newName)
        let currentFilename = info.url.deletingPathExtension().lastPathComponent
        if sanitized != currentFilename {
            let newURL = uniqueBundleURL(named: newName, in: info.url.deletingLastPathComponent())
            try? FileManager.default.moveItem(at: info.url, to: newURL)
        }

        ThumbnailStore.shared.clearAll()
        refresh()
    }

    func duplicateProject(id: UUID, newName: String) throws -> ProjectInfo {
        guard let source = projects.first(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        // If the source is currently loaded and dirty, save it first
        if loadedDocuments[id] != nil {
            try saveImmediately(id: id)
        }

        // Copy entire bundle next to the source, in the same folder
        let destURL = uniqueBundleURL(named: newName, in: source.url.deletingLastPathComponent())
        try FileManager.default.copyItem(at: source.url, to: destURL)

        // Patch project.json with new UUID and name
        let bundle = ProjectBundle(url: destURL)
        var doc = try bundle.readProject()
        doc = ProjectDocument(
            id: UUID(),
            name: newName,
            createdAt: Date(),
            categoryOrder: doc.categoryOrder,
            categoryEnabled: doc.categoryEnabled,
            entries: doc.entries,
            referenceImages: doc.referenceImages,
            defaultGenerationConfigJSON: doc.defaultGenerationConfigJSON
        )
        try bundle.writeProjectAtomic(doc)

        refresh()
        return ProjectInfo(id: doc.id, name: doc.name, url: destURL, folder: source.folder)
    }

    // MARK: - Folders

    enum FolderError: LocalizedError {
        case nameTaken(String)
        case notFound(String)
        case notEmpty(folder: String, leftovers: [String])

        var errorDescription: String? {
            switch self {
            case .nameTaken(let name):
                "A folder named \"\(name)\" already exists."
            case .notFound(let name):
                "The folder \"\(name)\" no longer exists."
            case .notEmpty(let folder, let leftovers):
                "The projects were moved out, but \"\(folder)\" still contains other files and was kept: \(leftovers.joined(separator: ", "))."
            }
        }
    }

    /// Creates a folder at the library's top level. Returns the final name, which gains a
    /// numeric suffix if the requested one is taken.
    @discardableResult
    func createFolder(name: String) throws -> String {
        let base = sanitizeFilename(name)
        var finalName = base
        var counter = 2
        while FileManager.default.fileExists(atPath: libraryURL.appending(path: finalName).path)
                || folders.contains(where: { $0.caseInsensitiveCompare(finalName) == .orderedSame }) {
            finalName = "\(base) \(counter)"
            counter += 1
        }
        try FileManager.default.createDirectory(
            at: libraryURL.appending(path: finalName), withIntermediateDirectories: false
        )
        refresh()
        return finalName
    }

    /// Renames a folder. Folders never merge: an existing target name is an error.
    /// Returns the final (sanitised) name.
    @discardableResult
    func renameFolder(_ name: String, to newName: String) throws -> String {
        let sanitized = sanitizeFilename(newName)
        guard sanitized != name else { return name }
        let source = libraryURL.appending(path: name)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw FolderError.notFound(name)
        }
        let isCaseOnlyChange = sanitized.caseInsensitiveCompare(name) == .orderedSame
        if !isCaseOnlyChange, FileManager.default.fileExists(atPath: libraryURL.appending(path: sanitized).path) {
            throw FolderError.nameTaken(sanitized)
        }
        saveAllDirty()
        try FileManager.default.moveItem(at: source, to: libraryURL.appending(path: sanitized))
        ThumbnailStore.shared.clearAll()
        refresh()
        return sanitized
    }

    /// Moves a project's bundle into `folder`, or to the top level when nil. Safe while the
    /// project is loaded or generating: routing and saving look bundles up by project UUID.
    func moveProject(id: UUID, toFolder folder: String?) throws {
        guard let info = projects.first(where: { $0.id == id }) else { return }
        guard info.folder != folder else { return }
        if let folder, !folders.contains(folder) { throw FolderError.notFound(folder) }

        if loadedDocuments[id] != nil {
            try saveImmediately(id: id)
        }
        saveTask[id]?.cancel()
        saveTask.removeValue(forKey: id)

        let name = info.url.deletingPathExtension().lastPathComponent
        let destURL = uniqueBundleURL(named: name, in: directoryURL(forFolder: folder))
        try FileManager.default.moveItem(at: info.url, to: destURL)

        ThumbnailStore.shared.clearAll()
        refresh()
    }

    /// Deletes a folder. With `deletingProjects` false, its projects move to the top level
    /// first, and the directory is only removed if nothing else is left in it.
    func deleteFolder(_ name: String, deletingProjects: Bool) throws {
        let folderURL = libraryURL.appending(path: name)
        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            throw FolderError.notFound(name)
        }
        let members = projects.filter { $0.folder == name }

        if deletingProjects {
            for member in members {
                try deleteProject(id: member.id)
            }
            try FileManager.default.removeItem(at: folderURL)
            refresh()
            return
        }

        for member in members {
            try moveProject(id: member.id, toFolder: nil)
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        guard leftovers.isEmpty else {
            refresh()
            throw FolderError.notEmpty(folder: name, leftovers: leftovers.map(\.lastPathComponent))
        }
        try FileManager.default.removeItem(at: folderURL)
        refresh()
    }

    // MARK: - Load / Save

    func loadDocument(id: UUID) throws -> ProjectDocument? {
        if let cached = loadedDocuments[id] { return cached }
        guard let info = projects.first(where: { $0.id == id }) else { return nil }
        let bundle = ProjectBundle(url: info.url)
        var doc = try bundle.readProject()
        if stripOrphanedImages(&doc, bundleURL: info.url) {
            try? bundle.writeProjectAtomic(doc)
        }
        loadedDocuments[id] = doc
        return doc
    }

    func updateDocument(_ doc: ProjectDocument) {
        loadedDocuments[doc.id] = doc
        scheduleSave(id: doc.id)
    }

    func updateDocumentExternally(_ doc: ProjectDocument) {
        loadedDocuments[doc.id] = doc
        lastExternalUpdate = ExternalUpdate(projectID: doc.id)
    }

    func scheduleSave(id: UUID) {
        saveTask[id]?.cancel()
        saveTask[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? self?.saveImmediately(id: id)
        }
    }

    func saveImmediately(id: UUID) throws {
        saveTask[id]?.cancel()
        saveTask.removeValue(forKey: id)
        guard let doc = loadedDocuments[id],
              let info = projects.first(where: { $0.id == id }) else { return }
        let bundle = ProjectBundle(url: info.url)
        try bundle.writeProjectAtomic(doc)
    }

    func saveAllDirty() {
        for id in loadedDocuments.keys {
            try? saveImmediately(id: id)
        }
    }

    func saveAndUnload(id: UUID) {
        try? saveImmediately(id: id)
        loadedDocuments.removeValue(forKey: id)
    }

    func saveSchema(id: UUID, repo: TagRepository) throws {
        guard let info = projects.first(where: { $0.id == id }) else { return }
        let categories = try repo.allCategories()
        let tags = try repo.allTags()
        let snapshot = SchemaSnapshot(categories: categories, tags: tags)
        let bundle = ProjectBundle(url: info.url)
        try bundle.writeSchemaAtomic(snapshot)
    }

    func bundleURL(for id: UUID) -> URL? {
        projects.first { $0.id == id }?.url
    }

    // MARK: - Cross-project frequency

    func tagFrequencyAcrossProjects() -> [UUID: Int] {
        var frequency: [UUID: Int] = [:]
        for info in projects {
            let bundle = ProjectBundle(url: info.url)
            guard let doc = try? bundle.readProject() else { continue }
            for entry in doc.entries {
                for assignment in entry.assignments {
                    frequency[assignment.tagID, default: 0] += 1
                }
            }
        }
        return frequency
    }

    // MARK: - Helpers

    /// Removes image records whose files no longer exist on disk. Returns true if any were removed.
    private func stripOrphanedImages(_ doc: inout ProjectDocument, bundleURL: URL) -> Bool {
        let fm = FileManager.default
        let imagesDir = bundleURL.appending(path: "images")
        var changed = false
        for i in doc.entries.indices {
            let before = doc.entries[i].images.count
            doc.entries[i].images.removeAll { image in
                !fm.fileExists(atPath: imagesDir.appending(path: image.filename).path)
            }
            if doc.entries[i].images.count != before { changed = true }
        }
        return changed
    }

    private func directoryURL(forFolder folder: String?) -> URL {
        folder.map { libraryURL.appending(path: $0) } ?? libraryURL
    }

    /// `name.loraforge` in `directory`, or `name 2.loraforge`, `name 3.loraforge`… if taken.
    private func uniqueBundleURL(named name: String, in directory: URL) -> URL {
        let sanitized = sanitizeFilename(name)
        var url = directory.appending(path: "\(sanitized).loraforge")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appending(path: "\(sanitized) \(counter).loraforge")
            counter += 1
        }
        return url
    }

    private func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\")
        let cleaned = name.unicodeScalars.filter { !illegal.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned))
            .trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "Untitled" : result
    }
}
