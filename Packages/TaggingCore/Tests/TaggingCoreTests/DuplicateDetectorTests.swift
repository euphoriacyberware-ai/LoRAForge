import Foundation
import Testing
import TaggingCore

// Disambiguate from Testing.Tag
private typealias Tag = TaggingCore.Tag

@Suite("DuplicateDetector")
struct DuplicateDetectorTests {

    private let categoryID = UUID()

    private func tag(_ string: String) -> Tag {
        Tag(canonicalString: string, categoryID: categoryID)
    }

    // MARK: - Normalization

    @Test func normalizationLowercasesLocaleIndependently() {
        #expect(DuplicateDetector.normalize("Looking At Viewer") == "looking at viewer")
        // Turkish I test — should use Unicode default, not Turkish rules.
        // In Turkish locale, "I" → "ı" (dotless). We want "I" → "i" always.
        #expect(DuplicateDetector.normalize("I") == "i")
    }

    @Test func normalizationTrimsWhitespace() {
        #expect(DuplicateDetector.normalize("  smiling  ") == "smiling")
    }

    @Test func normalizationCollapsesInternalWhitespace() {
        #expect(DuplicateDetector.normalize("warm   overhead   lighting") == "warm overhead lighting")
    }

    @Test func normalizationStripsPunctuation() {
        #expect(DuplicateDetector.normalize("three-quarter view") == "threequarter view")
        #expect(DuplicateDetector.normalize("it's fine!") == "its fine")
    }

    @Test func normalizationNFCNormalizes() {
        // e + combining acute accent (decomposed) should normalize to precomposed é
        let decomposed = "e\u{0301}"
        let precomposed = "\u{00E9}"
        let normalizedDecomposed = DuplicateDetector.normalize(decomposed)
        let normalizedPrecomposed = DuplicateDetector.normalize(precomposed)
        #expect(normalizedDecomposed == normalizedPrecomposed)
    }

    @Test func normalizationEmptyString() {
        #expect(DuplicateDetector.normalize("") == "")
        #expect(DuplicateDetector.normalize("   ") == "")
    }

    // MARK: - Token sort

    @Test func tokenSortReordersAlphabetically() {
        #expect(DuplicateDetector.tokenSort("warm overhead lighting") == "lighting overhead warm")
    }

    // MARK: - Levenshtein

    @Test func identicalStringsHaveSimilarityOne() {
        #expect(DuplicateDetector.levenshteinSimilarity("smiling", "smiling") == 1.0)
    }

    @Test func completelyDifferentStringsHaveLowSimilarity() {
        let sim = DuplicateDetector.levenshteinSimilarity("abc", "xyz")
        #expect(sim < 0.5)
    }

    @Test func emptyStringsHaveSimilarityOne() {
        #expect(DuplicateDetector.levenshteinSimilarity("", "") == 1.0)
    }

    @Test func oneEmptyStringHasSimilarityZero() {
        #expect(DuplicateDetector.levenshteinSimilarity("abc", "") == 0.0)
        #expect(DuplicateDetector.levenshteinSimilarity("", "abc") == 0.0)
    }

    @Test func typoCaughtByEditDistance() {
        let sim = DuplicateDetector.levenshteinSimilarity("smiling", "smilng")
        #expect(sim > 0.8)
    }

    // MARK: - Stage 1: exact normalized match

    @Test func exactNormalizedMatchReturnsThatTag() {
        let existing = tag("looking at viewer")
        let result = DuplicateDetector.check("Looking At Viewer", against: [existing])

        if case .exactMatch(let matched) = result {
            #expect(matched.id == existing.id)
        } else {
            Issue.record("Expected exactMatch, got \(result)")
        }
    }

    @Test func exactMatchAfterTrimmingAndCollapsing() {
        let existing = tag("warm overhead lighting")
        let result = DuplicateDetector.check("  warm   overhead   lighting  ", against: [existing])

        if case .exactMatch(let matched) = result {
            #expect(matched.id == existing.id)
        } else {
            Issue.record("Expected exactMatch, got \(result)")
        }
    }

    @Test func exactMatchIgnoresPunctuation() {
        let existing = tag("three-quarter view")
        let result = DuplicateDetector.check("threequarter view", against: [existing])

        if case .exactMatch(let matched) = result {
            #expect(matched.id == existing.id)
        } else {
            Issue.record("Expected exactMatch, got \(result)")
        }
    }

    // MARK: - Stage 2: near matches

    @Test func wordOrderVariationsDetected() {
        let existing = tag("warm overhead lighting")
        let result = DuplicateDetector.check("overhead warm lighting", against: [existing])

        if case .nearMatches(let matches) = result {
            #expect(matches.count == 1)
            #expect(matches[0].tag.id == existing.id)
            #expect(matches[0].similarity > 0.99)
        } else {
            Issue.record("Expected nearMatches, got \(result)")
        }
    }

    @Test func typoDetected() {
        let existing = tag("looking at viewer")
        let result = DuplicateDetector.check("loking at viewer", against: [existing])

        if case .nearMatches(let matches) = result {
            #expect(matches.count == 1)
            #expect(matches[0].tag.id == existing.id)
            #expect(matches[0].similarity >= 0.85)
        } else {
            Issue.record("Expected nearMatches, got \(result)")
        }
    }

    @Test func nearMatchesRankedBySimilarity() {
        let t1 = tag("warm lighting")
        let t2 = tag("warm overhead lighting")
        let result = DuplicateDetector.check("warm overhed lighting", against: [t1, t2], threshold: 0.7)

        if case .nearMatches(let matches) = result {
            #expect(matches.count >= 1)
            #expect(matches[0].similarity >= matches.last!.similarity)
        } else {
            Issue.record("Expected nearMatches, got \(result)")
        }
    }

    // MARK: - No match

    @Test func noMatchBelowThreshold() {
        let existing = tag("smiling")
        let result = DuplicateDetector.check("standing with arms crossed", against: [existing])

        if case .noMatch = result {
            // expected
        } else {
            Issue.record("Expected noMatch, got \(result)")
        }
    }

    @Test func noMatchAgainstEmptyLibrary() {
        let result = DuplicateDetector.check("smiling", against: [])
        if case .noMatch = result {
            // expected
        } else {
            Issue.record("Expected noMatch, got \(result)")
        }
    }

    @Test func emptyInputReturnsNoMatch() {
        let existing = tag("smiling")
        let result = DuplicateDetector.check("", against: [existing])
        if case .noMatch = result {
            // expected
        } else {
            Issue.record("Expected noMatch, got \(result)")
        }
    }

    // MARK: - Substring containment is not used

    @Test func distinctGarmentsAreNotFlaggedAsDuplicates() {
        // "yellow sundress" and "blue sundress" share "sundress" but are correctly distinct.
        // Substring containment would flag them; edit distance does not at the default threshold.
        let existing = tag("yellow sundress")
        let result = DuplicateDetector.check("blue sundress", against: [existing])

        switch result {
        case .noMatch:
            break // correct
        case .nearMatches(let matches):
            for m in matches {
                #expect(m.similarity < 0.85, "Should not flag distinct garments at default threshold")
            }
        case .exactMatch:
            Issue.record("Distinct garments should not be an exact match")
        }
    }
}
