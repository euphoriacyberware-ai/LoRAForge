import Foundation
import TaggingCore

/// Re-renders tagged-mode captions after their tags or the library changed.
///
/// Unlocked entries get a fresh caption. Locked captions are frozen text and are never
/// rewritten; they only have their drift flag recomputed.
@MainActor
struct CaptionRefresher {
    let tags: [UUID: Tag]
    let categories: [TagCategory]

    /// Reads the project's enabled categories, in project order, and every tag from the library.
    init(document: ProjectDocument, repo: TagRepository) {
        let all = (try? repo.allCategories()) ?? []
        categories = ProjectCategories.resolve(all, order: document.categoryOrder, enabled: document.categoryEnabled)
            .filter(\.isEnabled)
        tags = all.flatMap { (try? repo.tags(in: $0.id)) ?? [] }
            .reduce(into: [UUID: Tag]()) { $0[$1.id] = $1 }
    }

    /// Refreshes the given entries, or every entry when `ids` is nil.
    func refresh(_ entries: inout [EntryDocument], only ids: Set<UUID>? = nil) {
        for index in entries.indices {
            let entry = entries[index]
            guard entry.captionMode == .tagged, ids?.contains(entry.id) ?? true else { continue }
            let rendered = CaptionRenderer.render(
                assignments: entry.assignments.map {
                    TagAssignment(tagID: $0.tagID, selectionOrder: $0.selectionOrder)
                },
                tags: tags,
                categories: categories
            )
            if entry.isLocked {
                entries[index].driftDetected = (rendered != entry.lockedCaptionText)
            } else {
                entries[index].captionPreviewText = rendered
                entries[index].driftDetected = false
            }
        }
    }
}
