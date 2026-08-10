import Foundation
import SwiftData
import TaggingCore

@Model
final class SDTagCategory {
    #Unique<SDTagCategory>([\.stableID])

    var stableID: UUID
    var name: String
    var selectModeRaw: Int // 0 = single, 1 = multi
    var prefix: String?
    var position: Int
    var isEnabled: Bool
    var highThreshold: Double
    var lowThreshold: Double
    var isBuiltIn: Bool

    init(from domain: TagCategory) {
        self.stableID = domain.id
        self.name = domain.name
        self.selectModeRaw = domain.selectMode == .single ? 0 : 1
        self.prefix = domain.prefix
        self.position = domain.position
        self.isEnabled = domain.isEnabled
        self.highThreshold = domain.highThreshold
        self.lowThreshold = domain.lowThreshold
        self.isBuiltIn = domain.isBuiltIn
    }

    func toDomain() -> TagCategory {
        TagCategory(
            id: stableID,
            name: name,
            selectMode: selectModeRaw == 0 ? .single : .multi,
            prefix: prefix,
            position: position,
            isEnabled: isEnabled,
            highThreshold: highThreshold,
            lowThreshold: lowThreshold,
            isBuiltIn: isBuiltIn
        )
    }
}
