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
    var referenceImages: [ReferenceImageDocument]

    init(name: String, categories: [TagCategory]) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.categoryOrder = categories.sorted { $0.position < $1.position }.map(\.id)
        self.categoryEnabled = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.isEnabled) })
        self.entries = []
        self.referenceImages = []
    }

    var totalImageCount: Int {
        entries.reduce(0) { $0 + $1.activeImageCount }
    }

    var discardedImageCount: Int {
        entries.reduce(0) { $0 + $1.images.filter { $0.rank == .discarded }.count }
    }
}

enum CaptionMode: String, Codable, Sendable {
    case tagged
    case manual
    case ollama
}

struct EntryDocument: Codable, Identifiable {
    let id: UUID
    var name: String
    var position: Int
    var images: [ImageDocument]
    var assignments: [AssignmentDocument]
    var captionMode: CaptionMode
    var manualCaptionText: String
    var lockedCaptionText: String?
    var generationPrompt: String
    var generationNegativePrompt: String
    var generationSeed: Int64?
    var useCustomSeed: Bool
    var generationConfigJSON: String
    var useCustomConfig: Bool
    var referenceImageIDs: [UUID]

    var isLocked: Bool { lockedCaptionText != nil }

    init(name: String, position: Int) {
        self.id = UUID()
        self.name = name
        self.position = position
        self.images = []
        self.assignments = []
        self.captionMode = .tagged
        self.manualCaptionText = ""
        self.lockedCaptionText = nil
        self.generationPrompt = ""
        self.generationNegativePrompt = ""
        self.generationSeed = nil
        self.useCustomSeed = false
        self.generationConfigJSON = ""
        self.useCustomConfig = false
        self.referenceImageIDs = []
    }

    var finalImage: ImageDocument? {
        images.first { $0.rank == .final }
    }

    var activeImageCount: Int {
        images.filter { $0.rank != .discarded }.count
    }
}

struct ImageDocument: Codable, Identifiable {
    let id: UUID
    let filename: String
    var rank: ImageRank
    let addedAt: Date
    var provenance: ImageProvenance?

    init(filename: String, rank: ImageRank = .candidate, provenance: ImageProvenance? = nil) {
        self.id = UUID()
        self.filename = filename
        self.rank = rank
        self.addedAt = Date()
        self.provenance = provenance
    }
}

struct ImageProvenance: Codable {
    let prompt: String
    let negativePrompt: String
    let seed: Int64
}

struct ReferenceImageDocument: Codable, Identifiable {
    let id: UUID
    let filename: String
    let contentHash: String
    let addedAt: Date

    init(filename: String, contentHash: String) {
        self.id = UUID()
        self.filename = filename
        self.contentHash = contentHash
        self.addedAt = Date()
    }
}

enum ImageRank: String, Codable, CaseIterable, Sendable {
    case `final`
    case shortlist
    case candidate
    case discarded

    var label: String {
        switch self {
        case .final: return "Final"
        case .shortlist: return "Shortlist"
        case .candidate: return "Candidate"
        case .discarded: return "Discarded"
        }
    }

    var badgeIcon: String? {
        switch self {
        case .final: return "star.fill"
        case .shortlist: return "star"
        case .candidate: return nil
        case .discarded: return "trash"
        }
    }

    var visibleByDefault: Bool {
        self != .discarded
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
