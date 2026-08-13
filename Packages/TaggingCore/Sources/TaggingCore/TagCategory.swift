import Foundation

public struct TagCategory: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var selectMode: SelectMode
    public var prefix: String?
    public var position: Int
    public var isEnabled: Bool
    public var highThreshold: Int
    public var lowThreshold: Int
    public let isBuiltIn: Bool

    public enum SelectMode: String, Hashable, Sendable, Codable {
        case single
        case multi
    }

    public init(
        id: UUID = UUID(),
        name: String,
        selectMode: SelectMode,
        prefix: String? = nil,
        position: Int,
        isEnabled: Bool = true,
        highThreshold: Int = 70,
        lowThreshold: Int = 10,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.selectMode = selectMode
        self.prefix = prefix
        self.position = position
        self.isEnabled = isEnabled
        self.highThreshold = highThreshold
        self.lowThreshold = lowThreshold
        self.isBuiltIn = isBuiltIn
    }
}
