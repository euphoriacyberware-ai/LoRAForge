import SwiftUI

struct DatasetBuilderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Dataset builder",
                systemImage: "square.grid.2x2",
                description: Text("Project content will appear here.")
            )
            .navigationTitle("Dataset builder")
            .withSettingsAccess()
        }
    }
}
