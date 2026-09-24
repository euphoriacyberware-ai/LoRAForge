import SwiftUI
import TaggingCore
import DTConfigEditorKit
import DTConfigBridge
import DrawThingsClient

struct ProjectSettingsView: View {
    @Binding var document: ProjectDocument
    let onChanged: () -> Void

    @Environment(TagRepository.self) private var repo
    @Environment(GenerationPresetRepository.self) private var presetRepo
    @Environment(\.dismiss) private var dismiss

    @State private var categories: [TagCategory] = []
    @State private var presets: [SDGenerationPreset] = []
    @State private var configModel: ConfigEditorModel?
    @State private var showingApplyAllAlert = false
    @State private var showingApplyOrderAlert = false
    @State private var selectedTab: SettingsTab = .categories

    private enum SettingsTab: Hashable {
        case categories, configuration
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Inline rather than a .principal toolbar item: macOS sheets
                // don't render principal toolbar items.
                Picker("", selection: $selectedTab) {
                    Text("Categories").tag(SettingsTab.categories)
                    Text("Configuration").tag(SettingsTab.configuration)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, 8)
                .padding(.bottom, 4)

                Divider()

                switch selectedTab {
                case .categories:
                    leftPane
                case .configuration:
                    rightPane
                }
            }
            .navigationTitle("Project settings")
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                categories = (try? repo.allCategories()) ?? []
                presets = (try? presetRepo.allPresets()) ?? []
                initConfigModel()
            }
        }
    }

    // MARK: - Categories tab

    private var leftPane: some View {
        List {
            Section("Category order and enabled state") {
                Text("These settings are independent of the app defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(orderedCategories) { cat in
                    Toggle(isOn: Binding(
                        get: { document.categoryEnabled[cat.id] ?? true },
                        set: {
                            document.categoryEnabled[cat.id] = $0
                            onChanged()
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text(cat.name)
                            if let prefix = cat.prefix, !prefix.isEmpty {
                                Text(prefix)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .onMove(perform: moveCategories)
            }

            Section {
                Button("Re-render all captions", role: .destructive) {
                    showingApplyOrderAlert = true
                }
                .help("Re-render caption previews for all unlocked tagged entries using the current category order.")
            }
        }
        .listStyle(.sidebar)
        .alert("Re-render all captions?", isPresented: $showingApplyOrderAlert) {
            Button("Re-render", role: .destructive) { reRenderAllCaptions() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will re-render caption previews for all unlocked tagged entries using the current category order and enabled state. Locked and manual captions are not affected.")
        }
    }

    // MARK: - Configuration tab

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default generation configuration")
                .font(.headline)
            Text("Entries in this project use this config unless they override it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Preset picker
            if !presets.isEmpty {
                HStack {
                    Text("Load preset:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Menu("Presets") {
                        ForEach(presets) { preset in
                            Button(preset.name) { loadPreset(preset) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            if let configModel {
                ConfigTextView(model: configModel)
                    .onChange(of: configModel.text) {
                        document.defaultGenerationConfigJSON = configModel.text
                        onChanged()
                    }
            }

            HStack {
                if configModel?.isValid == true {
                    Label("Valid", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if configModel != nil {
                    Label("Invalid JSON", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Text("Seed and batch size are overridden by the app.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            Button("Apply to all entries", role: .destructive) {
                showingApplyAllAlert = true
            }
            .help("Overwrite the generation configuration of every entry in this project with the current default.")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert("Apply default configuration to all entries?", isPresented: $showingApplyAllAlert) {
            Button("Apply to all", role: .destructive) { applyConfigToAllEntries() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will overwrite the generation configuration for all \(document.entries.count) entries in this project. This cannot be undone.")
        }
    }

    // MARK: - Helpers

    private var orderedCategories: [TagCategory] {
        document.categoryOrder.compactMap { catID in
            categories.first { $0.id == catID }
        }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var order = document.categoryOrder
        order.move(fromOffsets: source, toOffset: destination)
        if let subjectIdx = order.firstIndex(of: BuiltInCategory.subject.id), subjectIdx != 0 {
            return
        }
        document.categoryOrder = order
        onChanged()
    }

    private func initConfigModel() {
        let json = document.defaultGenerationConfigJSON
        if json.trimmingCharacters(in: .whitespaces).isEmpty {
            configModel = ConfigEditorModel(DrawThingsConfiguration(), style: .nonDefaultOnly)
            document.defaultGenerationConfigJSON = configModel?.text ?? ""
        } else {
            configModel = ConfigEditorModel(text: json)
        }
    }

    private func loadPreset(_ preset: SDGenerationPreset) {
        configModel = ConfigEditorModel(text: preset.configJSON)
        document.defaultGenerationConfigJSON = preset.configJSON
        onChanged()
    }

    private func applyConfigToAllEntries() {
        let config = document.defaultGenerationConfigJSON
        for index in document.entries.indices {
            document.entries[index].generationConfigJSON = config
        }
        onChanged()
    }

    private func reRenderAllCaptions() {
        let enabledCats: [TagCategory] = document.categoryOrder.compactMap { catID in
            guard document.categoryEnabled[catID] != false else { return nil }
            return categories.first { $0.id == catID }
        }
        let allTags: [UUID: Tag] = categories.compactMap { cat in
            (try? repo.tags(in: cat.id))?.map { (cat.id, $0) }
        }
        .flatMap { $0 }
        .reduce(into: [UUID: Tag]()) { $0[$1.1.id] = $1.1 }

        for index in document.entries.indices {
            let entry = document.entries[index]
            guard entry.captionMode == .tagged else { continue }
            let domainAssignments = entry.assignments.map {
                TagAssignment(tagID: $0.tagID, selectionOrder: $0.selectionOrder)
            }
            let rendered = CaptionRenderer.render(
                assignments: domainAssignments, tags: allTags, categories: enabledCats
            )
            if entry.isLocked {
                document.entries[index].driftDetected = (rendered != entry.lockedCaptionText)
            } else {
                document.entries[index].captionPreviewText = rendered
                document.entries[index].driftDetected = false
            }
        }
        onChanged()
    }
}
