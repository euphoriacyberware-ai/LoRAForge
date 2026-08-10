import Foundation
import TaggingCore

struct SchemaSnapshot: Codable, Sendable {
    var tags: [TagSnapshot]
    var categories: [CategorySnapshot]

    init(tags: [TagSnapshot] = [], categories: [CategorySnapshot] = []) {
        self.tags = tags
        self.categories = categories
    }
}

struct TagSnapshot: Codable, Sendable, Identifiable {
    let id: UUID
    let canonicalString: String
    let categoryID: UUID

    init(from tag: Tag) {
        self.id = tag.id
        self.canonicalString = tag.canonicalString
        self.categoryID = tag.categoryID
    }

    func toDomainTag() -> Tag {
        Tag(id: id, canonicalString: canonicalString, categoryID: categoryID)
    }
}

enum SnapshotSelectMode: String, Codable, Sendable {
    case single
    case multi

    init(from mode: SelectMode) {
        self = mode == .single ? .single : .multi
    }

    var toDomain: SelectMode {
        self == .single ? .single : .multi
    }
}

struct CategorySnapshot: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let selectMode: SnapshotSelectMode
    let prefix: String?
    let highThreshold: Double
    let lowThreshold: Double

    init(from category: TagCategory) {
        self.id = category.id
        self.name = category.name
        self.selectMode = SnapshotSelectMode(from: category.selectMode)
        self.prefix = category.prefix
        self.highThreshold = category.highThreshold
        self.lowThreshold = category.lowThreshold
    }

    func toDomainCategory(isBuiltIn: Bool = false) -> TagCategory {
        TagCategory(
            id: id, name: name, selectMode: selectMode.toDomain,
            prefix: prefix, position: 0,
            highThreshold: highThreshold, lowThreshold: lowThreshold,
            isBuiltIn: isBuiltIn
        )
    }
}
