import SwiftUI
import SwiftData
import TaggingCore

struct CategoryDetailView: View {
    let categoryID: UUID
    var onChanged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var category: TagCategory?
    @State private var tags: [Tag] = []

    // Editing
    @State private var editName = ""
    @State private var editPrefix = ""
    @State private var originalPrefix = ""
    @State private var editHighThreshold = 0.70
    @State private var editLowThreshold = 0.10

    // Tag creation
    @State private var newTagText = ""
    @State private var showExactMatchAlert = false
    @State private var showNearMatchAlert = false
    @State private var nearMatches: [NearMatch] = []
    @State private var pendingTagText = ""

    // Tag deletion
    @State private var pendingDeleteTag: Tag?
    @State private var showDeleteTagAlert = false

    // Prefix warning
    @State private var showPrefixWarning = false

    // Search
    @State private var tagSearchText = ""

    var body: some View {
        Group {
            if let category {
                categoryContent(category)
            } else {
                ContentUnavailableView("Category not found", systemImage: "questionmark.circle")
            }
        }
        .task { load() }
        .onChange(of: categoryID) { _, _ in load() }
        .navigationTitle(category?.name ?? "")
    }

    // MARK: - Content

    @ViewBuilder
    private func categoryContent(_ category: TagCategory) -> some View {
        Form {
            propertiesSection(category)
            if category.id == BuiltInCategories.subjectID {
                Section("Tags") {
                    Text("Subject tags are project-specific and managed within each project.")
                        .foregroundStyle(.secondary)
                }
            } else {
                tagsSection
            }
        }
        .formStyle(.grouped)
        .searchable(text: $tagSearchText, prompt: "Filter tags")
        .alert("Tag already exists", isPresented: $showExactMatchAlert) {
            Button("OK") { newTagText = "" }
        } message: {
            Text("A tag with this name already exists in this category.")
        }
        .confirmationDialog(
            "Similar tags found",
            isPresented: $showNearMatchAlert,
            titleVisibility: .visible
        ) {
            Button("Create '\(pendingTagText)' anyway") { forceCreateTag() }
            Button("Cancel", role: .cancel) { pendingTagText = "" }
        } message: {
            let list = nearMatches
                .map { "\($0.tag.canonicalString) (\(Int($0.similarity * 100))%)" }
                .joined(separator: "\n")
            Text("Similar tags in this category:\n\(list)")
        }
        .alert("Change prefix?", isPresented: $showPrefixWarning) {
            Button("Change") { savePrefix() }
            Button("Cancel", role: .cancel) { editPrefix = originalPrefix }
        } message: {
            Text("Changing the prefix will affect how captions render. \(affectedCountDescription)")
        }
        .confirmationDialog(
            "Delete tag?",
            isPresented: $showDeleteTagAlert,
            titleVisibility: .visible
        ) {
            if let tag = pendingDeleteTag {
                Button("Delete '\(tag.canonicalString)'", role: .destructive) {
                    performDeleteTag()
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteTag = nil }
        } message: {
            Text("This tag will be removed from the library. \(affectedCountDescription)")
        }
    }

    // MARK: - Properties

    @ViewBuilder
    private func propertiesSection(_ category: TagCategory) -> some View {
        Section("Properties") {
            TextField("Name", text: $editName)
                .onSubmit { saveName() }

            if category.id != BuiltInCategories.subjectID {
                TextField("Prefix", text: $editPrefix, prompt: Text("None"))
                    .onSubmit {
                        if editPrefix != originalPrefix { showPrefixWarning = true }
                    }
            }

            LabeledContent("Select mode") {
                Text(category.selectMode == .single ? "Single" : "Multi")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("High threshold") {
                HStack {
                    Slider(value: $editHighThreshold, in: 0...1, step: 0.05)
                        .frame(maxWidth: 200)
                    Text("\(Int(editHighThreshold * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .onChange(of: editHighThreshold) { _, _ in saveThresholds() }

            LabeledContent("Low threshold") {
                HStack {
                    Slider(value: $editLowThreshold, in: 0...1, step: 0.05)
                        .frame(maxWidth: 200)
                    Text("\(Int(editLowThreshold * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .onChange(of: editLowThreshold) { _, _ in saveThresholds() }
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        Section("Tags (\(tags.count))") {
            HStack {
                TextField("New tag", text: $newTagText)
                    .onSubmit { createTag() }
                Button { createTag() } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderless)
            }

            if filteredTags.isEmpty && !tagSearchText.isEmpty {
                Text("No tags match '\(tagSearchText)'")
                    .foregroundStyle(.secondary)
            }

            ForEach(filteredTags) { tag in
                Text(tag.canonicalString)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeleteTag = tag
                            showDeleteTagAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingDeleteTag = tag
                            showDeleteTagAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private var filteredTags: [Tag] {
        let sorted = tags.sorted {
            $0.canonicalString.localizedCaseInsensitiveCompare($1.canonicalString) == .orderedAscending
        }
        if tagSearchText.isEmpty { return sorted }
        return sorted.filter {
            $0.canonicalString.localizedCaseInsensitiveContains(tagSearchText)
        }
    }

    // MARK: - Data

    private func load() {
        let catRepo = SwiftDataCategoryRepository(modelContext: modelContext)
        category = try? catRepo.category(byID: categoryID)
        if let cat = category {
            editName = cat.name
            editPrefix = cat.prefix ?? ""
            originalPrefix = cat.prefix ?? ""
            editHighThreshold = cat.highThreshold
            editLowThreshold = cat.lowThreshold
        }
        loadTags()
    }

    private func loadTags() {
        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
        tags = (try? tagRepo.tags(inCategory: categoryID)) ?? []
    }

    // MARK: - Category Actions

    private func saveName() {
        guard var cat = category else { return }
        let trimmed = editName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != cat.name else {
            editName = cat.name
            return
        }
        cat.name = trimmed
        let repo = SwiftDataCategoryRepository(modelContext: modelContext)
        try? repo.save(cat)
        category = cat
        onChanged()
    }

    private func savePrefix() {
        guard var cat = category else { return }
        let trimmed = editPrefix.trimmingCharacters(in: .whitespaces)
        cat.prefix = trimmed.isEmpty ? nil : trimmed
        let repo = SwiftDataCategoryRepository(modelContext: modelContext)
        try? repo.save(cat)
        category = cat
        originalPrefix = editPrefix
        onChanged()
    }

    private func saveThresholds() {
        guard var cat = category else { return }
        cat.highThreshold = editHighThreshold
        cat.lowThreshold = editLowThreshold
        let repo = SwiftDataCategoryRepository(modelContext: modelContext)
        try? repo.save(cat)
        category = cat
    }

    // MARK: - Tag Actions

    private func createTag() {
        let text = newTagText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
        let existing = (try? tagRepo.tags(inCategory: categoryID)) ?? []
        let result = DuplicateDetector.check(text, against: existing)

        switch result {
        case .exactMatch:
            showExactMatchAlert = true
        case .nearMatches(let matches):
            nearMatches = matches
            pendingTagText = text
            showNearMatchAlert = true
        case .noMatch:
            _ = try? tagRepo.createTag(canonicalString: text, inCategory: categoryID)
            newTagText = ""
            loadTags()
        }
    }

    private func forceCreateTag() {
        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
        _ = try? tagRepo.createTag(canonicalString: pendingTagText, inCategory: categoryID)
        newTagText = ""
        pendingTagText = ""
        loadTags()
    }

    private func performDeleteTag() {
        guard let tag = pendingDeleteTag else { return }
        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
        try? tagRepo.deleteTag(id: tag.id)
        pendingDeleteTag = nil
        loadTags()
    }

    private var affectedCountDescription: String {
        let repo = SwiftDataKnownProjectsRepository(modelContext: modelContext)
        let projectCount = (try? repo.allProjects().count) ?? 0
        if projectCount == 0 { return "No known projects affected." }
        return "0 images across \(projectCount) known projects."
    }
}
