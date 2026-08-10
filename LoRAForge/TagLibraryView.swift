import SwiftUI

struct TagLibraryView: View {
    var body: some View {
        ContentUnavailableView(
            "Tag Library",
            systemImage: "tag",
            description: Text("Category and tag management will be built in phase 3.")
        )
        .navigationTitle("Tag Library")
    }
}

#Preview {
    TagLibraryView()
}
