import SwiftUI

struct ContentView: View {
    @State private var selectedTab = AppTab.datasetBuilder

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dataset builder", systemImage: "square.grid.2x2", value: .datasetBuilder) {
                DatasetBuilderView()
            }
            Tab("Reference library", systemImage: "photo.on.rectangle", value: .referenceLibrary) {
                ReferenceLibraryView()
            }
            Tab("Tag library", systemImage: "tag", value: .tagLibrary) {
                TagLibraryView()
            }
        }
    }
}

enum AppTab: Hashable {
    case datasetBuilder
    case referenceLibrary
    case tagLibrary
}
