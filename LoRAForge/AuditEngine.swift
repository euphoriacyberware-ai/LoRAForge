import Foundation
import TaggingCore

struct AuditResult {
    let totalEntries: Int
    let scopedEntries: Int
    let excludedNoFinal: Int
    let excludedNotTagged: Int
    let categoryResults: [CategoryAuditResult]
}

struct CategoryAuditResult: Identifiable {
    let id: UUID
    let categoryName: String
    let selectMode: TagCategory.SelectMode
    let coverage: Double
    let coverageCount: Int
    let tagFrequencies: [TagFrequency]
    let highThreshold: Int
    let lowThreshold: Int

    var isPartialCoverage: Bool {
        coverage > 0 && coverage < 1.0
    }

    struct TagFrequency: Identifiable {
        let id: UUID
        let tagName: String
        let count: Int
        let fraction: Double
        let isAboveHigh: Bool
        let isBelowLow: Bool
    }
}

enum AuditEngine {

    /// Computes audit results over tagged-mode entries with a final image.
    static func audit(
        document: ProjectDocument,
        categories: [TagCategory],
        allTags: [UUID: Tag]
    ) -> AuditResult {
        let totalEntries = document.entries.count

        // Scope: tagged-mode entries with a final image
        let scopedEntries = document.entries.filter {
            $0.captionMode == .tagged && $0.finalImage != nil
        }
        let excludedNoFinal = document.entries.filter { $0.finalImage == nil }.count
        let excludedNotTagged = document.entries.filter {
            $0.captionMode != .tagged && $0.finalImage != nil
        }.count

        let scopedCount = scopedEntries.count
        guard scopedCount > 0 else {
            return AuditResult(
                totalEntries: totalEntries,
                scopedEntries: 0,
                excludedNoFinal: excludedNoFinal,
                excludedNotTagged: excludedNotTagged,
                categoryResults: []
            )
        }

        // Filter to enabled categories in project order
        let enabledCategories: [TagCategory] = document.categoryOrder.compactMap { catID in
            guard document.categoryEnabled[catID] != false else { return nil }
            return categories.first { $0.id == catID }
        }

        var categoryResults: [CategoryAuditResult] = []

        for category in enabledCategories {
            // Find tags belonging to this category
            let categoryTagIDs = Set(allTags.values.filter { $0.categoryID == category.id }.map(\.id))

            // Coverage: how many scoped entries have any tag in this category
            var coverageCount = 0
            var tagCounts: [UUID: Int] = [:]

            for entry in scopedEntries {
                let entryTagIDs = Set(entry.assignments.map(\.tagID))
                let assignedInCategory = entryTagIDs.intersection(categoryTagIDs)

                if !assignedInCategory.isEmpty {
                    coverageCount += 1
                }

                for tagID in assignedInCategory {
                    tagCounts[tagID, default: 0] += 1
                }
            }

            let coverage = Double(coverageCount) / Double(scopedCount)
            let highThreshold = category.highThreshold
            let lowThreshold = category.lowThreshold

            let tagFrequencies: [CategoryAuditResult.TagFrequency] = tagCounts
                .compactMap { (tagID: UUID, count: Int) -> CategoryAuditResult.TagFrequency? in
                    guard let tag = allTags[tagID] else { return nil }
                    let fraction = Double(count) / Double(scopedCount)
                    let percent = fraction * 100
                    return CategoryAuditResult.TagFrequency(
                        id: tagID,
                        tagName: tag.canonicalString,
                        count: count,
                        fraction: fraction,
                        isAboveHigh: percent >= Double(highThreshold),
                        isBelowLow: percent > 0 && percent <= Double(lowThreshold)
                    )
                }
                .sorted { $0.count > $1.count }

            categoryResults.append(CategoryAuditResult(
                id: category.id,
                categoryName: category.name,
                selectMode: category.selectMode,
                coverage: coverage,
                coverageCount: coverageCount,
                tagFrequencies: tagFrequencies,
                highThreshold: highThreshold,
                lowThreshold: lowThreshold
            ))
        }

        return AuditResult(
            totalEntries: totalEntries,
            scopedEntries: scopedCount,
            excludedNoFinal: excludedNoFinal,
            excludedNotTagged: excludedNotTagged,
            categoryResults: categoryResults
        )
    }
}
