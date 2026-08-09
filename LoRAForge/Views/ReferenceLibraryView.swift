import SwiftUI

struct ReferenceLibraryView: View {
    var body: some View {
        ContentUnavailableView(
            "Reference library",
            systemImage: "photo.on.rectangle",
            description: Text("Reference images will appear here.")
        )
    }
}
