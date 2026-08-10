import SwiftUI

struct DatasetBuilderView: View {
    @ObservedObject var document: LoRAForgeDocument

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Dataset builder",
                systemImage: "square.grid.2x2",
                description: Text("Entries will appear here.")
            )
            .navigationTitle(document.metadata.name)
            .withSettingsAccess()
        }
    }
}
