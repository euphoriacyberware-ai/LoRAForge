import Foundation
import Testing
import TaggingCore

// Disambiguate from Testing.Tag
private typealias Tag = TaggingCore.Tag

@Suite("CaptionRenderer")
struct CaptionRendererTests {

    // MARK: - Helpers

    /// Builds the full 11-category schema from tagging doc §4.
    private func makeDefaultCategories() -> [TagCategory] {
        [
            TagCategory(id: CatID.subject,    name: "Subject",             selectMode: .single, prefix: nil,       position: 0,  isBuiltIn: true),
            TagCategory(id: CatID.framing,    name: "Framing",             selectMode: .single, prefix: nil,       position: 1,  isBuiltIn: true),
            TagCategory(id: CatID.camera,     name: "Camera Angle",        selectMode: .single, prefix: nil,       position: 2,  isBuiltIn: true),
            TagCategory(id: CatID.pose,       name: "Pose",                selectMode: .single, prefix: nil,       position: 3,  isBuiltIn: true),
            TagCategory(id: CatID.gaze,       name: "Gaze",                selectMode: .single, prefix: nil,       position: 4,  isBuiltIn: true),
            TagCategory(id: CatID.expression, name: "Expression",          selectMode: .single, prefix: nil,       position: 5,  isBuiltIn: true),
            TagCategory(id: CatID.lighting,   name: "Lighting",            selectMode: .single, prefix: nil,       position: 6,  isBuiltIn: true),
            TagCategory(id: CatID.hairstyle,  name: "Hairstyle",           selectMode: .single, prefix: nil,       position: 7,  isBuiltIn: true),
            TagCategory(id: CatID.clothing,   name: "Clothing",            selectMode: .multi,  prefix: "wearing", position: 8,  isBuiltIn: true),
            TagCategory(id: CatID.heldItems,  name: "Held-Items",          selectMode: .multi,  prefix: "holding", position: 9,  isBuiltIn: true),
            TagCategory(id: CatID.background, name: "Background-Location", selectMode: .single, prefix: nil,       position: 10, isBuiltIn: true),
        ]
    }

    // Stable UUIDs for test categories
    private enum CatID {
        static let subject    = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        static let framing    = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        static let camera     = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        static let pose       = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        static let gaze       = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        static let expression = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
        static let lighting   = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
        static let hairstyle  = UUID(uuidString: "00000000-0000-0000-0000-000000000008")!
        static let clothing   = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
        static let heldItems  = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
        static let background = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    }

    private func tag(_ string: String, in categoryID: UUID) -> Tag {
        Tag(canonicalString: string, categoryID: categoryID)
    }

    // MARK: - Verbatim rendering

    @Test func tagTextRendersVerbatim() {
        let cat = TagCategory(name: "Expression", selectMode: .single, position: 0)
        let t = Tag(canonicalString: "smiling warmly", categoryID: cat.id)
        let assignments = [TagAssignment(tagID: t.id, selectionOrder: 0)]

        let result = CaptionRenderer.render(assignments: assignments, tags: [t], categories: [cat])
        #expect(result == "smiling warmly")
    }

    @Test func noAppendingOrRewriting() {
        let cat = TagCategory(name: "Background-Location", selectMode: .single, position: 0)
        let t = Tag(canonicalString: "hotel lobby background", categoryID: cat.id)
        let assignments = [TagAssignment(tagID: t.id, selectionOrder: 0)]

        let result = CaptionRenderer.render(assignments: assignments, tags: [t], categories: [cat])
        #expect(result == "hotel lobby background")
    }

    // MARK: - Prefix rendering

    @Test func prefixRenderedBeforeValues() {
        let cat = TagCategory(name: "Clothing", selectMode: .multi, prefix: "wearing", position: 0)
        let t = Tag(canonicalString: "yellow sundress", categoryID: cat.id)
        let assignments = [TagAssignment(tagID: t.id, selectionOrder: 0)]

        let result = CaptionRenderer.render(assignments: assignments, tags: [t], categories: [cat])
        #expect(result == "wearing yellow sundress")
    }

    @Test func prefixWithNoValuesEmitsNothing() {
        let cat = TagCategory(name: "Clothing", selectMode: .multi, prefix: "wearing", position: 0)
        let other = TagCategory(name: "Expression", selectMode: .single, position: 1)
        let t = Tag(canonicalString: "smiling", categoryID: other.id)
        let assignments = [TagAssignment(tagID: t.id, selectionOrder: 0)]

        let result = CaptionRenderer.render(assignments: assignments, tags: [t], categories: [cat, other])
        #expect(result == "smiling")
    }

    // MARK: - Multi-select

    @Test func multiSelectJoinsWithAnd() {
        let cat = TagCategory(name: "Clothing", selectMode: .multi, prefix: "wearing", position: 0)
        let t1 = Tag(canonicalString: "yellow sundress", categoryID: cat.id)
        let t2 = Tag(canonicalString: "white hat", categoryID: cat.id)
        let assignments = [
            TagAssignment(tagID: t1.id, selectionOrder: 0),
            TagAssignment(tagID: t2.id, selectionOrder: 1),
        ]

        let result = CaptionRenderer.render(assignments: assignments, tags: [t1, t2], categories: [cat])
        #expect(result == "wearing yellow sundress and white hat")
    }

    @Test func multiSelectPreservesSelectionOrder() {
        let cat = TagCategory(name: "Clothing", selectMode: .multi, prefix: "wearing", position: 0)
        let sundress = Tag(canonicalString: "yellow sundress", categoryID: cat.id)
        let hat = Tag(canonicalString: "white hat", categoryID: cat.id)
        let assignments = [
            TagAssignment(tagID: hat.id, selectionOrder: 0),
            TagAssignment(tagID: sundress.id, selectionOrder: 1),
        ]

        let result = CaptionRenderer.render(
            assignments: assignments, tags: [sundress, hat], categories: [cat]
        )
        #expect(result == "wearing white hat and yellow sundress")
    }

    @Test func multiSelectThreeValues() {
        let cat = TagCategory(name: "Clothing", selectMode: .multi, prefix: "wearing", position: 0)
        let t1 = Tag(canonicalString: "yellow sundress", categoryID: cat.id)
        let t2 = Tag(canonicalString: "white hat", categoryID: cat.id)
        let t3 = Tag(canonicalString: "gold earrings", categoryID: cat.id)
        let assignments = [
            TagAssignment(tagID: t1.id, selectionOrder: 0),
            TagAssignment(tagID: t2.id, selectionOrder: 1),
            TagAssignment(tagID: t3.id, selectionOrder: 2),
        ]

        let result = CaptionRenderer.render(
            assignments: assignments, tags: [t1, t2, t3], categories: [cat]
        )
        #expect(result == "wearing yellow sundress and white hat and gold earrings")
    }

    // MARK: - Empty categories omitted

    @Test func emptyCategoriesOmittedWithComma() {
        let c1 = TagCategory(name: "Subject", selectMode: .single, position: 0)
        let c2 = TagCategory(name: "Framing", selectMode: .single, position: 1)
        let c3 = TagCategory(name: "Expression", selectMode: .single, position: 2)
        let t1 = Tag(canonicalString: "Maya", categoryID: c1.id)
        let t3 = Tag(canonicalString: "smiling", categoryID: c3.id)
        let assignments = [
            TagAssignment(tagID: t1.id, selectionOrder: 0),
            TagAssignment(tagID: t3.id, selectionOrder: 0),
        ]

        let result = CaptionRenderer.render(
            assignments: assignments, tags: [t1, t3], categories: [c1, c2, c3]
        )
        #expect(result == "Maya, smiling")
    }

    @Test func allCategoriesEmptyRendersEmptyString() {
        let c1 = TagCategory(name: "Subject", selectMode: .single, position: 0)
        let result = CaptionRenderer.render(assignments: [], tags: [], categories: [c1])
        #expect(result == "")
    }

    // MARK: - Subject at position zero

    @Test func subjectIsPositionZeroPrefixless() {
        let subject = TagCategory(name: "Subject", selectMode: .single, prefix: nil, position: 0)
        let framing = TagCategory(name: "Framing", selectMode: .single, prefix: nil, position: 1)
        let ts = Tag(canonicalString: "Maya", categoryID: subject.id)
        let tf = Tag(canonicalString: "medium shot", categoryID: framing.id)
        let assignments = [
            TagAssignment(tagID: ts.id, selectionOrder: 0),
            TagAssignment(tagID: tf.id, selectionOrder: 0),
        ]

        let result = CaptionRenderer.render(
            assignments: assignments, tags: [ts, tf], categories: [subject, framing]
        )
        #expect(result == "Maya, medium shot")
    }

    // MARK: - Disabled categories

    @Test func disabledCategoriesRenderNothing() {
        let enabled = TagCategory(name: "Subject", selectMode: .single, position: 0, isEnabled: true)
        let disabled = TagCategory(name: "Framing", selectMode: .single, position: 1, isEnabled: false)
        let t1 = Tag(canonicalString: "Maya", categoryID: enabled.id)
        let t2 = Tag(canonicalString: "medium shot", categoryID: disabled.id)
        let assignments = [
            TagAssignment(tagID: t1.id, selectionOrder: 0),
            TagAssignment(tagID: t2.id, selectionOrder: 0),
        ]

        let result = CaptionRenderer.render(
            assignments: assignments, tags: [t1, t2], categories: [enabled, disabled]
        )
        #expect(result == "Maya")
    }

    @Test func disabledCategoryWithPrefixEmitsNothing() {
        let clothing = TagCategory(
            name: "Clothing", selectMode: .multi, prefix: "wearing",
            position: 0, isEnabled: false
        )
        let t = Tag(canonicalString: "yellow sundress", categoryID: clothing.id)
        let assignments = [TagAssignment(tagID: t.id, selectionOrder: 0)]

        let result = CaptionRenderer.render(assignments: assignments, tags: [t], categories: [clothing])
        #expect(result == "")
    }

    // MARK: - Full example from tagging doc §4

    @Test func exampleRenderFromDesign() {
        let categories = makeDefaultCategories()

        let maya      = tag("Maya",                    in: CatID.subject)
        let medium    = tag("medium shot",             in: CatID.framing)
        let threeQ    = tag("three-quarter view",      in: CatID.camera)
        let standing  = tag("standing",                in: CatID.pose)
        let looking   = tag("looking at viewer",       in: CatID.gaze)
        let smiling   = tag("smiling",                 in: CatID.expression)
        let lighting  = tag("warm overhead lighting",  in: CatID.lighting)
        let hairDown  = tag("hair down",               in: CatID.hairstyle)
        let sundress  = tag("yellow sundress",         in: CatID.clothing)
        let hat       = tag("white hat",               in: CatID.clothing)
        let purse     = tag("black purse",             in: CatID.heldItems)
        let lobby     = tag("hotel lobby background",  in: CatID.background)

        let tags: [Tag] = [maya, medium, threeQ, standing, looking, smiling,
                           lighting, hairDown, sundress, hat, purse, lobby]

        let assignments = [
            TagAssignment(tagID: maya.id,     selectionOrder: 0),
            TagAssignment(tagID: medium.id,   selectionOrder: 0),
            TagAssignment(tagID: threeQ.id,   selectionOrder: 0),
            TagAssignment(tagID: standing.id, selectionOrder: 0),
            TagAssignment(tagID: looking.id,  selectionOrder: 0),
            TagAssignment(tagID: smiling.id,  selectionOrder: 0),
            TagAssignment(tagID: lighting.id, selectionOrder: 0),
            TagAssignment(tagID: hairDown.id, selectionOrder: 0),
            TagAssignment(tagID: sundress.id, selectionOrder: 0),
            TagAssignment(tagID: hat.id,      selectionOrder: 1),
            TagAssignment(tagID: purse.id,    selectionOrder: 0),
            TagAssignment(tagID: lobby.id,    selectionOrder: 0),
        ]

        let result = CaptionRenderer.render(
            assignments: assignments, tags: tags, categories: categories
        )

        let expected = "Maya, medium shot, three-quarter view, standing, looking at viewer, "
            + "smiling, warm overhead lighting, hair down, wearing yellow sundress and white hat, "
            + "holding black purse, hotel lobby background"

        #expect(result == expected)
    }

    // MARK: - Position ordering

    @Test func categoriesRenderInPositionOrder() {
        let c1 = TagCategory(name: "B", selectMode: .single, position: 2)
        let c2 = TagCategory(name: "A", selectMode: .single, position: 0)
        let c3 = TagCategory(name: "C", selectMode: .single, position: 1)
        let t1 = Tag(canonicalString: "second", categoryID: c1.id)
        let t2 = Tag(canonicalString: "first", categoryID: c2.id)
        let t3 = Tag(canonicalString: "middle", categoryID: c3.id)
        let assignments = [
            TagAssignment(tagID: t1.id, selectionOrder: 0),
            TagAssignment(tagID: t2.id, selectionOrder: 0),
            TagAssignment(tagID: t3.id, selectionOrder: 0),
        ]

        let result = CaptionRenderer.render(
            assignments: assignments, tags: [t1, t2, t3], categories: [c1, c2, c3]
        )
        #expect(result == "first, middle, second")
    }

    // MARK: - Edge cases

    @Test func unknownTagIDIsSkipped() {
        let cat = TagCategory(name: "Subject", selectMode: .single, position: 0)
        let bogusID = UUID()
        let assignments = [TagAssignment(tagID: bogusID, selectionOrder: 0)]

        let result = CaptionRenderer.render(assignments: assignments, tags: [], categories: [cat])
        #expect(result == "")
    }

    @Test func singleSelectWithOneValueNoJoiner() {
        let cat = TagCategory(name: "Pose", selectMode: .single, position: 0)
        let t = Tag(canonicalString: "standing", categoryID: cat.id)
        let assignments = [TagAssignment(tagID: t.id, selectionOrder: 0)]

        let result = CaptionRenderer.render(assignments: assignments, tags: [t], categories: [cat])
        #expect(result == "standing")
    }
}
