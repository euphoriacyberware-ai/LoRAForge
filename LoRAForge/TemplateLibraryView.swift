import SwiftUI
import UniformTypeIdentifiers

struct TemplateLibraryView: View {
    @Environment(TemplateManager.self) private var templateManager
    @Environment(LibraryManager.self) private var library
    @State private var selectedTemplateID: UUID?
    @State private var importError: String?
    @State private var showingImportError = false
    @State private var newTemplateName = ""
    @State private var templateToDelete: Template?
    @State private var templateToRename: Template?
    @State private var renameName = ""

    var body: some View {
        HStack(spacing: 0) {
            templateList
                .frame(width: 250)
            Divider()
            templateEditor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    if let id = selectedTemplateID,
                       let template = templateManager.templates.first(where: { $0.id == id }) {
                        templateToDelete = template
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedTemplateID == nil)
            }
        }
        .alert("Import failed", isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    // MARK: - Template List

    private var templateList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedTemplateID) {
                ForEach(templateManager.templates) { template in
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
                    .contextMenu {
                        Button("Rename") {
                            renameName = template.name
                            templateToRename = template
                        }
                        Button("Duplicate") { duplicateTemplate(template) }
                        Divider()
                        Button("Delete", role: .destructive) { templateToDelete = template }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                TextField("New template", text: $newTemplateName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createTemplate() }
                Button { createTemplate() } label: {
                    Image(systemName: "plus")
                }
                .disabled(newTemplateName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
        }
        .alert("Delete template?", isPresented: .init(
            get: { templateToDelete != nil },
            set: { if !$0 { templateToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { templateToDelete = nil }
        } message: {
            if let template = templateToDelete {
                Text("Delete '\(template.name)'?")
            }
        }
        .alert("Rename template", isPresented: .init(
            get: { templateToRename != nil },
            set: { if !$0 { templateToRename = nil } }
        )) {
            TextField("Name", text: $renameName)
            Button("Rename") { performRename() }
            Button("Cancel", role: .cancel) { templateToRename = nil }
        }
    }

    // MARK: - Template Editor

    @ViewBuilder
    private var templateEditor: some View {
        if let selectedID = selectedTemplateID,
           let templateIndex = templateManager.templates.firstIndex(where: { $0.id == selectedID }) {
            let template = templateManager.templates[templateIndex]
            TemplateEditorPane(template: template, templateManager: templateManager)
                .id(selectedID)
        } else {
            ContentUnavailableView(
                "Select a template",
                systemImage: "doc.on.doc",
                description: Text("Choose a template to view and edit, or create a new one.")
            )
        }
    }

    // MARK: - Actions

    private func createTemplate() {
        let name = newTemplateName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let template = Template(
            id: UUID(),
            name: name,
            createdAt: Date(),
            prompts: []
        )
        templateManager.add(template)
        newTemplateName = ""
        selectedTemplateID = template.id
    }

    private func duplicateTemplate(_ template: Template) {
        let copy = Template(
            id: UUID(),
            name: "\(template.name) Copy",
            createdAt: Date(),
            prompts: template.prompts.map { prompt in
                TemplatePrompt(
                    id: UUID(),
                    order: prompt.order,
                    text: prompt.text,
                    sourceSlotIndex: prompt.sourceSlotIndex,
                    generateCount: prompt.generateCount
                )
            }
        )
        templateManager.add(copy)
    }

    private func performRename() {
        guard var template = templateToRename else { return }
        let trimmed = renameName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { templateToRename = nil; return }
        template.name = trimmed
        templateManager.update(template)
        templateToRename = nil
    }

    private func performDelete() {
        guard let template = templateToDelete else { return }
        if selectedTemplateID == template.id {
            selectedTemplateID = nil
        }
        templateManager.delete(id: template.id)
        templateToDelete = nil
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
            let imported = try templateManager.importTemplate(from: url)
            selectedTemplateID = imported.id
        } catch {
            importError = error.localizedDescription
            showingImportError = true
        }
    }
}

// MARK: - Template Editor Pane

private struct TemplateEditorPane: View {
    @State private var template: Template
    private var templateManager: TemplateManager

    init(template: Template, templateManager: TemplateManager) {
        self._template = State(initialValue: template)
        self.templateManager = templateManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.headline)
                Text(template.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)

            // Prompt list
            List {
                ForEach(Array(template.prompts.enumerated()), id: \.element.id) { index, prompt in
                    promptRow(index: index, prompt: prompt)
                }
                .onMove { source, destination in
                    template.prompts.move(fromOffsets: source, toOffset: destination)
                    recalculateOrder()
                    saveTemplate()
                }
            }
            .listStyle(.inset)
            .overlay {
                if template.prompts.isEmpty {
                    ContentUnavailableView(
                        "No prompts",
                        systemImage: "text.badge.plus",
                        description: Text("Add a prompt to get started.")
                    )
                }
            }

            // Add prompt button
            HStack {
                Spacer()
                Button {
                    let newPrompt = TemplatePrompt(
                        id: UUID(),
                        order: template.prompts.count,
                        text: "",
                        sourceSlotIndex: nil,
                        generateCount: 1
                    )
                    template.prompts.append(newPrompt)
                    saveTemplate()
                } label: {
                    Label("Add prompt", systemImage: "plus")
                }
                .padding(.bottom, 12)
                .padding(.trailing, 16)
            }
        }
    }

    @ViewBuilder
    private func promptRow(index: Int, prompt: TemplatePrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Prompt \(index + 1)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    template.prompts.removeAll { $0.id == prompt.id }
                    recalculateOrder()
                    saveTemplate()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }

            TextEditor(text: Binding(
                get: {
                    template.prompts.first(where: { $0.id == prompt.id })?.text ?? ""
                },
                set: { newValue in
                    if let idx = template.prompts.firstIndex(where: { $0.id == prompt.id }) {
                        template.prompts[idx].text = newValue
                        saveTemplate()
                    }
                }
            ))
            .font(.body)
            .frame(minHeight: 60)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )

            Stepper(
                "Generate count: \(prompt.generateCount)",
                value: Binding(
                    get: {
                        template.prompts.first(where: { $0.id == prompt.id })?.generateCount ?? 1
                    },
                    set: { newValue in
                        if let idx = template.prompts.firstIndex(where: { $0.id == prompt.id }) {
                            template.prompts[idx].generateCount = newValue
                            saveTemplate()
                        }
                    }
                ),
                in: 1...50
            )
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    private func recalculateOrder() {
        for i in template.prompts.indices {
            template.prompts[i].order = i
        }
    }

    private func saveTemplate() {
        templateManager.update(template)
    }
}
