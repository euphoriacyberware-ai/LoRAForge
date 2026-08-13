import SwiftUI
import UniformTypeIdentifiers

struct TemplateLibraryView: View {
    @Environment(TemplateManager.self) private var templateManager
    @Environment(LibraryManager.self) private var library
    @State private var selectedTemplateID: UUID?
    @State private var showingSaveSheet = false
    @State private var showingLoadConfirm = false
    @State private var importError: String?
    @State private var showingImportError = false

    private var selectedProject: LibraryManager.ProjectInfo? {
        library.projects.first
    }

    var body: some View {
        List(templateManager.templates, selection: $selectedTemplateID) { template in
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.headline)
                HStack {
                    Text("\(template.prompts.count) prompt(s)")
                    Text("—")
                    Text(template.createdAt, style: .date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .tag(template.id)
        }
        .navigationTitle("Templates Library")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    importTemplate()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

                Button {
                    exportTemplate()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(selectedTemplateID == nil)

                Button(role: .destructive) {
                    if let id = selectedTemplateID {
                        templateManager.delete(id: id)
                        selectedTemplateID = nil
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedTemplateID == nil)
            }
        }
        .overlay {
            if templateManager.templates.isEmpty {
                ContentUnavailableView(
                    "No templates",
                    systemImage: "doc.on.doc",
                    description: Text("Import a template or save entries from a project.")
                )
            }
        }
        .alert("Import failed", isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    // MARK: - Import / Export

    private func importTemplate() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.message = "Select a template JSON file to import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        performImport(from: url)
        #endif
    }

    private func exportTemplate() {
        guard let id = selectedTemplateID,
              let template = templateManager.templates.first(where: { $0.id == id }) else { return }
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "\(template.name).json"
        panel.message = "Export template as JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try templateManager.exportTemplate(template, to: url)
        } catch {
            importError = error.localizedDescription
            showingImportError = true
        }
        #endif
    }

    private func performImport(from url: URL) {
        do {
            try templateManager.importTemplate(from: url)
        } catch {
            importError = error.localizedDescription
            showingImportError = true
        }
    }
}
