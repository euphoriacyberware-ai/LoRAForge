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
    @State private var sidebarSelection: SidebarItem?
    @State private var lastProjectID: UUID?
    @State private var selectedTab: ProjectTab = .datasetBuilder
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section("Projects") {
                // Phase 4 populates this from the library folder.
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
        .onChange(of: sidebarSelection) { oldValue, _ in
            if case .project(let id) = oldValue {
                lastProjectID = id
            }
        }
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
            switch selectedTab {
            case .datasetBuilder:
                if case .project = sidebarSelection {
                    DatasetBuilderView()
                } else {
                    ContentUnavailableView(
                        "No project selected",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Select a project from the sidebar or create a new one.")
                    )
                }
            case .referenceLibrary:
                if case .project = sidebarSelection {
                    ReferenceLibraryView()
                } else {
                    ContentUnavailableView(
                        "No project selected",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Select a project from the sidebar or create a new one.")
                    )
                }
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
