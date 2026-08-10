import Foundation
import SwiftData
import TaggingCore

struct ReconciliationResult: Sendable {
    struct CategoryDrift: Sendable {
        let snapshot: CategorySnapshot
        let current: TagCategory
        let prefixChanged: Bool
        let selectModeChanged: Bool
    }

    var missingTags: [TagSnapshot]
    var missingCategories: [CategorySnapshot]
    var driftedCategories: [CategoryDrift]

    var needsAttention: Bool {
        !missingTags.isEmpty || !missingCategories.isEmpty || !driftedCategories.isEmpty
    }

    static let clean = ReconciliationResult(
        missingTags: [], missingCategories: [], driftedCategories: []
    )
}

struct ReconciliationService {
    let modelContext: ModelContext

    /// Compare a project's schema snapshot against the current app-level library.
    /// Returns items that are missing, drifted, or changed.
    func reconcile(snapshot: SchemaSnapshot) -> ReconciliationResult {
        let catRepo = SwiftDataCategoryRepository(modelContext: modelContext)
        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)

        let currentCategories = (try? catRepo.allCategories()) ?? []
        let catByID = Dictionary(
            currentCategories.map { ($0.id, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        let currentTags = (try? tagRepo.allTags()) ?? []
        let tagByID = Dictionary(
            currentTags.map { ($0.id, $0) },
            uniquingKeysWith: { a, _ in a }
        )

        var result = ReconciliationResult.clean

        for snap in snapshot.categories {
            if let current = catByID[snap.id] {
                let prefixChanged = snap.prefix != current.prefix
                let modeChanged = snap.selectMode.toDomain != current.selectMode
                if prefixChanged || modeChanged {
                    result.driftedCategories.append(
                        .init(snapshot: snap, current: current,
                              prefixChanged: prefixChanged, selectModeChanged: modeChanged)
                    )
                }
            } else {
                result.missingCategories.append(snap)
            }
        }

        for snap in snapshot.tags {
            if tagByID[snap.id] == nil {
                result.missingTags.append(snap)
            }
        }

        return result
    }

    /// Import a missing tag into the app-level library, running duplicate detection (design §9.3).
    func importTag(_ snapshot: TagSnapshot) throws -> ImportTagResult {
        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
        let existing = (try? tagRepo.tags(inCategory: snapshot.categoryID)) ?? []
        let check = DuplicateDetector.check(snapshot.canonicalString, against: existing)

        switch check {
        case .exactMatch(let tag):
            return .mappedToExisting(tag)
        case .nearMatches(let matches):
            return .nearMatchesFound(matches)
        case .noMatch:
            let created = try tagRepo.createTag(
                canonicalString: snapshot.canonicalString,
                inCategory: snapshot.categoryID
            )
            return .created(created)
        }
    }

    /// Import a missing category into the app-level library.
    func importCategory(_ snapshot: CategorySnapshot) throws {
        let catRepo = SwiftDataCategoryRepository(modelContext: modelContext)
        let allCats = (try? catRepo.allCategories()) ?? []
        let nextPosition = (allCats.map(\.position).max() ?? -1) + 1
        var category = snapshot.toDomainCategory()
        category.position = nextPosition
        try catRepo.save(category)
    }
}

enum ImportTagResult {
    case created(Tag)
    case mappedToExisting(Tag)
    case nearMatchesFound([NearMatch])
}
