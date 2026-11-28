import SwiftUI
import TaggingCore

/// Applies tags in chosen categories to every entry, or clears those categories everywhere.
///
/// Each category row has an Apply checkbox and a Remove all checkbox over the same tag row the
/// caption editor uses. Picking a tag ticks Apply. Locked entries are never changed.
struct BulkTagEditorView: View {
    @Binding var document: ProjectDocument
    let tagFrequency: [UUID: Int]
    let onChanged: () -> Void

    @Environment(TagRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    @State private var categories: [TagCategory] = []
    @State private var tagsByCategory: [UUID: [Tag]] = [:]
    /// The tags picked in the sheet, across all categories, as the tag rows edit them.
    @State private var picks: [AssignmentDocument] = []
    @State private var applying: Set<UUID> = []
    @State private var removing: Set<UUID> = []
    @State private var confirming = false

    private var enabledCategories: [TagCategory] {
        ProjectCategories.resolve(categories, order: document.categoryOrder, enabled: document.categoryEnabled)
            .filter(\.isEnabled)
    }

    private var tagCategory: [UUID: UUID] {
        tagsByCategory.reduce(into: [UUID: UUID]()) { index, pair in
            for tag in pair.value { index[tag.id] = pair.key }
        }
    }

    private func pickedTags(in categoryID: UUID) -> [UUID] {
        let index = tagCategory
        return picks.filter { index[$0.tagID] == categoryID }
            .sorted { $0.selectionOrder < $1.selectionOrder }
            .map(\.tagID)
    }

    private var edit: BulkTagEdit {
        var instructions: [UUID: BulkTagEdit.Instruction] = [:]
        for category in enabledCategories {
            if removing.contains(category.id) {
                instructions[category.id] = .removeAll
            } else if applying.contains(category.id) {
                let tags = pickedTags(in: category.id)
                if !tags.isEmpty { instructions[category.id] = .apply(tags) }
            }
        }
        return BulkTagEdit(instructions: instructions, categories: enabledCategories, tagCategory: tagCategory)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Tick Apply to add the picked tags to every entry, or Remove all to clear the category on every entry. Single-select categories are replaced; multi-select categories are added to. Locked entries are not changed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(enabledCategories) { category in
                            row(category)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Bulk tag editor")
            .frame(minWidth: 1000, idealWidth: 1100, minHeight: 700, idealHeight: 800)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply…") { confirming = true }
                        .disabled(edit.isEmpty)
                }
            }
            .alert("Apply tag changes?", isPresented: $confirming) {
                let summary = edit.summary(of: document.entries)
                if summary.changed > 0 {
                    Button("Apply") { apply() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(summaryText(edit.summary(of: document.entries)))
            }
        }
        .onAppear(perform: reloadTags)
    }

    private func row(_ category: TagCategory) -> some View {
        let isRemoving = removing.contains(category.id)
        return HStack(alignment: .top, spacing: 12) {
            Toggle("Apply", isOn: Binding(
                get: { applying.contains(category.id) || isRemoving },
                set: { on in
                    if on { applying.insert(category.id) } else {
                        applying.remove(category.id)
                        removing.remove(category.id)
                    }
                }
            ))
            .help("Change this category on every entry")

            Toggle("Remove all", isOn: Binding(
                get: { isRemoving },
                set: { on in
                    if on {
                        removing.insert(category.id)
                        let index = tagCategory
                        picks.removeAll { index[$0.tagID] == category.id }
                    } else {
                        removing.remove(category.id)
                    }
                }
            ))
            .help("Remove every tag in this category from every entry")

            TagRowView(
                category: category,
                assignments: $picks,
                availableTags: tagsByCategory[category.id] ?? [],
                tagFrequency: tagFrequency,
                repo: repo,
                onChanged: {
                    reloadTags()
                    if !pickedTags(in: category.id).isEmpty { applying.insert(category.id) }
                }
            )
            .disabled(isRemoving)
            .opacity(isRemoving ? 0.4 : 1)
        }
        #if os(macOS)
        .toggleStyle(.checkbox)
        #endif
        .padding(.horizontal)
    }

    private func summaryText(_ summary: BulkTagEdit.Summary) -> String {
        guard summary.changed > 0 else {
            return summary.lockedSkipped > 0
                ? "Only locked entries would change, and locked entries are not edited."
                : "No entries would change."
        }
        var parts = ["Will change tags on \(entries(summary.changed))."]
        parts.append(summary.captionsRewritten == 0
            ? "No captions will be rewritten."
            : "\(captions(summary.captionsRewritten)) will be rewritten.")
        let untagged = summary.changed - summary.captionsRewritten
        if untagged > 0 {
            parts.append("\(entries(untagged)) in Manual or Auto mode keep their caption text.")
        }
        if summary.lockedSkipped > 0 {
            parts.append("\(entries(summary.lockedSkipped, locked: true)) skipped.")
        }
        return parts.joined(separator: " ")
    }

    private func entries(_ count: Int, locked: Bool = false) -> String {
        let noun = count == 1 ? "entry" : "entries"
        let verb = locked ? (count == 1 ? " is" : " are") : ""
        return "\(count)\(locked ? " locked" : "") \(noun)\(verb)"
    }

    private func captions(_ count: Int) -> String {
        "\(count) caption\(count == 1 ? "" : "s")"
    }

    private func apply() {
        var entries = document.entries
        let changed = edit.apply(to: &entries)
        CaptionRefresher(document: document, repo: repo).refresh(&entries, only: changed)
        document.entries = entries
        onChanged()
        dismiss()
    }

    private func reloadTags() {
        categories = (try? repo.allCategories()) ?? []
        for category in categories {
            tagsByCategory[category.id] = (try? repo.tags(in: category.id)) ?? []
        }
    }
}
