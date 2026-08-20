import Foundation
import TaggingCore

@Observable
final class LibraryManager {
    struct ProjectInfo: Identifiable, Hashable {
        let id: UUID
        var name: String
        let url: URL

        static func == (lhs: ProjectInfo, rhs: ProjectInfo) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private(set) var projects: [ProjectInfo] = []
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

        // Move each .loraforge bundle to the new location
        let bundles = (try? fm.contentsOfDirectory(at: oldURL, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "loraforge" } ?? []

        for bundleURL in bundles {
            let destURL = destination.appending(path: bundleURL.lastPathComponent)
            if fm.fileExists(atPath: destURL.path) {
                // Skip bundles that already exist at destination
                continue
            }
            try fm.moveItem(at: bundleURL, to: destURL)
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

    func refresh() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: libraryURL, includingPropertiesForKeys: nil
        ) else {
            projects = []
            return
        }

        var infos: [ProjectInfo] = []
        for url in contents where url.pathExtension == "loraforge" {
            let bundle = ProjectBundle(url: url)
            if let doc = try? bundle.readProject() {
                infos.append(ProjectInfo(id: doc.id, name: doc.name, url: url))
            }
        }
        infos.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        projects = infos
    }

    // MARK: - Create / Delete / Rename

    func createProject(name: String, repo: TagRepository) throws -> ProjectInfo {
        let categories = try repo.allCategories()
        let tags = try repo.allTags()
        let doc = ProjectDocument(name: name, categories: categories)
        let schema = SchemaSnapshot(categories: categories, tags: tags)

        let sanitized = sanitizeFilename(name)
        var bundleURL = libraryURL.appending(path: "\(sanitized).loraforge")
        var counter = 2
        while FileManager.default.fileExists(atPath: bundleURL.path) {
            bundleURL = libraryURL.appending(path: "\(sanitized) \(counter).loraforge")
            counter += 1
        }

        try ProjectBundle.create(at: bundleURL, project: doc, schema: schema)
        loadedDocuments[doc.id] = doc

        let info = ProjectInfo(id: doc.id, name: doc.name, url: bundleURL)
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

        // Attempt to rename bundle directory to match
        let sanitized = sanitizeFilename(newName)
        let currentFilename = info.url.deletingPathExtension().lastPathComponent
        if sanitized != currentFilename {
            var newURL = libraryURL.appending(path: "\(sanitized).loraforge")
            if FileManager.default.fileExists(atPath: newURL.path) {
                var counter = 2
                while FileManager.default.fileExists(atPath: newURL.path) {
                    newURL = libraryURL.appending(path: "\(sanitized) \(counter).loraforge")
                    counter += 1
                }
            }
            try? FileManager.default.moveItem(at: info.url, to: newURL)
        }

        ThumbnailStore.shared.clearAll()
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
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: libraryURL, includingPropertiesForKeys: nil
        ) else { return [:] }

        var frequency: [UUID: Int] = [:]
        for url in contents where url.pathExtension == "loraforge" {
            let bundle = ProjectBundle(url: url)
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

    private func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\")
        let cleaned = name.unicodeScalars.filter { !illegal.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned))
            .trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "Untitled" : result
    }
}
