import Foundation

struct ProjectMetadata: Codable, Sendable {
    let id: UUID
    var name: String
    var categoryOrder: [UUID]
    var disabledCategories: Set<UUID>
    var exportBaseName: String?

    init(id: UUID = UUID(), name: String = "Untitled",
         categoryOrder: [UUID] = [], disabledCategories: Set<UUID> = []) {
        self.id = id
        self.name = name
        self.categoryOrder = categoryOrder
        self.disabledCategories = disabledCategories
    }
}
