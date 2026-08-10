import Foundation
import SwiftData
import TaggingCore

/// Audit scope: tagged-mode entries with a final image (design §7).
struct AuditResult: Sendable {
    let totalEntries: Int
    let auditedEntries: Int
    let excludedNoFinal: Int
    let excludedNotTagged: Int
    let categoryReports: [CategoryReport]

    var denominatorDescription: String {
        var parts: [String] = []
        if excludedNoFinal > 0 { parts.append("\(excludedNoFinal) not finalized") }
        if excludedNotTagged > 0 { parts.append("\(excludedNotTagged) not tag-captioned") }
        let excluded = parts.isEmpty ? "" : "; \(parts.joined(separator: ", "))"
        return "\(auditedEntries) of \(totalEntries) entries\(excluded)"
    }
}

struct CategoryReport: Identifiable, Sendable {
    let category: TagCategory
    let coveragePercent: Double          // % of audited entries with any tag in this category
    let tagFrequencies: [TagFrequency]   // individual tag frequencies
    let highThresholdExceeded: Bool
    let lowThresholdBelow: Bool
    let isPartialCoverage: Bool          // not 0% and not 100%

    var id: UUID { category.id }
}

struct TagFrequency: Identifiable, Sendable {
    let tagID: UUID
    let canonicalString: String
    let count: Int
    let percent: Double
    let aboveHigh: Bool
    let belowLow: Bool

    var id: UUID { tagID }
}

struct AuditService {
    let document: LoRAForgeDocument
    let modelContext: ModelContext

    func audit() -> AuditResult {
        let catRepo = SwiftDataCategoryRepository(modelContext: modelContext)
        let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
        let allCats = (try? catRepo.allCategories()) ?? []
        let allTags = (try? tagRepo.allTags()) ?? []
        let tagByID = Dictionary(allTags.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        let totalEntries = document.entries.count

        // Scope: tagged-mode entries with a final image
        let audited = document.entries.filter { entry in
            entry.captionMode == .tagged && entry.finalImage != nil
        }
        let auditedCount = audited.count
        let noFinal = document.entries.filter { $0.finalImage == nil }.count
        let notTagged = document.entries.filter { $0.captionMode != .tagged && $0.finalImage != nil }.count

        guard auditedCount > 0 else {
            return AuditResult(
                totalEntries: totalEntries, auditedEntries: 0,
                excludedNoFinal: noFinal, excludedNotTagged: notTagged,
                categoryReports: []
            )
        }

        // Build enabled categories in project order
        var enabledCats: [TagCategory] = []
        for id in document.metadata.categoryOrder {
            if var cat = allCats.first(where: { $0.id == id }) {
                if document.metadata.disabledCategories.contains(id) { cat.isEnabled = false }
                if cat.isEnabled { enabledCats.append(cat) }
            }
        }
        for cat in allCats where !document.metadata.categoryOrder.contains(cat.id) {
            if !document.metadata.disabledCategories.contains(cat.id) && cat.isEnabled {
                enabledCats.append(cat)
            }
        }

        var reports: [CategoryReport] = []

        for category in enabledCats {
            let catTagIDs = Set(allTags.filter { $0.categoryID == category.id }.map(\.id))

            // Count entries that have any tag in this category
            var entriesWithTag = 0
            var tagCounts: [UUID: Int] = [:]

            for entry in audited {
                let catAssignments = entry.tagAssignments.filter { catTagIDs.contains($0.tagID) }
                if !catAssignments.isEmpty {
                    entriesWithTag += 1
                    for assignment in catAssignments {
                        tagCounts[assignment.tagID, default: 0] += 1
                    }
                }
            }

            let coveragePercent = Double(entriesWithTag) / Double(auditedCount) * 100.0

            let frequencies: [TagFrequency] = tagCounts.map { tagID, count in
                let percent = Double(count) / Double(auditedCount) * 100.0
                let tag = tagByID[tagID]
                return TagFrequency(
                    tagID: tagID,
                    canonicalString: tag?.canonicalString ?? "unknown",
                    count: count,
                    percent: percent,
                    aboveHigh: percent >= category.highThreshold * 100,
                    belowLow: percent > 0 && percent <= category.lowThreshold * 100
                )
            }.sorted { $0.percent > $1.percent }

            let isPartial = coveragePercent > 0 && coveragePercent < 100

            reports.append(CategoryReport(
                category: category,
                coveragePercent: coveragePercent,
                tagFrequencies: frequencies,
                highThresholdExceeded: frequencies.contains(where: \.aboveHigh),
                lowThresholdBelow: frequencies.contains(where: \.belowLow),
                isPartialCoverage: isPartial
            ))
        }

        return AuditResult(
            totalEntries: totalEntries,
            auditedEntries: auditedCount,
            excludedNoFinal: noFinal,
            excludedNotTagged: notTagged,
            categoryReports: reports
        )
    }
}
