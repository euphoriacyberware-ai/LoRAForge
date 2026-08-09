import SwiftUI

struct TagLibraryView: View {
    var body: some View {
        ContentUnavailableView(
            "Tag library",
            systemImage: "tag",
            description: Text("Categories and tags will appear here.")
        )
    }
}
