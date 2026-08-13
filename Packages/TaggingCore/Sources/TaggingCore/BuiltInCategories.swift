import Foundation

public enum BuiltInCategory: String, CaseIterable, Sendable {
    case subject
    case framing
    case cameraAngle
    case pose
    case gaze
    case expression
    case lighting
    case hairstyle
    case clothing
    case heldItems
    case backgroundLocation

    public var id: UUID {
        switch self {
        case .subject:            return UUID(uuidString: "B0000001-0000-0000-0000-000000000000")!
        case .framing:            return UUID(uuidString: "B0000002-0000-0000-0000-000000000000")!
        case .cameraAngle:        return UUID(uuidString: "B0000003-0000-0000-0000-000000000000")!
        case .pose:               return UUID(uuidString: "B0000004-0000-0000-0000-000000000000")!
        case .gaze:               return UUID(uuidString: "B0000005-0000-0000-0000-000000000000")!
        case .expression:         return UUID(uuidString: "B0000006-0000-0000-0000-000000000000")!
        case .lighting:           return UUID(uuidString: "B0000007-0000-0000-0000-000000000000")!
        case .hairstyle:          return UUID(uuidString: "B0000008-0000-0000-0000-000000000000")!
        case .clothing:           return UUID(uuidString: "B0000009-0000-0000-0000-000000000000")!
        case .heldItems:          return UUID(uuidString: "B000000A-0000-0000-0000-000000000000")!
        case .backgroundLocation: return UUID(uuidString: "B000000B-0000-0000-0000-000000000000")!
        }
    }

    public var defaultCategory: TagCategory {
        switch self {
        case .subject:
            return TagCategory(id: id, name: "Subject", selectMode: .single, position: 0, isBuiltIn: true)
        case .framing:
            return TagCategory(id: id, name: "Framing", selectMode: .single, position: 1, isBuiltIn: true)
        case .cameraAngle:
            return TagCategory(id: id, name: "Camera Angle", selectMode: .single, position: 2, isBuiltIn: true)
        case .pose:
            return TagCategory(id: id, name: "Pose", selectMode: .single, position: 3, isBuiltIn: true)
        case .gaze:
            return TagCategory(id: id, name: "Gaze", selectMode: .single, position: 4, isBuiltIn: true)
        case .expression:
            return TagCategory(id: id, name: "Expression", selectMode: .single, position: 5, isBuiltIn: true)
        case .lighting:
            return TagCategory(id: id, name: "Lighting", selectMode: .single, position: 6, isBuiltIn: true)
        case .hairstyle:
            return TagCategory(id: id, name: "Hairstyle", selectMode: .single, position: 7, isBuiltIn: true)
        case .clothing:
            return TagCategory(id: id, name: "Clothing", selectMode: .multi, prefix: "wearing", position: 8, isBuiltIn: true)
        case .heldItems:
            return TagCategory(id: id, name: "Held-Items", selectMode: .multi, prefix: "holding", position: 9, isBuiltIn: true)
        case .backgroundLocation:
            return TagCategory(id: id, name: "Background-Location", selectMode: .single, position: 10, isBuiltIn: true)
        }
    }

    public static var defaultCategories: [TagCategory] {
        allCases.map(\.defaultCategory)
    }
}
