import SwiftUI
import TaggingCore

struct CaptionEditorView: View {
    @Binding var entry: EntryDocument
    let bundleURL: URL
    let projectCategoryOrder: [UUID]
    let projectCategoryEnabled: [UUID: Bool]
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
        projectCategoryOrder.compactMap { catID in
            guard projectCategoryEnabled[catID] != false else { return nil }
            return categories.first { $0.id == catID }
        }
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
            .navigationTitle(entry.name)
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
                        runOllama(profile: profile)
                    }
                )
            }
            .alert("Ollama error", isPresented: .init(
                get: { ollamaError != nil },
                set: { if !$0 { ollamaError = nil } }
            )) {
                Button("OK") { ollamaError = nil }
            } message: {
                Text(ollamaError ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 500)
        #endif
    }

    @ViewBuilder
    private var captionEditorContent: some View {
        #if os(macOS)
        HSplitView {
            imageWell
                .frame(minWidth: 200, idealWidth: 300)
            editorPanel
                .frame(minWidth: 350)
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
            modeAndLockBar
            Divider()
            captionField
            Divider()
            tagPanel
            Divider()
            renderPreview
        }
    }

    private var modeAndLockBar: some View {
        HStack {
            Picker("Mode", selection: Binding(
                get: { entry.captionMode },
                set: { switchMode(to: $0) }
            )) {
                Text("Tagged").tag(CaptionMode.tagged)
                Text("Manual").tag(CaptionMode.manual)
                Text("Ollama").tag(CaptionMode.ollama)
            }
            .pickerStyle(.segmented)
            .disabled(entry.isLocked)
            .frame(maxWidth: 300)

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

            // Ollama wand
            Button { showingProfilePicker = true } label: {
                if isOllamaRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Ollama", systemImage: "wand.and.stars")
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
                    .onChange(of: entry.manualCaptionText) { onChanged() }
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
                LazyVStack(spacing: 2) {
                    ForEach(enabledCategories) { category in
                        TagRowView(
                            category: category,
                            assignments: $entry.assignments,
                            availableTags: allTags[category.id] ?? [],
                            repo: repo,
                            onChanged: {
                                if entry.captionMode == .tagged { onChanged() }
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
        for cat in categories {
            allTags[cat.id] = (try? repo.tags(in: cat.id)) ?? []
        }
        ollamaProfiles = (try? ollamaRepo.allProfiles()) ?? []
    }

    private func runOllama(profile: SDOllamaProfile) {
        guard let finalImg = entry.finalImage else { return }
        let imageURL = bundleURL.appending(path: "images/\(finalImg.filename)")
        guard let imageData = try? Data(contentsOf: imageURL) else {
            ollamaError = "Could not load the final image."
            return
        }

        isOllamaRunning = true
        Task {
            do {
                let response = try await OllamaClient.generate(
                    endpoint: profile.endpoint,
                    model: profile.model,
                    instruction: profile.instruction,
                    imageData: imageData
                )
                previousCaptionText = entry.manualCaptionText
                entry.captionMode = .ollama
                entry.manualCaptionText = response
                onChanged()
            } catch {
                ollamaError = error.localizedDescription
            }
            isOllamaRunning = false
        }
    }

    private func switchMode(to newMode: CaptionMode) {
        guard !entry.isLocked else { return }
        let oldMode = entry.captionMode

        if newMode == .tagged && oldMode != .tagged {
            previousCaptionText = entry.manualCaptionText
        }
        if oldMode == .tagged && newMode != .tagged {
            if entry.manualCaptionText.isEmpty {
                entry.manualCaptionText = renderedCaption
            }
        }

        entry.captionMode = newMode
        onChanged()
    }

    private func lockEntry() {
        entry.lockedCaptionText = currentCaptionText
        onChanged()
    }

    private func unlockEntry() {
        if hasDrift {
            showingUnlockDiff = true
        }
        entry.lockedCaptionText = nil
        onChanged()
    }
}

// MARK: - Tag Row

private struct TagRowView: View {
    let category: TagCategory
    @Binding var assignments: [AssignmentDocument]
    let availableTags: [Tag]
    let repo: TagRepository
    let onChanged: () -> Void

    @State private var searchText = ""
    @State private var showingSuggestions = false

    private var assignedTags: [Tag] {
        let catTags = Set(availableTags.map(\.id))
        return assignments
            .filter { catTags.contains($0.tagID) }
            .sorted { $0.selectionOrder < $1.selectionOrder }
            .compactMap { a in availableTags.first { $0.id == a.tagID } }
    }

    private var suggestions: [Tag] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        let assignedIDs = Set(assignedTags.map(\.id))
        return availableTags.filter {
            !assignedIDs.contains($0.id) && $0.canonicalString.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let prefix = category.prefix, !prefix.isEmpty {
                    Text(prefix)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(category.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)

                // Assigned tag chips
                ForEach(assignedTags) { tag in
                    HStack(spacing: 2) {
                        Text(tag.canonicalString)
                            .font(.callout)
                        Button {
                            removeTag(tag.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                }

                // Inline search field
                TextField("", text: $searchText, prompt: Text("Add..."))
                    .textFieldStyle(.plain)
                    .frame(minWidth: 60, maxWidth: 120)
                    .onSubmit { commitSearch() }
            }

            // Suggestions dropdown
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions.prefix(5)) { tag in
                        Button {
                            selectTag(tag)
                            searchText = ""
                        } label: {
                            Text(tag.canonicalString)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(radius: 2)
                .padding(.leading, 110)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private func selectTag(_ tag: Tag) {
        if category.selectMode == .single {
            // Replace: remove existing assignments for this category
            let catTagIDs = Set(availableTags.map(\.id))
            assignments.removeAll { catTagIDs.contains($0.tagID) }
            assignments.append(AssignmentDocument(tagID: tag.id, selectionOrder: 0))
        } else {
            let maxOrder = assignments
                .filter { a in availableTags.contains { $0.id == a.tagID } }
                .map(\.selectionOrder).max() ?? -1
            assignments.append(AssignmentDocument(tagID: tag.id, selectionOrder: maxOrder + 1))
        }
        onChanged()
    }

    private func removeTag(_ tagID: UUID) {
        assignments.removeAll { $0.tagID == tagID }
        onChanged()
    }

    private func commitSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Check if it matches an existing tag
        if let existing = availableTags.first(where: {
            DuplicateDetector.normalize($0.canonicalString) == DuplicateDetector.normalize(trimmed)
        }) {
            selectTag(existing)
            searchText = ""
            return
        }

        // Check for near-matches
        let result = DuplicateDetector.findDuplicates(candidate: trimmed, in: availableTags)
        switch result {
        case .exactMatch(let tag):
            selectTag(tag)
        case .nearMatches:
            // For now, create anyway (full UI would show confirmation)
            createAndSelectTag(trimmed)
        case .noMatch:
            createAndSelectTag(trimmed)
        }
        searchText = ""
    }

    private func createAndSelectTag(_ text: String) {
        if let tag = try? repo.addTag(canonicalString: text, toCategoryID: category.id) {
            let domainTag = tag
            // Need to use the tag we just created
            if category.selectMode == .single {
                let catTagIDs = Set(availableTags.map(\.id))
                assignments.removeAll { catTagIDs.contains($0.tagID) }
                assignments.append(AssignmentDocument(tagID: domainTag.id, selectionOrder: 0))
            } else {
                let maxOrder = assignments
                    .filter { a in availableTags.contains { $0.id == a.tagID } }
                    .map(\.selectionOrder).max() ?? -1
                assignments.append(AssignmentDocument(tagID: domainTag.id, selectionOrder: maxOrder + 1))
            }
            onChanged()
        }
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
                    Text("No Ollama profiles configured. Add one in Settings > Ollama.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        Button {
                            onSelect(profile)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).font(.headline)
                                Text("\(profile.model) — \(profile.endpoint)")
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
            .navigationTitle("Choose Ollama profile")
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
