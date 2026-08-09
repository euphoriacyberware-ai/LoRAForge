import SwiftUI

struct ContentView: View {
    @State private var selectedTab = AppTab.datasetBuilder
    @State private var showingSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dataset builder", systemImage: "square.grid.2x2", value: .datasetBuilder) {
                NavigationStack {
                    DatasetBuilderView()
                        .navigationTitle("Dataset builder")
                        .settingsToolbarButton($showingSettings)
                }
            }
            Tab("Reference library", systemImage: "photo.on.rectangle", value: .referenceLibrary) {
                NavigationStack {
                    ReferenceLibraryView()
                        .navigationTitle("Reference library")
                        .settingsToolbarButton($showingSettings)
                }
            }
            Tab("Tag library", systemImage: "tag", value: .tagLibrary) {
                NavigationStack {
                    TagLibraryView()
                        .navigationTitle("Tag library")
                        .settingsToolbarButton($showingSettings)
                }
            }
        }
        #if os(iOS)
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
    }
}

enum AppTab: Hashable {
    case datasetBuilder
    case referenceLibrary
    case tagLibrary
}

extension View {
    @ViewBuilder
    func settingsToolbarButton(_ isPresented: Binding<Bool>) -> some View {
        #if os(iOS)
        self.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPresented.wrappedValue = true } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        #else
        self
        #endif
    }
}
