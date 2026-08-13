import Foundation

public struct TagAssignment: Hashable, Sendable, Codable {
    public let tagID: UUID
    public let selectionOrder: Int

    public init(tagID: UUID, selectionOrder: Int) {
        self.tagID = tagID
        self.selectionOrder = selectionOrder
    }
}
