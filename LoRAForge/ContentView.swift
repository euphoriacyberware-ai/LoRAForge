import SwiftUI

struct ContentView: View {
    @ObservedObject var document: LoRAForgeDocument

    var body: some View {
        NavigationSplitView {
            List {
                Section("Source Images") {
                    if document.project.sourceImages.isEmpty {
                        Text("No source images")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Prompts") {
                    if document.project.prompts.isEmpty {
                        Text("No prompts")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            Text("Select a prompt to get started")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}
