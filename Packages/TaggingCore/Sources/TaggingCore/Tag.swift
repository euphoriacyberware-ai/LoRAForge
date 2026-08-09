import Foundation

public struct Tag: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let canonicalString: String
    public let categoryID: UUID

    public init(id: UUID = UUID(), canonicalString: String, categoryID: UUID) {
        self.id = id
        self.canonicalString = canonicalString
        self.categoryID = categoryID
    }
}
