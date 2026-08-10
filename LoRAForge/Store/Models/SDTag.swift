import Foundation
import SwiftData
import TaggingCore

@Model
final class SDTag {
    #Unique<SDTag>([\.canonicalString, \.categoryStableID])

    var stableID: UUID
    var canonicalString: String
    var categoryStableID: UUID

    init(from domain: Tag) {
        self.stableID = domain.id
        self.canonicalString = domain.canonicalString
        self.categoryStableID = domain.categoryID
    }

    func toDomain() -> Tag {
        Tag(id: stableID, canonicalString: canonicalString, categoryID: categoryStableID)
    }
}
