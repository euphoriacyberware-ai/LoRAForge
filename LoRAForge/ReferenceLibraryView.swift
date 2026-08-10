import SwiftUI

struct ReferenceLibraryView: View {
    var body: some View {
        ContentUnavailableView(
            "Reference Library",
            systemImage: "photo.stack",
            description: Text("Reference image management will be built in phase 10.")
        )
        .navigationTitle("Reference Library")
    }
}

#Preview {
    ReferenceLibraryView()
}
