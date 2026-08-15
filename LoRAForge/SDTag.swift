import Foundation
import SwiftData
import TaggingCore

@Model
final class SDTag {
    var id: UUID

    var canonicalString: String
    var normalizedString: String
    var categoryID: UUID

    var category: SDCategory?

    init(canonicalString: String, category: SDCategory) {
        self.id = UUID()
        self.canonicalString = canonicalString
        self.normalizedString = DuplicateDetector.normalize(canonicalString)
        self.categoryID = category.id
        self.category = category
    }

    init(id: UUID, canonicalString: String, category: SDCategory) {
        self.id = id
        self.canonicalString = canonicalString
        self.normalizedString = DuplicateDetector.normalize(canonicalString)
        self.categoryID = category.id
        self.category = category
    }

    func toDomain() -> Tag {
        Tag(id: id, canonicalString: canonicalString, categoryID: categoryID)
    }
}
