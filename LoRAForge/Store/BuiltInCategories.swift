import Foundation
import TaggingCore

enum BuiltInCategories {
    // Well-known UUIDs so every installation shares the same IDs for built-in categories.
    // This matters for project reconciliation (design §9.2).
    private enum ID {
        static let subject    = UUID(uuidString: "B1000000-0000-0000-0000-000000000001")!
        static let framing    = UUID(uuidString: "B1000000-0000-0000-0000-000000000002")!
        static let camera     = UUID(uuidString: "B1000000-0000-0000-0000-000000000003")!
        static let pose       = UUID(uuidString: "B1000000-0000-0000-0000-000000000004")!
        static let gaze       = UUID(uuidString: "B1000000-0000-0000-0000-000000000005")!
        static let expression = UUID(uuidString: "B1000000-0000-0000-0000-000000000006")!
        static let lighting   = UUID(uuidString: "B1000000-0000-0000-0000-000000000007")!
        static let hairstyle  = UUID(uuidString: "B1000000-0000-0000-0000-000000000008")!
        static let clothing   = UUID(uuidString: "B1000000-0000-0000-0000-000000000009")!
        static let heldItems  = UUID(uuidString: "B1000000-0000-0000-0000-00000000000A")!
        static let background = UUID(uuidString: "B1000000-0000-0000-0000-00000000000B")!
    }

    static let subjectID = ID.subject

    /// The eleven built-in categories from tagging doc §4.
    /// Each carries its own 70/10 threshold pair (tagging doc §8).
    static let all: [TagCategory] = [
        TagCategory(id: ID.subject,    name: "Subject",             selectMode: .single, prefix: nil,       position: 0,  highThreshold: 0.70, lowThreshold: 0.10, isBuiltIn: true),
        TagCategory(id: ID.framing,    name: "Framing",             selectMode: .single, prefix: nil,       position: 1,  highThreshold: 0.70, lowThreshold: 0.10, isBuiltIn: true),
        TagCategory(id: ID.camera,     name: "Camera Angle",        selectMode: .single, prefix: nil,       position: 2,  highThreshold: 0.70, lowThreshold: 0.10, isBuiltIn: true),
        TagCategory(id: ID.pose,       name: "Pose",                selectMode: .single, prefix: nil,       position: 3,  highThreshold: 0.70, lowThreshold: 0.10, isBuiltIn: true),
        TagCategory(id: ID.gaze,       name: "Gaze",                selectMode: .single, prefix: nil,       position: 4,  highThreshold: 0.70, lowThreshold: 0.10, isBuiltIn: true),
        TagCategory(id: ID.expression, name: "Expression",          selectMode: .single, prefix: nil,       position: 5,  highThreshold: 0.70, lowThreshold: 0.10, isBuiltIn: true),
        TagCategory(id: ID.lighting,   name: "Lighting",            selectMode: .single, prefix: nil,       position: 6,  highThreshold: 0.70, lowThreshold: 0.10, isBuiltIn: true),
        TagCategory(id: ID.hairstyle,  name: "Hairstyle",           selectMode: .single, prefix: nil,       position: 7,  highThreshold: 0.70, lowThreshold: 0.10, isBuiltIn: true),
        TagCategory(id: ID.clothing,   name: "Clothing",            selectMode: .multi,  prefix: "wearing", position: 8,  highThreshold: 0.70, lowThreshold: 0.10, isBuiltIn: true),
        TagCategory(id: ID.heldItems,  name: "Held-Items",          selectMode: .multi,  prefix: "holding", position: 9,  highThreshold: 0.70, lowThreshold: 0.10, isBuiltIn: true),
        TagCategory(id: ID.background, name: "Background-Location", selectMode: .single, prefix: nil,       position: 10, highThreshold: 0.70, lowThreshold: 0.10, isBuiltIn: true),
    ]
}
