import Testing
import Foundation
@testable import TaggingCore

private typealias Tag = TaggingCore.Tag

// MARK: - Test helpers

/// Creates the eleven built-in categories in their default configuration.
private func defaultCategories() -> [TagCategory] {
    BuiltInCategory.defaultCategories
}

/// Builds a tag dictionary from an array of tags.
private func tagDict(_ tags: [Tag]) -> [UUID: Tag] {
    Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
}

// MARK: - Caption Renderer Tests

@Suite("Caption Renderer")
struct CaptionRendererTests {

    @Test("Example render from tagging doc §4")
    func exampleRender() {
        let categories = defaultCategories()

        let maya = Tag(canonicalString: "Maya", categoryID: BuiltInCategory.subject.id)
        let mediumShot = Tag(canonicalString: "medium shot", categoryID: BuiltInCategory.framing.id)
        let threeQuarter = Tag(canonicalString: "three-quarter view", categoryID: BuiltInCategory.cameraAngle.id)
        let standing = Tag(canonicalString: "standing", categoryID: BuiltInCategory.pose.id)
        let lookingAtViewer = Tag(canonicalString: "looking at viewer", categoryID: BuiltInCategory.gaze.id)
        let smiling = Tag(canonicalString: "smiling", categoryID: BuiltInCategory.expression.id)
        let warmLight = Tag(canonicalString: "warm overhead lighting", categoryID: BuiltInCategory.lighting.id)
        let hairDown = Tag(canonicalString: "hair down", categoryID: BuiltInCategory.hairstyle.id)
        let sundress = Tag(canonicalString: "yellow sundress", categoryID: BuiltInCategory.clothing.id)
        let hat = Tag(canonicalString: "white hat", categoryID: BuiltInCategory.clothing.id)
        let purse = Tag(canonicalString: "black purse", categoryID: BuiltInCategory.heldItems.id)
        let lobby = Tag(canonicalString: "hotel lobby background", categoryID: BuiltInCategory.backgroundLocation.id)

        let tags = tagDict([maya, mediumShot, threeQuarter, standing, lookingAtViewer,
                            smiling, warmLight, hairDown, sundress, hat, purse, lobby])

        let assignments: [TagAssignment] = [
            TagAssignment(tagID: maya.id, selectionOrder: 0),
            TagAssignment(tagID: mediumShot.id, selectionOrder: 0),
            TagAssignment(tagID: threeQuarter.id, selectionOrder: 0),
            TagAssignment(tagID: standing.id, selectionOrder: 0),
            TagAssignment(tagID: lookingAtViewer.id, selectionOrder: 0),
            TagAssignment(tagID: smiling.id, selectionOrder: 0),
            TagAssignment(tagID: warmLight.id, selectionOrder: 0),
            TagAssignment(tagID: hairDown.id, selectionOrder: 0),
            TagAssignment(tagID: sundress.id, selectionOrder: 0),
            TagAssignment(tagID: hat.id, selectionOrder: 1),
            TagAssignment(tagID: purse.id, selectionOrder: 0),
            TagAssignment(tagID: lobby.id, selectionOrder: 0),
        ]

        let result = CaptionRenderer.render(assignments: assignments, tags: tags, categories: categories)

        let expected = "Maya, medium shot, three-quarter view, standing, looking at viewer, smiling, warm overhead lighting, hair down, wearing yellow sundress and white hat, holding black purse, hotel lobby background"
        #expect(result == expected)
    }

    @Test("Tag text renders verbatim — no appending, rewriting, or normalising")
    func verbatimRendering() {
        let cat = TagCategory(name: "Test", selectMode: .single, position: 0)
        let tag = Tag(canonicalString: "Looking At Viewer", categoryID: cat.id)
        let assignments = [TagAssignment(tagID: tag.id, selectionOrder: 0)]
        let result = CaptionRenderer.render(assignments: assignments, tags: tagDict([tag]), categories: [cat])
        #expect(result == "Looking At Viewer")
    }

    @Test("Prefix renders before values")
    func prefixRendering() {
        let cat = TagCategory(name: "Clothing", selectMode: .multi, prefix: "wearing", position: 0)
        let tag = Tag(canonicalString: "yellow sundress", categoryID: cat.id)
        let assignments = [TagAssignment(tagID: tag.id, selectionOrder: 0)]
        let result = CaptionRenderer.render(assignments: assignments, tags: tagDict([tag]), categories: [cat])
        #expect(result == "wearing yellow sundress")
    }

    @Test("Prefix with no values emits nothing")
    func prefixNoValues() {
        let cat = TagCategory(name: "Clothing", selectMode: .multi, prefix: "wearing", position: 0)
        let result = CaptionRenderer.render(assignments: [], tags: [:], categories: [cat])
        #expect(result == "")
    }

    @Test("Multi-select joins with 'and' in selection order, never sorted")
    func multiSelectOrder() {
        let cat = TagCategory(name: "Clothing", selectMode: .multi, prefix: "wearing", position: 0)
        let hat = Tag(canonicalString: "white hat", categoryID: cat.id)
        let dress = Tag(canonicalString: "yellow sundress", categoryID: cat.id)
        let earrings = Tag(canonicalString: "gold earrings", categoryID: cat.id)

        // Deliberately non-alphabetical order
        let assignments = [
            TagAssignment(tagID: hat.id, selectionOrder: 0),
            TagAssignment(tagID: dress.id, selectionOrder: 1),
            TagAssignment(tagID: earrings.id, selectionOrder: 2),
        ]
        let result = CaptionRenderer.render(
            assignments: assignments, tags: tagDict([hat, dress, earrings]), categories: [cat]
        )
        #expect(result == "wearing white hat and yellow sundress and gold earrings")
    }

    @Test("Empty categories are omitted along with their comma")
    func emptyCategoriesOmitted() {
        let subject = TagCategory(name: "Subject", selectMode: .single, position: 0)
        let pose = TagCategory(name: "Pose", selectMode: .single, position: 1)
        let expression = TagCategory(name: "Expression", selectMode: .single, position: 2)

        let maya = Tag(canonicalString: "Maya", categoryID: subject.id)
        let smiling = Tag(canonicalString: "smiling", categoryID: expression.id)

        // Pose has no assignment — should be omitted entirely
        let assignments = [
            TagAssignment(tagID: maya.id, selectionOrder: 0),
            TagAssignment(tagID: smiling.id, selectionOrder: 0),
        ]
        let result = CaptionRenderer.render(
            assignments: assignments, tags: tagDict([maya, smiling]),
            categories: [subject, pose, expression]
        )
        #expect(result == "Maya, smiling")
    }

    @Test("Subject renders at position zero with no prefix")
    func subjectPositionZero() {
        let categories = defaultCategories()
        let maya = Tag(canonicalString: "Maya", categoryID: BuiltInCategory.subject.id)
        let standing = Tag(canonicalString: "standing", categoryID: BuiltInCategory.pose.id)

        let assignments = [
            TagAssignment(tagID: maya.id, selectionOrder: 0),
            TagAssignment(tagID: standing.id, selectionOrder: 0),
        ]
        let result = CaptionRenderer.render(
            assignments: assignments, tags: tagDict([maya, standing]), categories: categories
        )
        // Subject must appear first, with no prefix
        #expect(result.hasPrefix("Maya"))
        #expect(result == "Maya, standing")
    }

    @Test("Disabled categories render nothing")
    func disabledCategorySkipped() {
        var subject = TagCategory(name: "Subject", selectMode: .single, position: 0)
        subject.isEnabled = true
        var lighting = TagCategory(name: "Lighting", selectMode: .single, position: 1)
        lighting.isEnabled = false
        let expression = TagCategory(name: "Expression", selectMode: .single, position: 2)

        let maya = Tag(canonicalString: "Maya", categoryID: subject.id)
        let warm = Tag(canonicalString: "warm light", categoryID: lighting.id)
        let smiling = Tag(canonicalString: "smiling", categoryID: expression.id)

        let assignments = [
            TagAssignment(tagID: maya.id, selectionOrder: 0),
            TagAssignment(tagID: warm.id, selectionOrder: 0),
            TagAssignment(tagID: smiling.id, selectionOrder: 0),
        ]
        let result = CaptionRenderer.render(
            assignments: assignments, tags: tagDict([maya, warm, smiling]),
            categories: [subject, lighting, expression]
        )
        // Lighting is disabled — its tag should not appear
        #expect(result == "Maya, smiling")
    }

    @Test("Categories render in position order regardless of input order")
    func positionOrdering() {
        let catB = TagCategory(name: "B", selectMode: .single, position: 1)
        let catA = TagCategory(name: "A", selectMode: .single, position: 0)
        let catC = TagCategory(name: "C", selectMode: .single, position: 2)

        let tagA = Tag(canonicalString: "alpha", categoryID: catA.id)
        let tagB = Tag(canonicalString: "beta", categoryID: catB.id)
        let tagC = Tag(canonicalString: "gamma", categoryID: catC.id)

        let assignments = [
            TagAssignment(tagID: tagC.id, selectionOrder: 0),
            TagAssignment(tagID: tagA.id, selectionOrder: 0),
            TagAssignment(tagID: tagB.id, selectionOrder: 0),
        ]
        let result = CaptionRenderer.render(
            assignments: assignments, tags: tagDict([tagA, tagB, tagC]),
            categories: [catB, catA, catC]
        )
        #expect(result == "alpha, beta, gamma")
    }

    @Test("No assignments produces empty string")
    func emptyAssignments() {
        let result = CaptionRenderer.render(
            assignments: [], tags: [:], categories: defaultCategories()
        )
        #expect(result == "")
    }

    @Test("Single-select category renders only the first tag by selection order")
    func singleSelectFirstOnly() {
        let cat = TagCategory(name: "Pose", selectMode: .single, position: 0)
        let tag1 = Tag(canonicalString: "standing", categoryID: cat.id)
        let tag2 = Tag(canonicalString: "sitting", categoryID: cat.id)

        // Two assignments in a single-select category — only lowest order renders
        let assignments = [
            TagAssignment(tagID: tag2.id, selectionOrder: 1),
            TagAssignment(tagID: tag1.id, selectionOrder: 0),
        ]
        let result = CaptionRenderer.render(
            assignments: assignments, tags: tagDict([tag1, tag2]), categories: [cat]
        )
        #expect(result == "standing")
    }
}

// MARK: - Built-in Category Tests

@Suite("Built-in Categories")
struct BuiltInCategoryTests {

    @Test("Eleven built-in categories with stable IDs")
    func elevenCategories() {
        let categories = BuiltInCategory.defaultCategories
        #expect(categories.count == 11)

        // All IDs are distinct
        let ids = Set(categories.map(\.id))
        #expect(ids.count == 11)

        // All are built-in
        let allBuiltIn = categories.allSatisfy(\.isBuiltIn)
        #expect(allBuiltIn)
    }

    @Test("Subject is position zero, single-select, no prefix")
    func subjectProperties() {
        let subject = BuiltInCategory.subject.defaultCategory
        #expect(subject.position == 0)
        #expect(subject.selectMode == .single)
        #expect(subject.prefix == nil)
        #expect(subject.isBuiltIn)
    }

    @Test("Clothing and Held-Items are multi-select with prefixes")
    func multiSelectPrefixes() {
        let clothing = BuiltInCategory.clothing.defaultCategory
        #expect(clothing.selectMode == .multi)
        #expect(clothing.prefix == "wearing")

        let heldItems = BuiltInCategory.heldItems.defaultCategory
        #expect(heldItems.selectMode == .multi)
        #expect(heldItems.prefix == "holding")
    }

    @Test("Each category carries its own 70/10 threshold pair")
    func individualThresholds() {
        for category in BuiltInCategory.defaultCategories {
            #expect(category.highThreshold == 70)
            #expect(category.lowThreshold == 10)
        }
    }

    @Test("Default order matches the design document")
    func defaultOrder() {
        let names = BuiltInCategory.defaultCategories
            .sorted { $0.position < $1.position }
            .map(\.name)
        #expect(names == [
            "Subject", "Framing", "Camera Angle", "Pose", "Gaze", "Expression",
            "Lighting", "Hairstyle", "Clothing", "Held-Items", "Background-Location"
        ])
    }

    @Test("Built-in IDs are deterministic across calls")
    func stableIDs() {
        let first = BuiltInCategory.subject.id
        let second = BuiltInCategory.subject.id
        #expect(first == second)
    }
}

// MARK: - Duplicate Detection Tests

@Suite("Duplicate Detection")
struct DuplicateDetectionTests {

    @Test("Exact match after normalization blocks")
    func exactMatchBlocks() {
        let cat = TagCategory(name: "Pose", selectMode: .single, position: 0)
        let existing = Tag(canonicalString: "looking at viewer", categoryID: cat.id)

        // Same text, different case
        let result = DuplicateDetector.findDuplicates(candidate: "Looking At Viewer", in: [existing])
        if case .exactMatch(let tag) = result {
            #expect(tag.id == existing.id)
        } else {
            Issue.record("Expected exact match")
        }
    }

    @Test("Extra whitespace is collapsed before matching")
    func whitespaceCollapsed() {
        let cat = TagCategory(name: "Pose", selectMode: .single, position: 0)
        let existing = Tag(canonicalString: "looking at viewer", categoryID: cat.id)

        let result = DuplicateDetector.findDuplicates(candidate: "  looking   at   viewer  ", in: [existing])
        if case .exactMatch = result {
            // pass
        } else {
            Issue.record("Expected exact match after whitespace collapse")
        }
    }

    @Test("Punctuation is stripped before matching")
    func punctuationStripped() {
        let cat = TagCategory(name: "Pose", selectMode: .single, position: 0)
        let existing = Tag(canonicalString: "three-quarter view", categoryID: cat.id)

        let result = DuplicateDetector.findDuplicates(candidate: "three quarter view", in: [existing])
        if case .exactMatch = result {
            // pass — hyphen stripped from both
        } else {
            Issue.record("Expected exact match after punctuation stripping")
        }
    }

    @Test("Token-sort catches reordered words")
    func tokenSortReorder() {
        let cat = TagCategory(name: "Lighting", selectMode: .single, position: 0)
        let existing = Tag(canonicalString: "warm overhead lighting", categoryID: cat.id)

        let result = DuplicateDetector.findDuplicates(
            candidate: "overhead warm lighting", in: [existing]
        )
        // After normalization + token-sort, both become "lighting overhead warm"
        // Exact match after token-sort → similarity = 1.0
        switch result {
        case .exactMatch:
            break // token-sorted exact match goes through stage 2 as 1.0 similarity
        case .nearMatches(let matches):
            #expect(matches[0].similarity >= 0.99)
        case .noMatch:
            Issue.record("Expected match for reordered words")
        }
    }

    @Test("Typo detected as near-match")
    func typoDetected() {
        let cat = TagCategory(name: "Lighting", selectMode: .single, position: 0)
        let existing = Tag(canonicalString: "warm overhead lighting", categoryID: cat.id)

        let result = DuplicateDetector.findDuplicates(
            candidate: "warm overheadlighting", in: [existing], threshold: 0.80
        )
        if case .nearMatches(let matches) = result {
            #expect(matches[0].tag.id == existing.id)
            #expect(matches[0].similarity > 0.80)
        } else if case .exactMatch = result {
            // Also acceptable if normalization brings them together
        } else {
            Issue.record("Expected near-match for typo")
        }
    }

    @Test("Distinct tags are not flagged")
    func distinctNotFlagged() {
        let cat = TagCategory(name: "Clothing", selectMode: .multi, position: 0)
        let existing = [
            Tag(canonicalString: "yellow sundress", categoryID: cat.id),
            Tag(canonicalString: "blue sundress", categoryID: cat.id),
        ]

        let result = DuplicateDetector.findDuplicates(candidate: "red jacket", in: existing)
        if case .noMatch = result {
            // pass
        } else {
            Issue.record("Expected no match for completely different tag")
        }
    }

    @Test("Empty candidate normalizes without crashing")
    func emptyCandidate() {
        let result = DuplicateDetector.findDuplicates(candidate: "", in: [])
        if case .noMatch = result {
            // pass
        } else {
            Issue.record("Expected no match for empty candidate")
        }
    }

    @Test("Normalization is locale-independent")
    func localeIndependence() {
        // Swift's lowercased() is locale-independent by default.
        // The Turkish I problem: 'I' should fold to 'i', not 'ı'.
        let normalized = DuplicateDetector.normalize("ISTANBUL")
        #expect(normalized == "istanbul")
    }

    @Test("Levenshtein similarity of identical strings is 1.0")
    func identicalSimilarity() {
        let sim = DuplicateDetector.levenshteinSimilarity("hello", "hello")
        #expect(sim == 1.0)
    }

    @Test("Levenshtein similarity of completely different strings is low")
    func differentSimilarity() {
        let sim = DuplicateDetector.levenshteinSimilarity("abc", "xyz")
        #expect(sim < 0.5)
    }

    @Test("Levenshtein handles empty strings")
    func emptyStringSimilarity() {
        #expect(DuplicateDetector.levenshteinSimilarity("", "") == 1.0)
        #expect(DuplicateDetector.levenshteinSimilarity("abc", "") == 0.0)
        #expect(DuplicateDetector.levenshteinSimilarity("", "abc") == 0.0)
    }
}
