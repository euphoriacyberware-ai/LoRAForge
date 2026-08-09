import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                Text("General settings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Tab("Draw Things", systemImage: "paintbrush") {
                Text("Draw Things settings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Tab("Ollama", systemImage: "text.bubble") {
                Text("Ollama settings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Tab("Tagging", systemImage: "tag") {
                Text("Tagging settings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Tab("Generation", systemImage: "wand.and.stars") {
                Text("Generation settings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 300)
        #endif
    }
}
