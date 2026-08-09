import Foundation

public struct CaptionRenderer: Sendable {

    /// Renders a caption string from tag assignments against a schema of tags and categories.
    ///
    /// Categories are emitted in position order. Disabled categories and categories with no
    /// assignments are omitted entirely — no empty segment, no stray prefix. Multi-select
    /// categories join values with " and " in selection order. Tag text renders verbatim.
    public static func render(
        assignments: [TagAssignment],
        tags: [Tag],
        categories: [TagCategory]
    ) -> String {
        let tagsByID = Dictionary(
            tags.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Group assignments by category
        var assignmentsByCategory: [UUID: [TagAssignment]] = [:]
        for assignment in assignments {
            guard let tag = tagsByID[assignment.tagID] else { continue }
            assignmentsByCategory[tag.categoryID, default: []].append(assignment)
        }

        // Enabled categories in position order
        let sortedCategories = categories
            .filter(\.isEnabled)
            .sorted { $0.position < $1.position }

        var segments: [String] = []

        for category in sortedCategories {
            guard let catAssignments = assignmentsByCategory[category.id],
                  !catAssignments.isEmpty else {
                continue
            }

            let values = catAssignments
                .sorted { $0.selectionOrder < $1.selectionOrder }
                .compactMap { tagsByID[$0.tagID]?.canonicalString }

            guard !values.isEmpty else { continue }

            let joined = values.joined(separator: " and ")

            if let prefix = category.prefix, !prefix.isEmpty {
                segments.append("\(prefix) \(joined)")
            } else {
                segments.append(joined)
            }
        }

        return segments.joined(separator: ", ")
    }
}
