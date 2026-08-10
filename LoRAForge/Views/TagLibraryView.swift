import SwiftUI
import SwiftData
import TaggingCore

struct TagLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedCategoryID: UUID?
    @State private var categories: [TagCategory] = []

    // Add category
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategorySelectMode: SelectMode = .single
    @State private var newCategoryPrefix = ""

    // Delete category
    @State private var pendingDeleteCategory: TagCategory?
    @State private var showDeleteConfirmation = false

    // Reorder
    @State private var showReorderWarning = false
    @State private var pendingReorder: (from: IndexSet, to: Int)?

    var body: some View {
        NavigationSplitView {
            categoryList
                .navigationTitle("Tag library")
                .withSettingsAccess()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showAddCategory = true } label: {
                            Label("Add category", systemImage: "plus")
                        }
                    }
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                    #endif
                }
        } detail: {
            if let id = selectedCategoryID,
               categories.contains(where: { $0.id == id }) {
                CategoryDetailView(categoryID: id, onChanged: loadCategories)
            } else {
                ContentUnavailableView(
                    "Select a category",
                    systemImage: "tag",
                    description: Text("Choose a category to manage its tags.")
                )
            }
        }
        .task { loadCategories() }
        .sheet(isPresented: $showAddCategory) { addCategorySheet }
        .confirmationDialog(
            "Delete \(pendingDeleteCategory?.name ?? "")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Disable instead") { disableInstead() }
            Button("Cancel", role: .cancel) { pendingDeleteCategory = nil }
        } message: {
            Text("This will permanently remove the category and all its tags. \(affectedCountDescription)")
        }
        .alert("Reorder categories?", isPresented: $showReorderWarning) {
            Button("Reorder") { applyReorder() }
            Button("Cancel", role: .cancel) { pendingReorder = nil; loadCategories() }
        } message: {
            Text("This will change the order of rendered captions. \(affectedCountDescription)")
        }
    }

    // MARK: - Category List

    private var categoryList: some View {
        List(selection: $selectedCategoryID) {
            ForEach(categories) { category in
                categoryRow(category)
                    .tag(category.id)
                    .contextMenu { categoryContextMenu(category) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !category.isBuiltIn {
                            Button(role: .destructive) {
                                pendingDeleteCategory = category
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        Button {
                            toggleEnabled(category)
                        } label: {
                            Label(
                                category.isEnabled ? "Disable" : "Enable",
                                systemImage: category.isEnabled ? "eye.slash" : "eye"
                            )
                        }
                        .tint(category.isEnabled ? .orange : .green)
                    }
            }
            .onMove { from, to in
                guard !from.contains(0), to != 0 else { return }
                pendingReorder = (from, to)
                showReorderWarning = true
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: TagCategory) -> some View {
        HStack {
            Image(systemName: category.isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(category.isEnabled ? .green : .secondary)
                .imageScale(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .fontWeight(category.id == BuiltInCategories.subjectID ? .semibold : .regular)
                if let prefix = category.prefix, !prefix.isEmpty {
                    Text(prefix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(category.selectMode == .single ? "single" : "multi")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func categoryContextMenu(_ category: TagCategory) -> some View {
        Button {
            toggleEnabled(category)
        } label: {
            Label(
                category.isEnabled ? "Disable" : "Enable",
                systemImage: category.isEnabled ? "eye.slash" : "eye"
            )
        }
        if !category.isBuiltIn {
            Divider()
            Button(role: .destructive) {
                pendingDeleteCategory = category
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Add Category Sheet

    private var addCategorySheet: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $newCategoryName)
                Picker("Select mode", selection: $newCategorySelectMode) {
                    Text("Single").tag(SelectMode.single)
                    Text("Multi").tag(SelectMode.multi)
                }
                TextField("Prefix (optional)", text: $newCategoryPrefix)
            }
            .navigationTitle("New category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddCategory = false
                        resetAddForm()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addCategory() }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadCategories() {
        let repo = SwiftDataCategoryRepository(modelContext: modelContext)
        categories = (try? repo.allCategories()) ?? []
    }

    private func addCategory() {
        let prefix = newCategoryPrefix.trimmingCharacters(in: .whitespaces)
        let nextPosition = (categories.map(\.position).max() ?? -1) + 1
        let category = TagCategory(
            name: newCategoryName.trimmingCharacters(in: .whitespaces),
            selectMode: newCategorySelectMode,
            prefix: prefix.isEmpty ? nil : prefix,
            position: nextPosition
        )
        let repo = SwiftDataCategoryRepository(modelContext: modelContext)
        try? repo.save(category)
        showAddCategory = false
        resetAddForm()
        loadCategories()
        selectedCategoryID = category.id
    }

    private func resetAddForm() {
        newCategoryName = ""
        newCategorySelectMode = .single
        newCategoryPrefix = ""
    }

    private func toggleEnabled(_ category: TagCategory) {
        var updated = category
        updated.isEnabled.toggle()
        let repo = SwiftDataCategoryRepository(modelContext: modelContext)
        try? repo.save(updated)
        loadCategories()
    }

    private func performDelete() {
        guard let category = pendingDeleteCategory else { return }
        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
        if let tags = try? tagRepo.tags(inCategory: category.id) {
            for tag in tags { try? tagRepo.deleteTag(id: tag.id) }
        }
        let repo = SwiftDataCategoryRepository(modelContext: modelContext)
        try? repo.delete(categoryID: category.id)
        if selectedCategoryID == category.id { selectedCategoryID = nil }
        pendingDeleteCategory = nil
        loadCategories()
    }

    private func disableInstead() {
        guard let category = pendingDeleteCategory else { return }
        var updated = category
        updated.isEnabled = false
        let repo = SwiftDataCategoryRepository(modelContext: modelContext)
        try? repo.save(updated)
        pendingDeleteCategory = nil
        loadCategories()
    }

    private func applyReorder() {
        guard let (from, to) = pendingReorder else { return }
        var reordered = categories
        reordered.move(fromOffsets: from, toOffset: to)
        let repo = SwiftDataCategoryRepository(modelContext: modelContext)
        for (index, var cat) in reordered.enumerated() {
            cat.position = index
            try? repo.save(cat)
        }
        pendingReorder = nil
        loadCategories()
    }

    private var affectedCountDescription: String {
        let repo = SwiftDataKnownProjectsRepository(modelContext: modelContext)
        let projectCount = (try? repo.allProjects().count) ?? 0
        if projectCount == 0 { return "No known projects affected." }
        return "0 images across \(projectCount) known projects."
    }
}
