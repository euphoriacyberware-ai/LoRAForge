import Foundation

/// Applies a project's category settings on top of the global category set.
///
/// Order and enabled state are two-level (tagging design §3, §7): the app holds defaults,
/// and each project snapshots and overrides them. `TagCategory.position` and `isEnabled`
/// carry the app-level values, so categories must be resolved against the project before
/// anything that reads those fields — `CaptionRenderer` in particular — sees them.
public enum ProjectCategories {

    /// The global categories as this project sees them: in project order, with `position`
    /// set to the index in `order` and `isEnabled` taken from the project's override
    /// (enabled when the project has no entry). Categories not in `order` are omitted.
    public static func resolve(
        _ categories: [TagCategory],
        order: [UUID],
        enabled: [UUID: Bool]
    ) -> [TagCategory] {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.enumerated().compactMap { index, id in
            guard var category = byID[id] else { return nil }
            category.position = index
            category.isEnabled = enabled[id] ?? true
            return category
        }
    }
}
