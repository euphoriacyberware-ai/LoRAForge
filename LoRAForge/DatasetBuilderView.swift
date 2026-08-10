import SwiftUI

struct DatasetBuilderView: View {
    var body: some View {
        ContentUnavailableView(
            "Dataset Builder",
            systemImage: "photo.on.rectangle.angled",
            description: Text("Entry list and image management will be built in phase 5.")
        )
        .navigationTitle("Dataset Builder")
    }
}

#Preview {
    DatasetBuilderView()
}
