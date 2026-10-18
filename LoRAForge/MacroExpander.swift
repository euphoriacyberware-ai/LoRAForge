import Foundation

/// Expands `<Name>` references in prompt text using a project's macros.
///
/// Names match case-insensitively after trimming. Expansion is single-pass: a
/// reference inside a macro's own text is sent literally. Unresolved references
/// are left in the text unchanged.
enum MacroExpander {

    struct Expansion: Equatable {
        var text: String
        /// Referenced names with no matching macro, as written, in first-seen order.
        var unresolved: [String]
        /// Referenced names whose macro has no text, as written, in first-seen order.
        var empty: [String]

        var hasWarnings: Bool { !unresolved.isEmpty || !empty.isEmpty }
    }

    enum NameError: Error, Equatable {
        case empty
        case invalidCharacters
        case duplicate

        var message: String {
            switch self {
            case .empty: return "Name cannot be empty"
            case .invalidCharacters: return "Name cannot contain <, > or line breaks"
            case .duplicate: return "Another macro already has this name"
            }
        }
    }

    private static let pattern = /<([^<>\n]+)>/

    /// Normalized lookup key for a macro name.
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Referenced names in order of first appearance, de-duplicated by key.
    static func references(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for match in text.matches(of: pattern) {
            let name = String(match.output.1).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, seen.insert(key(name)).inserted else { continue }
            result.append(name)
        }
        return result
    }

    static func expand(_ text: String, macros: [ProjectMacro]) -> Expansion {
        let lookup = Dictionary(macros.map { (key($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        var unresolved: [String] = []
        var empty: [String] = []
        var seen = Set<String>()

        let expanded = text.replacing(pattern) { match -> String in
            let name = String(match.output.1).trimmingCharacters(in: .whitespaces)
            let k = key(name)
            guard let macro = lookup[k] else {
                if seen.insert(k).inserted { unresolved.append(name) }
                return String(match.output.0)
            }
            if macro.text.isEmpty, seen.insert(k).inserted { empty.append(name) }
            return macro.text
        }
        return Expansion(text: expanded, unresolved: unresolved, empty: empty)
    }

    /// Validates a proposed name against the other macros in the project.
    static func validateName(_ name: String, existing: [ProjectMacro], excluding id: UUID? = nil) -> NameError? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .empty }
        if trimmed.contains(where: { $0 == "<" || $0 == ">" || $0.isNewline }) { return .invalidCharacters }
        let k = key(trimmed)
        if existing.contains(where: { $0.id != id && key($0.name) == k }) { return .duplicate }
        return nil
    }

    /// Number of entries whose prompt or negative prompt references `name`.
    static func usageCount(of name: String, in entries: [EntryDocument]) -> Int {
        let k = key(name)
        return entries.filter { entry in
            (references(in: entry.generationPrompt) + references(in: entry.generationNegativePrompt))
                .contains { key($0) == k }
        }.count
    }

    /// Names referenced by any entry that no macro defines, in first-seen order.
    static func undefinedReferences(in entries: [EntryDocument], macros: [ProjectMacro]) -> [String] {
        let defined = Set(macros.map { key($0.name) })
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            for name in references(in: entry.generationPrompt) + references(in: entry.generationNegativePrompt) {
                let k = key(name)
                guard !defined.contains(k), seen.insert(k).inserted else { continue }
                result.append(name)
            }
        }
        return result
    }

    /// Appends an empty macro for every name the prompts reference that the
    /// project doesn't define. Returns the names added.
    @discardableResult
    static func addStubs(for prompts: [String], to macros: inout [ProjectMacro]) -> [String] {
        var defined = Set(macros.map { key($0.name) })
        var added: [String] = []
        for prompt in prompts {
            for name in references(in: prompt) where defined.insert(key(name)).inserted {
                macros.append(ProjectMacro(name: name))
                added.append(name)
            }
        }
        return added
    }
}
