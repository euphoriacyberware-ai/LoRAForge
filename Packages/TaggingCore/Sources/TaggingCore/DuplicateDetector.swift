import Foundation

/// Result of checking a candidate string against the existing tag library.
public enum DuplicateCheckResult: Sendable {
    /// The normalized input exactly matches an existing tag — it IS that tag.
    case exactMatch(Tag)
    /// One or more existing tags are similar above the threshold.
    case nearMatches([NearMatch])
    /// No match found.
    case noMatch
}

/// A tag paired with its similarity score to the candidate string.
public struct NearMatch: Sendable {
    public let tag: Tag
    public let similarity: Double

    public init(tag: Tag, similarity: Double) {
        self.tag = tag
        self.similarity = similarity
    }
}

public struct DuplicateDetector: Sendable {

    // MARK: - Public API

    /// Checks a candidate string against a list of tags (scoped to one category by the caller).
    ///
    /// Stage 1: normalize both sides and check for an exact match — if found, the candidate
    /// IS that tag and should be selected rather than created.
    ///
    /// Stage 2: token-sort and compare by Levenshtein similarity. Returns near-matches
    /// above the threshold, ranked by similarity.
    public static func check(
        _ candidate: String,
        against tags: [Tag],
        threshold: Double = 0.85
    ) -> DuplicateCheckResult {
        let normalizedCandidate = normalize(candidate)
        guard !normalizedCandidate.isEmpty else { return .noMatch }

        // Stage 1 — exact normalized match
        for tag in tags {
            if normalize(tag.canonicalString) == normalizedCandidate {
                return .exactMatch(tag)
            }
        }

        // Stage 2 — token-sort + Levenshtein similarity
        let sortedCandidate = tokenSort(normalizedCandidate)
        var matches: [NearMatch] = []

        for tag in tags {
            let sortedTag = tokenSort(normalize(tag.canonicalString))
            let sim = levenshteinSimilarity(sortedCandidate, sortedTag)
            if sim >= threshold {
                matches.append(NearMatch(tag: tag, similarity: sim))
            }
        }

        if matches.isEmpty {
            return .noMatch
        }

        matches.sort { $0.similarity > $1.similarity }
        return .nearMatches(matches)
    }

    // MARK: - Normalization

    /// Normalizes a string for duplicate comparison: lowercase (locale-independent), trim,
    /// collapse internal whitespace, strip punctuation, NFC-normalize.
    public static func normalize(_ string: String) -> String {
        var result = string.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.lowercased()

        // Strip punctuation
        var scalars = String.UnicodeScalarView()
        for scalar in result.unicodeScalars {
            if !CharacterSet.punctuationCharacters.contains(scalar) {
                scalars.append(scalar)
            }
        }
        result = String(scalars)

        // Collapse internal whitespace
        result = result.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        // NFC for storage consistency (Swift String equality already handles
        // canonical equivalence, so this is for byte-stable output)
        result = result.precomposedStringWithCanonicalMapping

        return result
    }

    // MARK: - Token Sort

    /// Sorts the whitespace-delimited tokens of a string alphabetically.
    /// "warm overhead lighting" → "lighting overhead warm"
    public static func tokenSort(_ string: String) -> String {
        string.split(separator: " ", omittingEmptySubsequences: true)
            .sorted()
            .joined(separator: " ")
    }

    // MARK: - Levenshtein

    /// Returns a similarity score between 0.0 (completely different) and 1.0 (identical).
    public static func levenshteinSimilarity(_ a: String, _ b: String) -> Double {
        let distance = levenshteinDistance(a, b)
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - Double(distance) / Double(maxLen)
    }

    /// Classic dynamic-programming Levenshtein edit distance.
    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        if m == 0 { return n }
        if n == 0 { return m }

        // Two-row optimization
        var previous = Array(0...n)
        var current = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            current[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,        // deletion
                    current[j - 1] + 1,     // insertion
                    previous[j - 1] + cost  // substitution
                )
            }
            swap(&previous, &current)
        }

        return previous[n]
    }
}
