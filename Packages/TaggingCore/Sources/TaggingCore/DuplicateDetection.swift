import Foundation

public enum DuplicateDetector {

    public enum Result: Sendable {
        case exactMatch(Tag)
        case nearMatches([Match])
        case noMatch
    }

    public struct Match: Sendable {
        public let tag: Tag
        public let similarity: Double
    }

    // MARK: - Public API

    /// Checks a candidate string against existing tags in a category.
    ///
    /// Stage 1: normalizes both strings and blocks on exact match.
    /// Stage 2: token-sorts and compares by Levenshtein similarity,
    /// returning near-matches above the threshold (~0.85 Recommended).
    public static func findDuplicates(
        candidate: String,
        in existingTags: [Tag],
        threshold: Double = 0.85
    ) -> Result {
        let normalizedCandidate = normalize(candidate)

        // Stage 1 — exact match after normalization blocks immediately
        for tag in existingTags {
            if normalize(tag.canonicalString) == normalizedCandidate {
                return .exactMatch(tag)
            }
        }

        // Stage 2 — fuzzy match via token-sort + Levenshtein
        let sortedCandidate = tokenSort(normalizedCandidate)
        var nearMatches: [Match] = []

        for tag in existingTags {
            let normalizedExisting = normalize(tag.canonicalString)
            let sortedExisting = tokenSort(normalizedExisting)
            // Compare both sorted (catches word reorder) and unsorted (catches typos)
            let similarity = max(
                levenshteinSimilarity(sortedCandidate, sortedExisting),
                levenshteinSimilarity(normalizedCandidate, normalizedExisting)
            )
            if similarity >= threshold {
                nearMatches.append(Match(tag: tag, similarity: similarity))
            }
        }

        nearMatches.sort { $0.similarity > $1.similarity }

        return nearMatches.isEmpty ? .noMatch : .nearMatches(nearMatches)
    }

    // MARK: - Normalization

    /// Normalizes a string for comparison: lowercase, strip punctuation,
    /// collapse whitespace, NFC-normalize. Locale-independent.
    public static func normalize(_ string: String) -> String {
        var s = string.lowercased()
        s = s.unicodeScalars.map { CharacterSet.punctuationCharacters.contains($0) ? " " : String($0) }.joined()
        s = s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        s = s.precomposedStringWithCanonicalMapping
        return s
    }

    // MARK: - Internals

    static func tokenSort(_ string: String) -> String {
        string.split(separator: " ").sorted().joined(separator: " ")
    }

    static func levenshteinSimilarity(_ a: String, _ b: String) -> Double {
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - Double(levenshteinDistance(a, b)) / Double(maxLen)
    }

    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        guard m > 0 else { return n }
        guard n > 0 else { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }

        return prev[n]
    }
}
