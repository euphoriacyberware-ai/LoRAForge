import Foundation

public struct TagCategory: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var selectMode: SelectMode
    public var prefix: String?
    public var position: Int
    public var isEnabled: Bool
    public var highThreshold: Double
    public var lowThreshold: Double
    public let isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        selectMode: SelectMode,
        prefix: String? = nil,
        position: Int,
        isEnabled: Bool = true,
        highThreshold: Double = 0.70,
        lowThreshold: Double = 0.10,
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
