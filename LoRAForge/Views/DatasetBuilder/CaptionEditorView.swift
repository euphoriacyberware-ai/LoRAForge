import SwiftUI
import SwiftData
import TaggingCore

struct CaptionEditorView: View {
    @ObservedObject var document: LoRAForgeDocument
    let entryIndex: Int
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager

    @State private var editingText = ""
    @State private var showModeChangeWarning = false
    @State private var pendingMode: CaptionMode?
    @State private var showUnlockDiff = false

    private var entry: DatasetEntry { document.entries[entryIndex] }

    var body: some View {
        VStack(spacing: 0) {
            topSection
            Divider()
            tagPanel
            Divider()
            previewBar
        }
        .navigationTitle(entry.name)
        .onAppear { editingText = entry.captionText }
        .onChange(of: entryIndex) { _, _ in editingText = document.entries[entryIndex].captionText }
        .alert("Switch to tagged mode?", isPresented: $showModeChangeWarning) {
            Button("Switch") { applyModeChange() }
            Button("Cancel", role: .cancel) { pendingMode = nil }
        } message: {
            Text("The current caption will be replaced with text rendered from your tags.")
        }
        .alert("Unlock caption?", isPresented: $showUnlockDiff) {
            Button("Unlock") { performUnlock() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let current = liveRender
            let locked = entry.lockedText ?? ""
            if current == locked {
                Text("The caption is unchanged.")
            } else {
                Text("Before: \(locked)\n\nAfter: \(current)")
            }
        }
    }

    // MARK: - Top Section

    private var topSection: some View {
        HStack(alignment: .top, spacing: 16) {
            // Image well
            imageWell
                .frame(width: 160, height: 160)

            // Caption + controls
            VStack(alignment: .leading, spacing: 8) {
                controlBar
                captionField
            }
        }
        .padding()
    }

    @ViewBuilder
    private var imageWell: some View {
        if let finalImg = entry.finalImage,
           let data = document.imageData(for: finalImg.filename),
           let image = Image(imageData: data) {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .overlay {
                    VStack {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                        Text("No final image")
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                }
        }
    }

    private var controlBar: some View {
        HStack {
            Picker("Mode", selection: modeBinding) {
                Text("Tagged").tag(CaptionMode.tagged)
                Text("Manual").tag(CaptionMode.manual)
                Text("Ollama").tag(CaptionMode.ollama).disabled(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 250)

            Spacer()

            if entry.isLocked {
                Button { showUnlockDiff = true } label: {
                    Label("Locked", systemImage: "lock.fill")
                }
                if hasDrift {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Caption has drifted from current tag state")
                }
            } else {
                Button { lock() } label: {
                    Label("Lock", systemImage: "lock.open")
                }
                .disabled(entry.captionText.isEmpty)
            }
        }
    }

    private var modeBinding: Binding<CaptionMode> {
        Binding(
            get: { entry.captionMode },
            set: { newMode in
                if newMode == .tagged && entry.captionMode != .tagged && !entry.captionText.isEmpty {
                    pendingMode = newMode
                    showModeChangeWarning = true
                } else {
                    switchMode(to: newMode)
                }
            }
        )
    }

    @ViewBuilder
    private var captionField: some View {
        if entry.isLocked {
            Text(entry.lockedText ?? entry.captionText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.secondary)
        } else if entry.captionMode == .tagged {
            Text(entry.captionText.isEmpty ? "Assign tags to generate a caption" : entry.captionText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(entry.captionText.isEmpty ? .tertiary : .primary)
        } else {
            TextEditor(text: $editingText)
                .frame(minHeight: 60)
                .padding(4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: editingText) { _, newValue in
                    document.entries[entryIndex].captionText = newValue
                }
        }
    }

    // MARK: - Tag Panel

    private var tagPanel: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(enabledCategories) { category in
                    if category.id != BuiltInCategories.subjectID {
                        CategoryTagRow(
                            document: document,
                            entryIndex: entryIndex,
                            category: category,
                            modelContext: modelContext,
                            isLocked: entry.isLocked
                        )
                        Divider()
                    } else {
                        // Subject row — project-scoped, simplified for now
                        SubjectRow(
                            document: document,
                            entryIndex: entryIndex,
                            isLocked: entry.isLocked
                        )
                        Divider()
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Preview Bar

    private var previewBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(liveRender.isEmpty ? "No tags assigned" : liveRender)
                .font(.callout)
                .foregroundStyle(liveRender.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Computed

    private var enabledCategories: [TagCategory] {
        let catRepo = SwiftDataCategoryRepository(modelContext: modelContext)
        let allCats = (try? catRepo.allCategories()) ?? []
        let catByID = Dictionary(allCats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var result: [TagCategory] = []
        for id in document.metadata.categoryOrder {
            if var cat = catByID[id] {
                if document.metadata.disabledCategories.contains(id) { cat.isEnabled = false }
                if cat.isEnabled { result.append(cat) }
            }
        }
        for cat in allCats where !document.metadata.categoryOrder.contains(cat.id) {
            if !document.metadata.disabledCategories.contains(cat.id) && cat.isEnabled {
                result.append(cat)
            }
        }
        return result
    }

    private var liveRender: String {
        let catRepo = SwiftDataCategoryRepository(modelContext: modelContext)
        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
        let allCats = (try? catRepo.allCategories()) ?? []
        let allTags = (try? tagRepo.allTags()) ?? []

        // Build categories with project order
        var ordered: [TagCategory] = []
        for id in document.metadata.categoryOrder {
            if var cat = allCats.first(where: { $0.id == id }) {
                if document.metadata.disabledCategories.contains(id) { cat.isEnabled = false }
                ordered.append(cat)
            }
        }
        for cat in allCats where !document.metadata.categoryOrder.contains(cat.id) {
            ordered.append(cat)
        }

        let assignments = entry.tagAssignments.map {
            TagAssignment(tagID: $0.tagID, selectionOrder: $0.selectionOrder)
        }
        return CaptionRenderer.render(assignments: assignments, tags: allTags, categories: ordered)
    }

    private var hasDrift: Bool {
        guard entry.isLocked, let locked = entry.lockedText else { return false }
        return locked != liveRender
    }

    // MARK: - Actions

    private func switchMode(to mode: CaptionMode) {
        let oldText = entry.captionText
        let oldMode = entry.captionMode

        document.entries[entryIndex].captionMode = mode

        if mode == .tagged {
            let rendered = liveRender
            document.entries[entryIndex].captionText = rendered
            editingText = rendered
        }

        undoManager?.registerUndo(withTarget: document) { doc in
            guard entryIndex < doc.entries.count else { return }
            doc.entries[entryIndex].captionMode = oldMode
            doc.entries[entryIndex].captionText = oldText
        }
        undoManager?.setActionName("Switch to \(mode.label)")
    }

    private func applyModeChange() {
        guard let mode = pendingMode else { return }
        switchMode(to: mode)
        pendingMode = nil
    }

    private func lock() {
        document.entries[entryIndex].isLocked = true
        if entry.captionMode == .tagged {
            document.entries[entryIndex].lockedText = liveRender
            document.entries[entryIndex].captionText = liveRender
        } else {
            document.entries[entryIndex].lockedText = entry.captionText
        }
    }

    private func performUnlock() {
        document.entries[entryIndex].isLocked = false
        if entry.captionMode == .tagged {
            let rendered = liveRender
            document.entries[entryIndex].captionText = rendered
            editingText = rendered
        }
        document.entries[entryIndex].lockedText = nil
    }
}

// MARK: - Category Tag Row

struct CategoryTagRow: View {
    @ObservedObject var document: LoRAForgeDocument
    let entryIndex: Int
    let category: TagCategory
    let modelContext: ModelContext
    let isLocked: Bool

    @State private var searchText = ""
    @State private var showCreateAlert = false
    @State private var showDuplicateAlert = false
    @State private var nearMatches: [NearMatch] = []
    @State private var pendingText = ""

    private var entry: DatasetEntry { document.entries[entryIndex] }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Category label
            VStack(alignment: .trailing, spacing: 2) {
                Text(category.name)
                    .font(.caption)
                    .fontWeight(.medium)
                if let prefix = category.prefix, !prefix.isEmpty {
                    Text(prefix)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 100, alignment: .trailing)

            // Selected tags
            FlowLayout(spacing: 4) {
                ForEach(selectedTags, id: \.id) { tag in
                    tagChip(tag)
                }
                if !isLocked {
                    tagInput
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .confirmationDialog("Similar tags found", isPresented: $showDuplicateAlert, titleVisibility: .visible) {
            Button("Create '\(pendingText)' anyway") { forceCreate() }
            Button("Cancel", role: .cancel) { pendingText = "" }
        } message: {
            let list = nearMatches.map { "\($0.tag.canonicalString) (\(Int($0.similarity * 100))%)" }.joined(separator: "\n")
            Text("Similar tags:\n\(list)")
        }
    }

    private var selectedTags: [Tag] {
        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
        let allTags = (try? tagRepo.tags(inCategory: category.id)) ?? []
        let tagByID = Dictionary(allTags.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        return entry.tagAssignments
            .sorted { $0.selectionOrder < $1.selectionOrder }
            .compactMap { assignment in
                guard let tag = tagByID[assignment.tagID], tag.categoryID == category.id else { return nil }
                return tag
            }
    }

    private var availableTags: [Tag] {
        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
        let allTags = (try? tagRepo.tags(inCategory: category.id)) ?? []
        let assignedIDs = Set(entry.tagAssignments.map(\.tagID))
        var filtered = allTags.filter { !assignedIDs.contains($0.id) }
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.canonicalString.localizedCaseInsensitiveContains(searchText) }
        }
        return filtered.sorted { $0.canonicalString < $1.canonicalString }
    }

    @ViewBuilder
    private func tagChip(_ tag: Tag) -> some View {
        HStack(spacing: 4) {
            Text(tag.canonicalString)
                .font(.caption)
            if !isLocked {
                Button { removeTag(tag.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.blue.opacity(0.15), in: Capsule())
    }

    @ViewBuilder
    private var tagInput: some View {
        Menu {
            ForEach(availableTags) { tag in
                Button(tag.canonicalString) { addTag(tag.id) }
            }
            if !searchText.isEmpty {
                Divider()
                Button("Create '\(searchText)'") { createTag() }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.caption2)
                Text(selectedTags.isEmpty ? "Add..." : "")
                    .font(.caption)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Actions

    private func addTag(_ tagID: UUID) {
        let nextOrder = (entry.tagAssignments.map(\.selectionOrder).max() ?? -1) + 1

        if category.selectMode == .single {
            // Remove existing assignment for this category
            let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
            let catTags = (try? tagRepo.tags(inCategory: category.id)) ?? []
            let catTagIDs = Set(catTags.map(\.id))
            document.entries[entryIndex].tagAssignments.removeAll { catTagIDs.contains($0.tagID) }
        }

        document.entries[entryIndex].tagAssignments.append(
            CodableTagAssignment(tagID: tagID, selectionOrder: nextOrder)
        )
        updateCaptionIfTagged()
    }

    private func removeTag(_ tagID: UUID) {
        document.entries[entryIndex].tagAssignments.removeAll { $0.tagID == tagID }
        updateCaptionIfTagged()
    }

    private func createTag() {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
        let existing = (try? tagRepo.tags(inCategory: category.id)) ?? []
        let result = DuplicateDetector.check(text, against: existing)

        switch result {
        case .exactMatch(let tag):
            addTag(tag.id)
            searchText = ""
        case .nearMatches(let matches):
            nearMatches = matches
            pendingText = text
            showDuplicateAlert = true
        case .noMatch:
            if let created = try? tagRepo.createTag(canonicalString: text, inCategory: category.id) {
                addTag(created.id)
            }
            searchText = ""
        }
    }

    private func forceCreate() {
        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
        if let created = try? tagRepo.createTag(canonicalString: pendingText, inCategory: category.id) {
            addTag(created.id)
        }
        pendingText = ""
        searchText = ""
    }

    private func updateCaptionIfTagged() {
        guard document.entries[entryIndex].captionMode == .tagged,
              !document.entries[entryIndex].isLocked else { return }
        // Trigger a document change so SwiftUI re-evaluates the caption
        let current = document.entries[entryIndex].captionText
        document.entries[entryIndex].captionText = current
    }
}

// MARK: - Subject Row (simplified)

struct SubjectRow: View {
    @ObservedObject var document: LoRAForgeDocument
    let entryIndex: Int
    let isLocked: Bool

    @State private var subjectText = ""

    private var entry: DatasetEntry { document.entries[entryIndex] }

    var body: some View {
        HStack(spacing: 8) {
            Text("Subject")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 100, alignment: .trailing)

            if isLocked {
                Text(currentSubjectName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.15), in: Capsule())
            } else {
                TextField("Subject name", text: $subjectText)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .onAppear { subjectText = currentSubjectName }
                    .onSubmit { saveSubject() }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var currentSubjectName: String {
        // Subject tags are project-scoped, stored as a simple assignment
        // For Phase 6, we store subject as a tag assignment like any other
        let subjectAssignments = entry.tagAssignments.filter { assignment in
            // We don't have easy category lookup here, so use a name field instead
            false // Simplified — subject handled via text for now
        }
        return subjectText
    }

    private func saveSubject() {
        // Subject tag creation is project-scoped
        // For Phase 6, this is a placeholder — full implementation in Phase 9
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> LayoutResult {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return LayoutResult(
            positions: positions,
            size: CGSize(width: maxWidth, height: y + rowHeight)
        )
    }
}
