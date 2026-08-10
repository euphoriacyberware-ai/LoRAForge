import Foundation
import SwiftData
import TaggingCore

@Model
final class SDCategory {
    var id: UUID

    var name: String
    var selectModeRaw: String
    var prefix: String?
    var position: Int
    var isEnabled: Bool
    var highThreshold: Int
    var lowThreshold: Int
    var isBuiltIn: Bool

    @Relationship(deleteRule: .cascade)
    var tags: [SDTag] = []

    init(from category: TagCategory) {
        self.id = category.id
        self.name = category.name
        self.selectModeRaw = category.selectMode.rawValue
        self.prefix = category.prefix
        self.position = category.position
        self.isEnabled = category.isEnabled
        self.highThreshold = category.highThreshold
        self.lowThreshold = category.lowThreshold
        self.isBuiltIn = category.isBuiltIn
    }

    func toDomain() -> TagCategory {
        TagCategory(
            id: id,
            name: name,
            selectMode: TagCategory.SelectMode(rawValue: selectModeRaw) ?? .single,
            prefix: prefix,
            position: position,
            isEnabled: isEnabled,
            highThreshold: highThreshold,
            lowThreshold: lowThreshold,
            isBuiltIn: isBuiltIn
        )
    }

    func update(from category: TagCategory) {
        name = category.name
        selectModeRaw = category.selectMode.rawValue
        prefix = category.prefix
        position = category.position
        isEnabled = category.isEnabled
        highThreshold = category.highThreshold
        lowThreshold = category.lowThreshold
    }
}
