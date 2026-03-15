import SwiftUI
import UniformTypeIdentifiers

struct TemplateLibraryView: View {
    @ObservedObject var document: LoRAForgeDocument
    @ObservedObject var templateManager = TemplateManager.shared
    @Binding var isPresented: Bool
    @State private var selectedTemplateID: UUID?
    @State private var showingSaveSheet = false
    @State private var showingLoadConfirm = false
    @State private var loadMode: LoadMode = .append
    @State private var importError: String?
    @State private var showingImportError = false

    enum LoadMode {
        case append, replace
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Template Library")
                .font(.headline)
                .padding()

            Divider()

            // Template list
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
            .frame(minHeight: 200)

            Divider()

            // Buttons
            HStack {
                Button("Save Current Prompts…") {
                    showingSaveSheet = true
                }
                .disabled(document.project.prompts.isEmpty)

                Button("Import…") {
                    importTemplate()
                }

                Spacer()

                Button("Export…") {
                    exportTemplate()
                }
                .disabled(selectedTemplateID == nil)

                Button("Delete") {
                    if let id = selectedTemplateID {
                        templateManager.delete(id: id)
                        selectedTemplateID = nil
                    }
                }
                .disabled(selectedTemplateID == nil)

                Button("Load into Project…") {
                    showingLoadConfirm = true
                }
                .disabled(selectedTemplateID == nil)
            }
            .padding()

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 400, idealHeight: 500)
        .sheet(isPresented: $showingSaveSheet) {
            SaveTemplateSheet(document: document, isPresented: $showingSaveSheet)
        }
        .sheet(isPresented: $showingLoadConfirm) {
            if let id = selectedTemplateID,
               let template = templateManager.templates.first(where: { $0.id == id }) {
                LoadTemplateSheet(
                    document: document,
                    template: template,
                    isPresented: $showingLoadConfirm
                )
            }
        }
        .alert("Import Failed", isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    // MARK: - Import / Export

    private func importTemplate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.message = "Select a template JSON file to import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try templateManager.importTemplate(from: url)
        } catch {
            importError = error.localizedDescription
            showingImportError = true
        }
    }

    private func exportTemplate() {
        guard let id = selectedTemplateID,
              let template = templateManager.templates.first(where: { $0.id == id }) else { return }
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
    }
}

// MARK: - Save Template Sheet

struct SaveTemplateSheet: View {
    @ObservedObject var document: LoRAForgeDocument
    @Binding var isPresented: Bool
    @State private var templateName = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Save as Template")
                .font(.headline)

            TextField("Template Name", text: $templateName)
                .textFieldStyle(.roundedBorder)

            Text("This will save \(document.project.prompts.count) prompt(s) as a reusable template.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveTemplate()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(templateName.isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            templateName = document.project.name
        }
    }

    private func saveTemplate() {
        let templatePrompts = document.project.prompts.enumerated().map { index, prompt in
            TemplatePrompt(
                id: UUID(),
                order: index,
                text: prompt.text,
                sourceSlotIndex: nil,
                generateCount: prompt.generateCount
            )
        }

        let template = Template(
            id: UUID(),
            name: templateName,
            createdAt: Date(),
            prompts: templatePrompts
        )

        TemplateManager.shared.add(template)
    }
}

// MARK: - Load Template Sheet

struct LoadTemplateSheet: View {
    @ObservedObject var document: LoRAForgeDocument
    let template: Template
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Load Template")
                .font(.headline)

            Text("Template \"\(template.name)\" has \(template.prompts.count) prompt(s).")
                .font(.body)

            Text("How would you like to load them?")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Replace") {
                    loadTemplate(replace: true)
                    isPresented = false
                }

                Button("Append") {
                    loadTemplate(replace: false)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
    }

    private func loadTemplate(replace: Bool) {
        let startOrder: Int
        if replace {
            let ids = Set(document.project.prompts.map(\.id))
            document.trashPrompts(ids: ids)
            startOrder = 0
        } else {
            startOrder = document.project.prompts.count
        }

        for (index, tp) in template.prompts.sorted(by: { $0.order < $1.order }).enumerated() {
            let prompt = Prompt(
                id: UUID(),
                order: startOrder + index,
                text: tp.text,
                sourceImageIDs: sourceImageID(for: tp.sourceSlotIndex),
                generateCount: tp.generateCount,
                configurationOverrideJSON: nil,
                generatedImages: []
            )
            document.project.prompts.append(prompt)
        }

        document.updateChangeCount(.changeDone)
    }

    private func sourceImageID(for slotIndex: Int?) -> [UUID] {
        guard let index = slotIndex,
              index < document.project.sourceImages.count else { return [] }
        return [document.project.sourceImages[index].id]
    }
}
