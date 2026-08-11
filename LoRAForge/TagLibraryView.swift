import SwiftUI
import TaggingCore

struct TagLibraryView: View {
    @Environment(TagRepository.self) private var repo
    @State private var categories: [TagCategory] = []
    @State private var selectedCategoryID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            categoryList
                .frame(width: 280)
            Divider()
            tagDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Tag Library")
        .onAppear(perform: refresh)
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func refresh() {
        categories = (try? repo.allCategories()) ?? []
    }

    // MARK: - Category List

    private var categoryList: some View {
        CategoryListPane(
            categories: $categories,
            selectedCategoryID: $selectedCategoryID,
            repo: repo,
            onError: { errorMessage = $0 },
            onRefresh: refresh
        )
    }

    // MARK: - Tag Detail

    @ViewBuilder
    private var tagDetail: some View {
        if let catID = selectedCategoryID,
           let category = categories.first(where: { $0.id == catID }) {
            TagListPane(category: category, repo: repo, onError: { errorMessage = $0 })
        } else {
            ContentUnavailableView("Select a category", systemImage: "tag",
                                   description: Text("Choose a category to manage its tags."))
        }
    }
}

// MARK: - Category List Pane

private struct CategoryListPane: View {
    @Binding var categories: [TagCategory]
    @Binding var selectedCategoryID: UUID?
    let repo: TagRepository
    let onError: (String) -> Void
    let onRefresh: () -> Void

    @State private var showingNewCategory = false
    @State private var editingCategory: TagCategory?
    @State private var categoryToDelete: TagCategory?
    @State private var showingReorderWarning = false
    @State private var pendingReorder: (() -> Void)?

    var body: some View {
        List(selection: $selectedCategoryID) {
            ForEach(categories) { category in
                CategoryRow(category: category, onEdit: { editingCategory = category })
                    .tag(category.id)
                    .contextMenu { categoryContextMenu(for: category) }
            }
            .onMove(perform: moveCategories)
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button { showingNewCategory = true } label: {
                    Label("New category", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditorSheet(category: category, repo: repo, onSave: onRefresh)
        }
        .sheet(isPresented: $showingNewCategory) {
            NewCategorySheet(repo: repo, onSave: onRefresh)
        }
        .alert("Reorder categories?", isPresented: $showingReorderWarning) {
            Button("Reorder", role: .destructive) { pendingReorder?(); pendingReorder = nil }
            Button("Cancel", role: .cancel) { pendingReorder = nil; onRefresh() }
        } message: {
            Text("Reordering categories will change the render order of all captions. No projects in the library yet.")
        }
        .alert("Delete category?", isPresented: .init(
            get: { categoryToDelete != nil },
            set: { if !$0 { categoryToDelete = nil } }
        )) {
            if let cat = categoryToDelete {
                Button("Delete", role: .destructive) { performDelete(cat) }
                Button("Disable instead") { performDisable(cat) }
                Button("Cancel", role: .cancel) { categoryToDelete = nil }
            }
        } message: {
            if let cat = categoryToDelete {
                let tagCount = (try? repo.tagCount(in: cat.id)) ?? 0
                Text("'\(cat.name)' has \(tagCount) tag\(tagCount == 1 ? "" : "s"). No projects in the library yet.\n\nDisabling hides it without losing data.")
            }
        }
    }

    @ViewBuilder
    private func categoryContextMenu(for category: TagCategory) -> some View {
        Button("Edit...") { editingCategory = category }

        if category.isEnabled {
            Button("Disable") { toggleEnabled(category, enabled: false) }
        } else {
            Button("Enable") { toggleEnabled(category, enabled: true) }
        }

        Divider()

        if !category.isBuiltIn {
            Button("Delete...", role: .destructive) { categoryToDelete = category }
        }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var reordered = categories
        reordered.move(fromOffsets: source, toOffset: destination)

        // Subject must stay at position 0
        let subjectID = BuiltInCategory.subject.id
        if let subjectIdx = reordered.firstIndex(where: { $0.id == subjectID }), subjectIdx != 0 {
            onRefresh() // revert
            return
        }

        pendingReorder = {
            let ids = reordered.map(\.id)
            do {
                try repo.reorderCategories(ids)
                onRefresh()
            } catch {
                onError(error.localizedDescription)
            }
        }
        categories = reordered
        showingReorderWarning = true
    }

    private func toggleEnabled(_ category: TagCategory, enabled: Bool) {
        var updated = category
        updated.isEnabled = enabled
        do {
            try repo.updateCategory(updated)
            onRefresh()
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func performDelete(_ category: TagCategory) {
        do {
            try repo.deleteCategory(id: category.id)
            if selectedCategoryID == category.id { selectedCategoryID = nil }
            onRefresh()
        } catch {
            onError(error.localizedDescription)
        }
        categoryToDelete = nil
    }

    private func performDisable(_ category: TagCategory) {
        var updated = category
        updated.isEnabled = false
        do {
            try repo.updateCategory(updated)
            onRefresh()
        } catch {
            onError(error.localizedDescription)
        }
        categoryToDelete = nil
    }
}

// MARK: - Category Row

private struct CategoryRow: View {
    let category: TagCategory
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .foregroundStyle(category.isEnabled ? .primary : .secondary)
                if let prefix = category.prefix, !prefix.isEmpty {
                    Text(prefix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(category.selectMode == .multi ? "multi" : "single")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if !category.isEnabled {
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Category Editor Sheet

private struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let repo: TagRepository
    let onSave: () -> Void

    @State private var name: String
    @State private var prefix: String
    @State private var isEnabled: Bool
    @State private var highThreshold: Int
    @State private var lowThreshold: Int
    @State private var showingPrefixWarning = false

    private let category: TagCategory
    private let originalPrefix: String?

    init(category: TagCategory, repo: TagRepository, onSave: @escaping () -> Void) {
        self.category = category
        self.repo = repo
        self.onSave = onSave
        self._name = State(initialValue: category.name)
        self._prefix = State(initialValue: category.prefix ?? "")
        self._isEnabled = State(initialValue: category.isEnabled)
        self._highThreshold = State(initialValue: category.highThreshold)
        self._lowThreshold = State(initialValue: category.lowThreshold)
        self.originalPrefix = category.prefix
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Name", text: $name)
                    TextField("Prefix", text: $prefix, prompt: Text("e.g. wearing, holding"))
                    Toggle("Enabled", isOn: $isEnabled)
                }
                Section("Select mode") {
                    Text(category.selectMode == .multi ? "Multi-select" : "Single-select")
                        .foregroundStyle(.secondary)
                    Text("Select mode cannot be changed after creation.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Section("Coverage thresholds") {
                    Stepper("High: \(highThreshold)%", value: $highThreshold, in: 0...100, step: 5)
                    Stepper("Low: \(lowThreshold)%", value: $lowThreshold, in: 0...100, step: 5)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit \(category.name)")
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 320)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Editing prefix will change captions", isPresented: $showingPrefixWarning) {
                Button("Change prefix", role: .destructive) { commitSave() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Changing the prefix from '\(originalPrefix ?? "none")' to '\(prefix.isEmpty ? "none" : prefix)' will rewrite every caption using this category. No projects in the library yet.")
            }
        }
    }

    private func save() {
        let newPrefix = prefix.trimmingCharacters(in: .whitespaces)
        let oldPrefix = originalPrefix ?? ""
        if newPrefix != oldPrefix {
            showingPrefixWarning = true
        } else {
            commitSave()
        }
    }

    private func commitSave() {
        var updated = category
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.prefix = prefix.trimmingCharacters(in: .whitespaces).isEmpty ? nil : prefix.trimmingCharacters(in: .whitespaces)
        updated.isEnabled = isEnabled
        updated.highThreshold = highThreshold
        updated.lowThreshold = lowThreshold
        do {
            try repo.updateCategory(updated)
            onSave()
            dismiss()
        } catch {
            // handled by parent
        }
    }
}

// MARK: - New Category Sheet

private struct NewCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let repo: TagRepository
    let onSave: () -> Void

    @State private var name = ""
    @State private var selectMode: TagCategory.SelectMode = .single
    @State private var prefix = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Select mode", selection: $selectMode) {
                    Text("Single-select").tag(TagCategory.SelectMode.single)
                    Text("Multi-select").tag(TagCategory.SelectMode.multi)
                }
                TextField("Prefix", text: $prefix, prompt: Text("Optional, e.g. wearing"))
            }
            .formStyle(.grouped)
            .navigationTitle("New category")
            #if os(macOS)
            .frame(minWidth: 340, minHeight: 200)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let pfx = prefix.trimmingCharacters(in: .whitespaces)
        do {
            _ = try repo.addCategory(
                name: trimmed, selectMode: selectMode,
                prefix: pfx.isEmpty ? nil : pfx
            )
            onSave()
            dismiss()
        } catch {
            // handled by parent
        }
    }
}

// MARK: - Tag List Pane

private struct TagListPane: View {
    let category: TagCategory
    let repo: TagRepository
    let onError: (String) -> Void

    @State private var tags: [Tag] = []
    @State private var searchText = ""
    @State private var newTagText = ""
    @State private var duplicateResult: DuplicateDetector.Result?
    @State private var showingDuplicateAlert = false
    @State private var tagToDelete: Tag?

    private var filteredTags: [Tag] {
        if searchText.isEmpty { return tags }
        let query = searchText.lowercased()
        return tags.filter { $0.canonicalString.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            tagListHeader
            Divider()
            tagList
        }
        .onAppear(perform: refreshTags)
        .onChange(of: category.id) { refreshTags() }
        .alert("Delete tag?", isPresented: .init(
            get: { tagToDelete != nil },
            set: { if !$0 { tagToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) { performDeleteTag() }
            Button("Cancel", role: .cancel) { tagToDelete = nil }
        } message: {
            if let tag = tagToDelete {
                Text("Delete '\(tag.canonicalString)'? No projects in the library yet.")
            }
        }
        .alert("Similar tag exists", isPresented: $showingDuplicateAlert) {
            Button("Create anyway") { commitNewTag() }
            Button("Cancel", role: .cancel) { newTagText = "" }
        } message: {
            if case .nearMatches(let matches) = duplicateResult {
                let names = matches.prefix(3).map { "'\($0.tag.canonicalString)'" }.joined(separator: ", ")
                Text("Similar tags found: \(names). Create '\(newTagText)' anyway?")
            }
        }
    }

    private var tagListHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text(category.name)
                    .font(.headline)
                Spacer()
                Text("\(tags.count) tag\(tags.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            HStack {
                TextField("New tag", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { tryCreateTag() }
                Button("Add") { tryCreateTag() }
                    .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            TextField("Search tags", text: $searchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding()
    }

    private var tagList: some View {
        List {
            ForEach(filteredTags) { tag in
                HStack {
                    Text(tag.canonicalString)
                    Spacer()
                    Button(role: .destructive) { tagToDelete = tag } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if filteredTags.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if tags.isEmpty {
                ContentUnavailableView("No tags", systemImage: "tag",
                                       description: Text("Add tags to \(category.name) using the field above."))
            }
        }
    }

    private func refreshTags() {
        tags = (try? repo.tags(in: category.id)) ?? []
    }

    private func tryCreateTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let result = DuplicateDetector.findDuplicates(candidate: trimmed, in: tags)
        switch result {
        case .exactMatch(let existing):
            onError("'\(trimmed)' matches existing tag '\(existing.canonicalString)'.")
            newTagText = ""
        case .nearMatches:
            duplicateResult = result
            showingDuplicateAlert = true
        case .noMatch:
            commitNewTag()
        }
    }

    private func commitNewTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try repo.addTag(canonicalString: trimmed, toCategoryID: category.id)
            newTagText = ""
            refreshTags()
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func performDeleteTag() {
        guard let tag = tagToDelete else { return }
        do {
            try repo.deleteTag(id: tag.id)
            refreshTags()
        } catch {
            onError(error.localizedDescription)
        }
        tagToDelete = nil
    }
}

// MARK: - Identifiable conformance for sheet presentation

extension TagCategory: @retroactive Identifiable {}
