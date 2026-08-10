import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsTab()
            }
            Tab("Draw Things", systemImage: "paintbrush") {
                Text("Draw Things settings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Tab("Ollama", systemImage: "brain") {
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

private struct GeneralSettingsTab: View {
    @Environment(LibraryManager.self) private var library

    var body: some View {
        Form {
            Section("Library folder") {
                LabeledContent("Location") {
                    Text(library.libraryURL.path(percentEncoded: false))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Projects") {
                    Text("\(library.projects.count)")
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
}
