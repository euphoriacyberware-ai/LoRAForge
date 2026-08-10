import Foundation
import TaggingCore

struct ProjectDocument: Codable {
    let id: UUID
    var name: String
    let createdAt: Date
    var categoryOrder: [UUID]
    var categoryEnabled: [UUID: Bool]
    var lastExportBaseName: String?
    var entries: [EntryDocument]

    init(name: String, categories: [TagCategory]) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.categoryOrder = categories.sorted { $0.position < $1.position }.map(\.id)
        self.categoryEnabled = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.isEnabled) })
        self.entries = []
    }
}

struct EntryDocument: Codable, Identifiable {
    let id: UUID
    var name: String
    var position: Int
    var assignments: [AssignmentDocument]

    init(name: String, position: Int) {
        self.id = UUID()
        self.name = name
        self.position = position
        self.assignments = []
    }
}

struct AssignmentDocument: Codable {
    let tagID: UUID
    let selectionOrder: Int
}

struct SchemaSnapshot: Codable {
    var categories: [CategorySnapshot]
    var tags: [TagSnapshot]

    struct CategorySnapshot: Codable, Identifiable {
        let id: UUID
        let name: String
        let selectMode: String
        let prefix: String?
        let highThreshold: Int
        let lowThreshold: Int
    }

    struct TagSnapshot: Codable, Identifiable {
        let id: UUID
        let canonicalString: String
        let categoryID: UUID
    }

    init(categories: [TagCategory], tags: [Tag]) {
        self.categories = categories.map {
            CategorySnapshot(
                id: $0.id, name: $0.name, selectMode: $0.selectMode.rawValue,
                prefix: $0.prefix, highThreshold: $0.highThreshold, lowThreshold: $0.lowThreshold
            )
        }
        self.tags = tags.map {
            TagSnapshot(id: $0.id, canonicalString: $0.canonicalString, categoryID: $0.categoryID)
        }
    }
}
