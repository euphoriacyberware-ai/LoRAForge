import Foundation
import TaggingCore
import DTConfigEditorKit
import DTConfigBridge
import DrawThingsClient

// Project-wide edits from the Dataset Builder's Bulk actions menu. Kept apart from the views
// so the rules are unit-tested: each edit can report what it would change (for the warning
// shown before applying) and apply itself to the project's entries.

// MARK: - Demotion

nonisolated enum BulkDemotion: CaseIterable, Sendable {
    case finalToShortlist
    case shortlistToCandidate
    case candidateToDiscarded

    var from: ImageRank {
        switch self {
        case .finalToShortlist: .final
        case .shortlistToCandidate: .shortlist
        case .candidateToDiscarded: .candidate
        }
    }

    var to: ImageRank {
        switch self {
        case .finalToShortlist: .shortlist
        case .shortlistToCandidate: .candidate
        case .candidateToDiscarded: .discarded
        }
    }

    /// Images in the `from` rank across all entries.
    func count(in entries: [EntryDocument]) -> Int {
        entries.reduce(0) { $0 + $1.images.filter { $0.rank == from }.count }
    }

    /// Entries holding at least one image in the `from` rank.
    func entryCount(in entries: [EntryDocument]) -> Int {
        entries.filter { $0.images.contains { $0.rank == from } }.count
    }

    func apply(to entries: inout [EntryDocument]) {
        for e in entries.indices {
            for i in entries[e].images.indices where entries[e].images[i].rank == from {
                entries[e].images[i].rank = to
            }
        }
    }
}

// MARK: - Tags

nonisolated struct BulkTagEdit: Sendable {
    enum Instruction: Equatable, Sendable {
        /// Add these tags (single-select categories: replace with the first).
        case apply([UUID])
        /// Remove every tag in the category.
        case removeAll
    }

    struct Summary: Equatable, Sendable {
        /// Unlocked entries whose tags will change.
        var changed: Int
        /// Of those, Tagged-mode entries: their captions are re-rendered.
        var captionsRewritten: Int
        /// Locked entries that would otherwise have changed, left as they are.
        var lockedSkipped: Int
    }

    /// Instructions per category ID.
    var instructions: [UUID: Instruction]
    /// The categories the instructions refer to, for their select mode.
    var categories: [TagCategory]
    /// Tag ID → category ID, for finding an entry's assignments in a category.
    var tagCategory: [UUID: UUID]

    var isEmpty: Bool { instructions.isEmpty }

    /// The entry's assignments after the edit.
    func edited(_ assignments: [AssignmentDocument]) -> [AssignmentDocument] {
        var result = assignments
        for category in categories {
            guard let instruction = instructions[category.id] else { continue }
            let inCategory = { (a: AssignmentDocument) in tagCategory[a.tagID] == category.id }
            switch instruction {
            case .removeAll:
                result.removeAll(where: inCategory)
            case .apply(let tagIDs):
                guard !tagIDs.isEmpty else { continue }
                if category.selectMode == .single {
                    let tagID = tagIDs[0]
                    let current = result.filter(inCategory)
                    guard current.map(\.tagID) != [tagID] else { continue }
                    result.removeAll(where: inCategory)
                    result.append(AssignmentDocument(tagID: tagID, selectionOrder: 0))
                } else {
                    let existing = Set(result.filter(inCategory).map(\.tagID))
                    var order = (result.filter(inCategory).map(\.selectionOrder).max() ?? -1) + 1
                    for tagID in tagIDs where !existing.contains(tagID) {
                        result.append(AssignmentDocument(tagID: tagID, selectionOrder: order))
                        order += 1
                    }
                }
            }
        }
        return result
    }

    private func wouldChange(_ entry: EntryDocument) -> Bool {
        let before = entry.assignments
        let after = edited(before)
        return before.map(\.tagID) != after.map(\.tagID)
            || before.map(\.selectionOrder) != after.map(\.selectionOrder)
    }

    func summary(of entries: [EntryDocument]) -> Summary {
        var summary = Summary(changed: 0, captionsRewritten: 0, lockedSkipped: 0)
        for entry in entries where wouldChange(entry) {
            if entry.isLocked {
                summary.lockedSkipped += 1
            } else {
                summary.changed += 1
                if entry.captionMode == .tagged { summary.captionsRewritten += 1 }
            }
        }
        return summary
    }

    /// Edits unlocked entries; locked entries are left exactly as they are. Returns the IDs of
    /// the entries that changed.
    @discardableResult
    func apply(to entries: inout [EntryDocument]) -> Set<UUID> {
        var changed = Set<UUID>()
        for i in entries.indices where !entries[i].isLocked && wouldChange(entries[i]) {
            entries[i].assignments = edited(entries[i].assignments)
            changed.insert(entries[i].id)
        }
        return changed
    }
}

// MARK: - Generation settings

@MainActor
struct BulkGenerationEdit {
    /// Configuration keys and the values to write; every other key is left alone.
    var values: [(key: String, value: JSONValue)]

    var isEmpty: Bool { values.isEmpty }

    init(values: [(key: String, value: JSONValue)]) {
        self.values = values
    }

    /// The settings the bulk form offers, in form order, with their display names.
    static let settings: [(key: String, name: String)] = [
        ("model", "Model"), ("sampler", "Sampler"), ("steps", "Steps"), ("guidanceScale", "CFG"),
        ("width", "Width"), ("height", "Height"),
        ("resolutionDependentShift", "Resolution dependent shift"), ("shift", "Shift"),
        ("loras", "LoRAs"), ("refinerModel", "Refiner model"), ("refinerStart", "Refiner start"),
        ("colorCalibration", "Color calibration"),
    ]

    /// The chosen keys with their values taken from `config`, written the way the form writes them.
    init(keys: Set<String>, from config: DrawThingsConfiguration) {
        values = Self.settings.compactMap { setting in
            guard keys.contains(setting.key) else { return nil }
            let value: JSONValue
            switch setting.key {
            case "model": value = .string(config.model)
            case "sampler": value = GenerationSettingsWriter.sampler(config.sampler)
            case "steps": value = GenerationSettingsWriter.int(Int(config.steps))
            case "guidanceScale": value = GenerationSettingsWriter.float(config.guidanceScale)
            case "width": value = GenerationSettingsWriter.int(Int(config.width))
            case "height": value = GenerationSettingsWriter.int(Int(config.height))
            case "resolutionDependentShift": value = .bool(config.resolutionDependentShift)
            case "shift": value = GenerationSettingsWriter.float(config.shift)
            case "loras": value = GenerationSettingsWriter.loras(config.loras)
            case "refinerModel": value = GenerationSettingsWriter.refinerModel(config.refinerModel)
            case "refinerStart": value = GenerationSettingsWriter.float(config.refinerStart)
            case "colorCalibration": value = GenerationSettingsWriter.colorCalibration(config.colorCalibration == .lab)
            default: return nil
            }
            return (setting.key, value)
        }
    }

    /// Display names of the settings being applied, in form order.
    var settingNames: [String] {
        let keys = Set(values.map(\.key))
        return Self.settings.filter { keys.contains($0.key) }.map(\.name)
    }

    /// The entry's configuration JSON after the edit. An empty configuration starts from the
    /// same defaults the entry editor uses.
    func edited(_ json: String) -> String {
        let model: ConfigEditorModel
        if json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model = ConfigEditorModel(DrawThingsConfiguration(), style: .nonDefaultOnly)
        } else {
            model = ConfigEditorModel(text: json)
        }
        for (key, value) in values {
            model.set(key, to: value)
        }
        return model.text
    }

    /// Entries whose configuration would change.
    func changedCount(in entries: [EntryDocument]) -> Int {
        entries.filter { edited($0.generationConfigJSON) != $0.generationConfigJSON }.count
    }

    /// Applies to every entry, locked or not: locking freezes the caption, not the settings.
    func apply(to entries: inout [EntryDocument]) {
        for i in entries.indices {
            entries[i].generationConfigJSON = edited(entries[i].generationConfigJSON)
        }
    }
}
