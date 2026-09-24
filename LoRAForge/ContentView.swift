import SwiftUI

enum SidebarItem: Hashable {
    case project(id: UUID)
    case tagLibrary
    case configLibrary
    case templateLibrary
    case settingsGeneral
    case settingsConnections
}

enum ProjectTab: String, CaseIterable {
    case datasetBuilder = "Dataset Builder"
    case referenceLibrary = "Reference Library"
}

struct ContentView: View {
    @Environment(TagRepository.self) private var repo
    @Environment(LibraryManager.self) private var library
    @Environment(GenerationService.self) private var generation
    @State private var sidebarSelection: SidebarItem?
    @State private var lastProjectID: UUID?
    @State private var selectedTab: ProjectTab = .datasetBuilder
    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var projectToDelete: LibraryManager.ProjectInfo?
    @State private var currentDocument: ProjectDocument?
    @State private var renamingProjectID: UUID?
    @State private var renameText = ""
    @State private var duplicatingProject: LibraryManager.ProjectInfo?
    @State private var duplicateName = ""
    @State private var showingQueuePopover = false
    @State private var showingProjectSettings = false
    @State private var importResult: LegacyImporter.BatchImportResult?
    @State private var showingImportResult = false
    @State private var importError: String?
    @State private var showingImportError = false
    @AppStorage("generateUnfilledCount") private var generateUnfilledCount: Int = 1
    @State private var newProjectFolder: String?
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var projectPendingNewFolder: UUID?
    @State private var renamingFolder: String?
    @State private var renameFolderText = ""
    @State private var folderToDelete: String?
    @State private var folderError: String?
    @AppStorage("collapsedSidebarFolders") private var collapsedFoldersJSON = "[]"

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .onChange(of: sidebarSelection) { oldValue, newValue in
            // Save and unload previous project
            if case .project(let id) = oldValue {
                lastProjectID = id
                if let doc = currentDocument {
                    library.updateDocument(doc)
                }
                library.saveAndUnload(id: id)
                try? library.saveSchema(id: id, repo: repo)
                currentDocument = nil
            }
            // Load new project
            if case .project(let id) = newValue {
                currentDocument = try? library.loadDocument(id: id)
            }
        }
        .onChange(of: library.lastExternalUpdate) { _, update in
            guard let update else { return }
            if case .project(let id) = sidebarSelection, id == update.projectID {
                currentDocument = try? library.loadDocument(id: id)
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            library.saveAllDirty()
        }
        #endif
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section {
                ForEach(library.folders, id: \.self) { folder in
                    folderRow(folder)
                }
                // Keyed on the whole value (including folder), so a move is a remove + insert.
                // The macOS sidebar won't otherwise reparent a row whose identity is unchanged.
                ForEach(library.projects.filter { $0.folder == nil }, id: \.self) { project in
                    projectRow(project)
                }
            } header: {
                Text("Projects")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { items, _ in
                        moveDroppedProjects(items, toFolder: nil)
                    }
            }

            Section("Libraries") {
                Label("Tags", systemImage: "tag")
                    .tag(SidebarItem.tagLibrary)
                Label("Configurations", systemImage: "slider.horizontal.3")
                    .tag(SidebarItem.configLibrary)
                Label("Templates", systemImage: "doc.on.doc")
                    .tag(SidebarItem.templateLibrary)
            }

            Section("Settings") {
                Label("General", systemImage: "gear")
                    .tag(SidebarItem.settingsGeneral)
                Label("Connections", systemImage: "network")
                    .tag(SidebarItem.settingsConnections)
            }
        }
        .navigationTitle("LoRAForge")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { performImport() } label: {
                    Label("Import project", systemImage: "square.and.arrow.down")
                }
                Button {
                    projectPendingNewFolder = nil
                    showingNewFolder = true
                } label: {
                    Label("New folder", systemImage: "folder.badge.plus")
                }
                Button {
                    newProjectFolder = nil
                    showingNewProject = true
                } label: {
                    Label("New project", systemImage: "plus")
                }
            }
        }
        .alert("New project", isPresented: $showingNewProject) {
            TextField("Project name", text: $newProjectName)
            Button("Create") { createProject() }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        } message: {
            if let newProjectFolder {
                Text("In \(newProjectFolder)")
            }
        }
        .alert("New folder", isPresented: $showingNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
                projectPendingNewFolder = nil
            }
        }
        .alert("Rename folder", isPresented: .init(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Name", text: $renameFolderText)
            Button("Rename") { performRenameFolder() }
            Button("Cancel", role: .cancel) { renamingFolder = nil }
        }
        .confirmationDialog(
            "Delete folder \"\(folderToDelete ?? "")\"?",
            isPresented: .init(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: folderToDelete
        ) { folder in
            let count = projectsInFolder(folder).count
            if count > 0 {
                Button("Ungroup projects") { performDeleteFolder(folder, deletingProjects: false) }
                Button("Delete folder and \(count) project\(count == 1 ? "" : "s")", role: .destructive) {
                    performDeleteFolder(folder, deletingProjects: true)
                }
            } else {
                Button("Delete folder", role: .destructive) {
                    performDeleteFolder(folder, deletingProjects: false)
                }
            }
            Button("Cancel", role: .cancel) { folderToDelete = nil }
        } message: { folder in
            let count = projectsInFolder(folder).count
            if count > 0 {
                Text("Ungrouping moves its \(count) project\(count == 1 ? "" : "s") to the top level. Deleting them also deletes all their images and cannot be undone.")
            } else {
                Text("The folder is empty.")
            }
        }
        .alert("Folder error", isPresented: .init(
            get: { folderError != nil },
            set: { if !$0 { folderError = nil } }
        )) {
            Button("OK") { folderError = nil }
        } message: {
            Text(folderError ?? "")
        }
        .alert("Rename project", isPresented: .init(
            get: { renamingProjectID != nil },
            set: { if !$0 { renamingProjectID = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") { performRename() }
            Button("Cancel", role: .cancel) { renamingProjectID = nil }
        }
        .alert("Duplicate project", isPresented: .init(
            get: { duplicatingProject != nil },
            set: { if !$0 { duplicatingProject = nil } }
        )) {
            TextField("Name", text: $duplicateName)
            Button("Duplicate") { performDuplicate() }
            Button("Cancel", role: .cancel) { duplicatingProject = nil }
        }
        .alert("Delete project?", isPresented: .init(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        } message: {
            if let project = projectToDelete {
                Text("'\(project.name)' and all its images will be permanently deleted.")
            }
        }
        .alert("Import complete", isPresented: $showingImportResult) {
            Button("OK") { importResult = nil }
        } message: {
            if let result = importResult {
                let lines = result.results.map { r in
                    if r.success {
                        return "\(r.name): \(r.entryCount) entries, \(r.imageCount) images, \(r.referenceCount) references"
                    } else {
                        return "\(r.name): failed — \(r.error ?? "unknown error")"
                    }
                }
                Text("\(result.successCount) succeeded, \(result.failureCount) failed\n\(lines.joined(separator: "\n"))")
            }
        }
        .alert("Import error", isPresented: $showingImportError) {
            Button("OK") { importError = nil }
        } message: {
            if let error = importError {
                Text(error)
            }
        }
    }

    private func projectRow(_ project: LibraryManager.ProjectInfo) -> some View {
        Label(project.name, systemImage: "doc.fill")
            .tag(SidebarItem.project(id: project.id))
            .contextMenu { projectContextMenu(for: project) }
            .draggable(project.id.uuidString)
    }

    private func folderRow(_ folder: String) -> some View {
        let members = projectsInFolder(folder)
        return DisclosureGroup(isExpanded: folderExpansionBinding(folder)) {
            ForEach(members, id: \.self) { project in
                projectRow(project)
            }
        } label: {
            Label(folder, systemImage: "folder")
                .badge(members.count)
                .contextMenu { folderContextMenu(for: folder) }
                .dropDestination(for: String.self) { items, _ in
                    moveDroppedProjects(items, toFolder: folder)
                }
        }
    }

    @ViewBuilder
    private func folderContextMenu(for folder: String) -> some View {
        Button("New project in folder...") {
            newProjectFolder = folder
            showingNewProject = true
        }
        Button("Rename...") {
            renameFolderText = folder
            renamingFolder = folder
        }
        Button("Delete...", role: .destructive) {
            folderToDelete = folder
        }
    }

    @ViewBuilder
    private func projectContextMenu(for project: LibraryManager.ProjectInfo) -> some View {
        Menu("Move to") {
            ForEach(library.folders, id: \.self) { folder in
                Button(folder) { moveProject(project.id, toFolder: folder) }
                    .disabled(project.folder == folder)
            }
            if !library.folders.isEmpty { Divider() }
            Button("No folder") { moveProject(project.id, toFolder: nil) }
                .disabled(project.folder == nil)
            Divider()
            Button("New folder...") {
                projectPendingNewFolder = project.id
                showingNewFolder = true
            }
        }
        Divider()
        Button("Rename...") {
            renameText = project.name
            renamingProjectID = project.id
        }
        Button("Duplicate...") {
            duplicateName = project.name + " Copy"
            duplicatingProject = project
        }
        Button("Delete...", role: .destructive) {
            projectToDelete = project
        }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { newProjectName = ""; return }
        if let info = try? library.createProject(name: name, folder: newProjectFolder, repo: repo) {
            if let newProjectFolder { setFolder(newProjectFolder, collapsed: false) }
            sidebarSelection = .project(id: info.id)
        }
        newProjectName = ""
        newProjectFolder = nil
    }

    // MARK: - Folders

    private func projectsInFolder(_ folder: String) -> [LibraryManager.ProjectInfo] {
        library.projects.filter { $0.folder == folder }
    }

    private var collapsedFolders: Set<String> {
        get { (try? JSONDecoder().decode(Set<String>.self, from: Data(collapsedFoldersJSON.utf8))) ?? [] }
        nonmutating set {
            let data = (try? JSONEncoder().encode(newValue.sorted())) ?? Data("[]".utf8)
            collapsedFoldersJSON = String(decoding: data, as: UTF8.self)
        }
    }

    private func setFolder(_ folder: String, collapsed: Bool) {
        var set = collapsedFolders
        if collapsed { set.insert(folder) } else { set.remove(folder) }
        collapsedFolders = set
    }

    private func folderExpansionBinding(_ folder: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedFolders.contains(folder) },
            set: { setFolder(folder, collapsed: !$0) }
        )
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        let pendingProject = projectPendingNewFolder
        newFolderName = ""
        projectPendingNewFolder = nil
        guard !name.isEmpty else { return }
        do {
            let created = try library.createFolder(name: name)
            setFolder(created, collapsed: false)
            if let pendingProject {
                moveProject(pendingProject, toFolder: created)
            }
        } catch {
            folderError = error.localizedDescription
        }
    }

    private func performRenameFolder() {
        guard let folder = renamingFolder else { return }
        renamingFolder = nil
        let name = renameFolderText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        saveCurrentProject()
        do {
            let wasCollapsed = collapsedFolders.contains(folder)
            let renamed = try library.renameFolder(folder, to: name)
            setFolder(folder, collapsed: false)
            setFolder(renamed, collapsed: wasCollapsed)
        } catch {
            folderError = error.localizedDescription
        }
    }

    private func performDeleteFolder(_ folder: String, deletingProjects: Bool) {
        folderToDelete = nil
        if deletingProjects,
           case .project(let id) = sidebarSelection,
           projectsInFolder(folder).contains(where: { $0.id == id }) {
            sidebarSelection = nil
        }
        saveCurrentProject()
        do {
            try library.deleteFolder(folder, deletingProjects: deletingProjects)
            setFolder(folder, collapsed: false)
        } catch {
            folderError = error.localizedDescription
        }
    }

    private func moveProject(_ id: UUID, toFolder folder: String?) {
        // Push the open document's latest edits so the move writes them first.
        saveCurrentProject()
        do {
            try library.moveProject(id: id, toFolder: folder)
            if let folder { setFolder(folder, collapsed: false) }
        } catch {
            folderError = error.localizedDescription
        }
    }

    private func moveDroppedProjects(_ items: [String], toFolder folder: String?) -> Bool {
        let ids = items.compactMap(UUID.init(uuidString:))
            .filter { id in library.projects.contains { $0.id == id } }
        guard !ids.isEmpty else { return false }
        for id in ids { moveProject(id, toFolder: folder) }
        return true
    }

    private func performRename() {
        guard let id = renamingProjectID else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { renamingProjectID = nil; return }
        try? library.renameProject(id: id, to: name)
        if case .project(let selectedID) = sidebarSelection, selectedID == id {
            currentDocument?.name = name
        }
        renamingProjectID = nil
    }

    private func performDelete() {
        guard let project = projectToDelete else { return }
        if case .project(let id) = sidebarSelection, id == project.id {
            sidebarSelection = nil
        }
        try? library.deleteProject(id: project.id)
        projectToDelete = nil
    }

    private func performDuplicate() {
        guard let project = duplicatingProject else { return }
        let name = duplicateName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { duplicatingProject = nil; return }
        if let info = try? library.duplicateProject(id: project.id, newName: name) {
            sidebarSelection = .project(id: info.id)
        }
        duplicatingProject = nil
    }

    private func performImport() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Select .lforge or .loraforge projects, or a folder containing them"
        panel.delegate = ImportPanelDelegate.shared
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let selectedURLs = panel.urls

        do {
            let categories = try repo.allCategories()
            let tags = try repo.allTags()
            var existingNames = Set(library.projects.map(\.name))

            // Discover both formats
            var legacyBundles: [URL] = []
            var loraforgeBundles: [URL] = []
            for url in selectedURLs {
                legacyBundles.append(contentsOf: LegacyImporter.discoverLegacyBundles(at: url))
                loraforgeBundles.append(contentsOf: LegacyImporter.discoverLoRAForgeBundles(at: url))
            }

            guard !legacyBundles.isEmpty || !loraforgeBundles.isEmpty else {
                importError = "No .lforge or .loraforge projects found in the selection."
                showingImportError = true
                return
            }

            var allResults: [LegacyImporter.ImportResult] = []

            // Import legacy .lforge projects
            if !legacyBundles.isEmpty {
                let legacyResult = LegacyImporter.importLegacyProjects(
                    at: legacyBundles,
                    libraryURL: library.libraryURL,
                    existingNames: existingNames,
                    categories: categories,
                    tags: tags
                )
                for r in legacyResult.results {
                    if r.success { existingNames.insert(r.name) }
                }
                allResults.append(contentsOf: legacyResult.results)
            }

            // Import .loraforge projects
            if !loraforgeBundles.isEmpty {
                let loraforgeResult = LegacyImporter.importLoRAForgeProjects(
                    at: loraforgeBundles,
                    libraryURL: library.libraryURL,
                    existingNames: existingNames,
                    repo: repo
                )
                allResults.append(contentsOf: loraforgeResult.results)
            }

            library.refresh()
            importResult = LegacyImporter.BatchImportResult(results: allResults)
            showingImportResult = true
        } catch {
            importError = error.localizedDescription
            showingImportError = true
        }
        #endif
    }

    private func saveCurrentProject() {
        guard let doc = currentDocument else { return }
        library.updateDocument(doc)
    }

    // MARK: - Generate Unfilled

    private func entriesWithoutFinal(in doc: ProjectDocument) -> [EntryDocument] {
        doc.entries.filter { $0.finalImage == nil && !$0.generationPrompt.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func generateUnfilled(in doc: ProjectDocument) {
        guard case .project(let id) = sidebarSelection,
              let bundleURL = library.bundleURL(for: id) else { return }
        for entry in entriesWithoutFinal(in: doc) {
            for _ in 0..<generateUnfilledCount {
                generateForEntry(entry, in: doc, bundleURL: bundleURL)
            }
        }
    }

    private func generateForEntry(_ entry: EntryDocument, in doc: ProjectDocument, bundleURL: URL) {
        let prompt = entry.generationPrompt
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let seed: Int64? = entry.useCustomSeed ? entry.generationSeed : nil

        let refData: [Data] = entry.referenceImageIDs.compactMap { refID in
            guard let ref = doc.referenceImages.first(where: { $0.id == refID }) else { return nil }
            let url = bundleURL.appending(path: "references/\(ref.filename)")
            return try? Data(contentsOf: url)
        }

        generation.generate(
            prompt: prompt,
            negativePrompt: entry.generationNegativePrompt,
            seed: seed,
            configJSON: entry.generationConfigJSON,
            projectConfigJSON: doc.defaultGenerationConfigJSON,
            projectID: doc.id,
            entryID: entry.id,
            referenceImageData: refData,
            referenceImageIDs: entry.referenceImageIDs
        )
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            detailContent
        }
        // Attached at the detail-column level so connection and queue
        // controls are present on every sidebar selection.
        .toolbar { generationToolbarItems }
    }

    @ToolbarContentBuilder
    private var generationToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
                // Draw Things connection toggle
                Button {
                    if generation.isConnected {
                        generation.disconnect()
                    } else {
                        generation.connect()
                    }
                } label: {
                    Label(
                        generation.isConnected ? "Connected" : "Connect",
                        systemImage: generation.isConnected ? "bolt.fill" : "bolt.slash"
                    )
                }
                .labelStyle(.iconOnly)
                .help(generation.isConnected
                      ? "Connected to Draw Things — click to disconnect"
                      : "Connect to Draw Things at \(generation.serverAddress)")
                .foregroundStyle(generation.isConnected ? .green : .secondary)

                // Queue manager — visible when items are queued or processing
                if generation.pendingCount > 0 || generation.isProcessing {
                    Button { showingQueuePopover.toggle() } label: {
                        Label("Queue", systemImage: "hourglass")
                    }
                    .badge(generation.pendingCount + (generation.isProcessing ? 1 : 0))
                    .popover(isPresented: $showingQueuePopover) {
                        QueueManagerView()
                    }
                }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if sidebarSelection == .tagLibrary {
            TagLibraryView()
        } else if sidebarSelection == .configLibrary {
            ConfigLibraryView()
        } else if sidebarSelection == .templateLibrary {
            TemplateLibraryView()
        } else if sidebarSelection == .settingsGeneral {
            GeneralSettingsPanel()
        } else if sidebarSelection == .settingsConnections {
            ConnectionsSettingsPanel()
        } else {
            projectContent
        }
    }

    @ViewBuilder
    private var projectContent: some View {
        Group {
            if case .project(let id) = sidebarSelection, currentDocument != nil {
                switch selectedTab {
                case .datasetBuilder:
                    DatasetBuilderView(
                        document: Binding(
                            get: { currentDocument! },
                            set: { currentDocument = $0 }
                        ),
                        bundleURL: library.bundleURL(for: id) ?? URL(filePath: "/"),
                        onChanged: { saveCurrentProject() }
                    )
                case .referenceLibrary:
                    ReferenceLibraryView(
                        document: Binding(
                            get: { currentDocument! },
                            set: { currentDocument = $0 }
                        ),
                        bundleURL: library.bundleURL(for: id) ?? URL(filePath: "/"),
                        onChanged: { saveCurrentProject() }
                    )
                }
            } else {
                ContentUnavailableView(
                    "No project selected",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Select a project from the sidebar or create a new one.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $selectedTab) {
                    ForEach(ProjectTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItemGroup(placement: .automatic) {
                // Generate unfilled — visible on Dataset Builder when connected
                if selectedTab == .datasetBuilder,
                   generation.isConnected,
                   case .project = sidebarSelection,
                   let doc = currentDocument {
                    let unfilled = entriesWithoutFinal(in: doc)
                    GenerateUnfilledButton(
                        count: $generateUnfilledCount,
                        unfilledCount: unfilled.count,
                        disabled: unfilled.isEmpty
                    ) {
                        generateUnfilled(in: doc)
                    }
                    .help(unfilled.isEmpty
                          ? "All entries have a final image"
                          : "Generate \(generateUnfilledCount)× for \(unfilled.count) entr\(unfilled.count == 1 ? "y" : "ies") without a final — \(generateUnfilledCount * unfilled.count) total")
                }

                // Project settings — hidden on Tag Library
                if case .project = sidebarSelection, currentDocument != nil {
                    Button { showingProjectSettings = true } label: {
                        Label("Project settings", systemImage: "folder.badge.gearshape")
                    }
                }

            }
        }
        .sheet(isPresented: $showingProjectSettings) {
            if currentDocument != nil {
                ProjectSettingsView(
                    document: Binding(
                        get: { currentDocument! },
                        set: { currentDocument = $0 }
                    ),
                    onChanged: { saveCurrentProject() }
                )
            }
        }
    }
}

#Preview {
    ContentView()
}
