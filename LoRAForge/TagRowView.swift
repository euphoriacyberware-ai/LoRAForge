import SwiftUI
import TaggingCore

// The per-category tag row shared by the caption editor and the bulk tag editor: assigned
// tags as removable chips, a type-ahead field that can create tags, and frequently used tags.

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, position) in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews).positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

// MARK: - Tag Row

struct TagRowView: View {
    let category: TagCategory
    @Binding var assignments: [AssignmentDocument]
    let availableTags: [Tag]
    let tagFrequency: [UUID: Int]
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

    private var quickTags: [Tag] {
        let assignedIDs = Set(assignedTags.map(\.id))
        return Array(availableTags
            .filter { !assignedIDs.contains($0.id) && (tagFrequency[$0.id] ?? 0) > 0 }
            .sorted { (tagFrequency[$0.id] ?? 0) > (tagFrequency[$1.id] ?? 0) }
            .prefix(Self.quickTagCount))
    }

    /// How many frequently used tags show under an empty category row.
    private static let quickTagCount = 8

    private var categoryLabel: String {
        if let prefix = category.prefix, !prefix.isEmpty {
            return "\(prefix) \(category.name)"
        }
        return category.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                Text(categoryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .trailing)

                FlowLayout(spacing: 4) {
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
            }

            // Quick-tag chips
            if !quickTags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(quickTags) { tag in
                        Button {
                            selectTag(tag)
                        } label: {
                            Text(tag.canonicalString)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 128)
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
                .padding(.leading, 132)
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
