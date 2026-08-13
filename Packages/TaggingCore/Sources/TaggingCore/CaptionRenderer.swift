import Foundation

public enum CaptionRenderer {

    /// Renders a caption string from tag assignments against a set of categories.
    ///
    /// Categories are sorted by position. Disabled categories and categories with
    /// no assignments are omitted. Multi-select values are joined with " and " in
    /// selection order. Prefixes are prepended when present.
    public static func render(
        assignments: [TagAssignment],
        tags: [UUID: Tag],
        categories: [TagCategory]
    ) -> String {
        let enabledCategories = categories
            .filter(\.isEnabled)
            .sorted { $0.position < $1.position }

        var segments: [String] = []

        for category in enabledCategories {
            let categoryAssignments = assignments
                .filter { assignment in
                    guard let tag = tags[assignment.tagID] else { return false }
                    return tag.categoryID == category.id
                }
                .sorted { $0.selectionOrder < $1.selectionOrder }

            guard !categoryAssignments.isEmpty else { continue }

            let tagStrings = categoryAssignments.compactMap { tags[$0.tagID]?.canonicalString }
            guard !tagStrings.isEmpty else { continue }

            let joined: String
            switch category.selectMode {
            case .single:
                joined = tagStrings[0]
            case .multi:
                joined = tagStrings.joined(separator: " and ")
            }

            if let prefix = category.prefix, !prefix.isEmpty {
                segments.append("\(prefix) \(joined)")
            } else {
                segments.append(joined)
            }
        }

        return segments.joined(separator: ", ")
    }
}
