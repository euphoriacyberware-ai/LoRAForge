import SwiftUI

enum SidebarItem: Hashable {
    case project(id: UUID)
    case tagLibrary
}

enum ProjectTab: String, CaseIterable {
    case datasetBuilder = "Dataset Builder"
    case referenceLibrary = "Reference Library"
}

struct ContentView: View {
    @Environment(TagRepository.self) private var repo
    @Environment(LibraryManager.self) private var library
    @State private var sidebarSelection: SidebarItem?
    @State private var lastProjectID: UUID?
    @State private var selectedTab: ProjectTab = .datasetBuilder
    @State private var showingSettings = false
    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var projectToDelete: LibraryManager.ProjectInfo?
    @State private var currentDocument: ProjectDocument?
    @State private var renamingProjectID: UUID?
    @State private var renameText = ""

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
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            library.saveAllDirty()
        }
        #endif
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section("Projects") {
                ForEach(library.projects) { project in
                    Label(project.name, systemImage: "doc.fill")
                        .tag(SidebarItem.project(id: project.id))
                        .contextMenu { projectContextMenu(for: project) }
                }
            }

            Section {
                Label("Tag Library", systemImage: "tag")
                    .tag(SidebarItem.tagLibrary)
            }
        }
        .navigationTitle("LoRAForge")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button { showingNewProject = true } label: {
                    Label("New project", systemImage: "plus")
                }
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingSettings = true } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
        #endif
        .alert("New project", isPresented: $showingNewProject) {
            TextField("Project name", text: $newProjectName)
            Button("Create") { createProject() }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        }
        .alert("Rename project", isPresented: .init(
            get: { renamingProjectID != nil },
            set: { if !$0 { renamingProjectID = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") { performRename() }
            Button("Cancel", role: .cancel) { renamingProjectID = nil }
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
    }

    @ViewBuilder
    private func projectContextMenu(for project: LibraryManager.ProjectInfo) -> some View {
        Button("Rename...") {
            renameText = project.name
            renamingProjectID = project.id
        }
        Button("Delete...", role: .destructive) {
            projectToDelete = project
        }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { newProjectName = ""; return }
        if let info = try? library.createProject(name: name, repo: repo) {
            sidebarSelection = .project(id: info.id)
        }
        newProjectName = ""
    }

    private func performRename() {
        guard let id = renamingProjectID else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { renamingProjectID = nil; return }
        try? library.renameProject(id: id, to: name)
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

    private func saveCurrentProject() {
        guard let doc = currentDocument else { return }
        library.updateDocument(doc)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if sidebarSelection == .tagLibrary {
            TagLibraryView()
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
        }
    }
}

#Preview {
    ContentView()
}
