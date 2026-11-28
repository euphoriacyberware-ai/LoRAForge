import SwiftUI
import TaggingCore

struct CaptionEditorView: View {
    @Binding var entry: EntryDocument
    let bundleURL: URL
    let projectCategoryOrder: [UUID]
    let projectCategoryEnabled: [UUID: Bool]
    let tagFrequency: [UUID: Int]
    let onChanged: () -> Void

    @Environment(TagRepository.self) private var repo
    @Environment(OllamaRepository.self) private var ollamaRepo
    @Environment(\.dismiss) private var dismiss

    @State private var categories: [TagCategory] = []
    @State private var allTags: [UUID: [Tag]] = [:]
    @State private var previousCaptionText: String?
    @State private var showingUnlockDiff = false
    @State private var ollamaProfiles: [SDOllamaProfile] = []
    @State private var showingProfilePicker = false
    @State private var isOllamaRunning = false
    @State private var ollamaError: String?

    private var enabledCategories: [TagCategory] {
        ProjectCategories.resolve(categories, order: projectCategoryOrder, enabled: projectCategoryEnabled)
            .filter(\.isEnabled)
    }

    private var renderedCaption: String {
        let tagDict = allTags.values.flatMap { $0 }
            .reduce(into: [UUID: Tag]()) { $0[$1.id] = $1 }
        let domainAssignments = entry.assignments.map {
            TagAssignment(tagID: $0.tagID, selectionOrder: $0.selectionOrder)
        }
        return CaptionRenderer.render(
            assignments: domainAssignments, tags: tagDict, categories: enabledCategories
        )
    }

    private var currentCaptionText: String {
        if let locked = entry.lockedCaptionText { return locked }
        switch entry.captionMode {
        case .tagged: return renderedCaption
        case .manual, .ollama: return entry.manualCaptionText
        }
    }

    private var hasDrift: Bool {
        guard entry.isLocked, entry.captionMode == .tagged else { return false }
        return entry.lockedCaptionText != renderedCaption
    }

    var body: some View {
        NavigationStack {
            captionEditorContent
            .navigationTitle("\(String(format: "%03d", entry.position)) · \(entry.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: loadData)
            .sheet(isPresented: $showingProfilePicker) {
                OllamaProfilePickerSheet(
                    profiles: ollamaProfiles,
                    onSelect: { profile in
                        showingProfilePicker = false
                        runAutoCaption(profile: profile)
                    }
                )
            }
            .alert("Captioning error", isPresented: .init(
                get: { ollamaError != nil },
                set: { if !$0 { ollamaError = nil } }
            )) {
                Button("OK") { ollamaError = nil }
            } message: {
                Text(ollamaError ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 1200, idealWidth: 1400, minHeight: 800, idealHeight: 900)
        #endif
    }

    @ViewBuilder
    private var captionEditorContent: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            // The image is the reference the caption is written from, so it takes the
            // space the editor doesn't need.
            imageWell
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            editorPanel
                .frame(minWidth: 620, idealWidth: 680, maxWidth: 720)
        }
        #else
        ScrollView {
            VStack(spacing: 0) {
                imageWell
                    .frame(height: 250)
                editorPanel
            }
        }
        #endif
    }

    // MARK: - Image Well

    @ViewBuilder
    private var imageWell: some View {
        if let finalImg = entry.finalImage {
            let imageURL = bundleURL.appending(path: "images/\(finalImg.filename)")
            #if os(macOS)
            if let nsImage = NSImage(contentsOf: imageURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            } else {
                imagePlaceholder
            }
            #else
            if let data = try? Data(contentsOf: imageURL),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            } else {
                imagePlaceholder
            }
            #endif
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        VStack {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No final image")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editor Panel

    private var editorPanel: some View {
        VStack(spacing: 0) {
            // Pinned top: mode bar + caption field
            modeAndLockBar
            Divider()
            captionField
            Divider()

            // Scrollable middle: tag panel
            tagPanel

            // Pinned bottom: preview
            Divider()
            renderPreview
        }
    }

    private var modeAndLockBar: some View {
        HStack {
            Picker("Mode", selection: $entry.captionMode) {
                Text("Tagged").tag(CaptionMode.tagged)
                Text("Manual").tag(CaptionMode.manual)
                Text("Auto").tag(CaptionMode.ollama)
            }
            .pickerStyle(.segmented)
            .disabled(entry.isLocked)
            .frame(maxWidth: 300)
            .onChange(of: entry.captionMode) { oldMode, newMode in
                guard !entry.isLocked else { return }
                if newMode == .tagged && oldMode != .tagged {
                    previousCaptionText = entry.manualCaptionText
                }
                if oldMode == .tagged && newMode != .tagged {
                    if entry.manualCaptionText.isEmpty {
                        entry.manualCaptionText = renderedCaption
                    }
                }
                updatePreview()
                onChanged()
            }

            Spacer()

            if hasDrift {
                Label("Drifted", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                if entry.isLocked {
                    unlockEntry()
                } else {
                    lockEntry()
                }
            } label: {
                Label(
                    entry.isLocked ? "Locked" : "Lock",
                    systemImage: entry.isLocked ? "lock.fill" : "lock.open"
                )
            }

            // Auto-caption wand
            Button { showingProfilePicker = true } label: {
                if isOllamaRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Auto-caption", systemImage: "wand.and.stars")
                }
            }
            .disabled(entry.finalImage == nil || entry.isLocked || isOllamaRunning)
            .help(entry.finalImage == nil
                  ? "Requires a final image"
                  : "Auto-caption with a vision model")
        }
        .padding(8)
    }

    @ViewBuilder
    private var captionField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Caption")
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.isLocked {
                Text(currentCaptionText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            } else if entry.captionMode == .tagged {
                Text(currentCaptionText.isEmpty ? "Assign tags below to build a caption" : currentCaptionText)
                    .foregroundStyle(currentCaptionText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
            } else {
                TextEditor(text: $entry.manualCaptionText)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 100)
                    .onChange(of: entry.manualCaptionText) { updatePreview(); onChanged() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Tag Panel

    private var tagPanel: some View {
        VStack(spacing: 0) {
            HStack {
                let assigned = enabledCategories.filter { cat in
                    entry.assignments.contains { a in
                        allTags[cat.id]?.contains { $0.id == a.tagID } ?? false
                    }
                }.count
                Text("\(assigned)/\(enabledCategories.count) categories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(enabledCategories) { category in
                        TagRowView(
                            category: category,
                            assignments: $entry.assignments,
                            availableTags: allTags[category.id] ?? [],
                            tagFrequency: tagFrequency,
                            repo: repo,
                            onChanged: {
                                reloadTags()
                                updatePreview()
                                onChanged()
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Render Preview

    private var renderPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tag preview")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(renderedCaption.isEmpty ? "No tags assigned" : renderedCaption)
                .font(.callout)
                .foregroundStyle(renderedCaption.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.gray.opacity(0.05))
    }

    // MARK: - Actions

    private func loadData() {
        categories = (try? repo.allCategories()) ?? []
        reloadTags()
        ollamaProfiles = (try? ollamaRepo.allProfiles()) ?? []
    }

    private func reloadTags() {
        for cat in categories {
            allTags[cat.id] = (try? repo.tags(in: cat.id)) ?? []
        }
    }

    /// The entry's trigger: the canonical string of its Subject tag.
    private var trigger: String? {
        let subjectTags = allTags[BuiltInCategory.subject.id] ?? []
        let assigned = Set(entry.assignments.map(\.tagID))
        return subjectTags.first { assigned.contains($0.id) }?.canonicalString
    }

    private func runAutoCaption(profile: SDOllamaProfile) {
        guard let finalImg = entry.finalImage else { return }
        let imageURL = bundleURL.appending(path: "images/\(finalImg.filename)")
        guard let imageData = try? Data(contentsOf: imageURL) else {
            ollamaError = "Could not load the final image."
            return
        }
        let instruction: String
        do {
            instruction = try CaptionInstruction.resolve(profile.instruction, trigger: trigger)
        } catch {
            ollamaError = error.localizedDescription
            return
        }
        let settings = CaptionRequestSettings(
            api: profile.api, endpoint: profile.endpoint,
            model: profile.model, disablesReasoning: profile.disablesReasoning
        )

        isOllamaRunning = true
        Task {
            do {
                let response = try await CaptionClient.caption(
                    settings: settings, instruction: instruction, imageData: imageData
                )
                previousCaptionText = entry.manualCaptionText
                entry.captionMode = .ollama
                entry.manualCaptionText = response
                updatePreview()
                onChanged()
            } catch {
                ollamaError = error.localizedDescription
            }
            isOllamaRunning = false
        }
    }

    private func updatePreview() {
        entry.captionPreviewText = currentCaptionText
        entry.driftDetected = hasDrift
    }

    private func lockEntry() {
        entry.lockedCaptionText = currentCaptionText
        entry.driftDetected = false
        updatePreview()
        onChanged()
    }

    private func unlockEntry() {
        if hasDrift {
            showingUnlockDiff = true
        }
        entry.lockedCaptionText = nil
        entry.driftDetected = false
        updatePreview()
        onChanged()
    }
}

// MARK: - Ollama Profile Picker

private struct OllamaProfilePickerSheet: View {
    let profiles: [SDOllamaProfile]
    let onSelect: (SDOllamaProfile) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if profiles.isEmpty {
                    Text("No captioning profiles configured. Add one in Settings → Connections.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        Button {
                            onSelect(profile)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).font(.headline)
                                Text("\(profile.api.shortName) · \(profile.model.isEmpty ? "server's model" : profile.model) — \(profile.endpoint)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(profile.instruction)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Choose captioning profile")
            #if os(macOS)
            .frame(minWidth: 350, minHeight: 250)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
