import Foundation

struct DatasetEntry: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var images: [EntryImage]

    // Caption
    var captionMode: CaptionMode
    var captionText: String
    var isLocked: Bool
    var lockedText: String?
    var tagAssignments: [CodableTagAssignment]

    init(id: UUID = UUID(), name: String, images: [EntryImage] = []) {
        self.id = id
        self.name = name
        self.images = images
        self.captionMode = .tagged
        self.captionText = ""
        self.isLocked = false
        self.lockedText = nil
        self.tagAssignments = []
    }

    // Backward-compatible decoding for documents saved before Phase 6
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        images = try c.decode([EntryImage].self, forKey: .images)
        captionMode = try c.decodeIfPresent(CaptionMode.self, forKey: .captionMode) ?? .tagged
        captionText = try c.decodeIfPresent(String.self, forKey: .captionText) ?? ""
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        lockedText = try c.decodeIfPresent(String.self, forKey: .lockedText)
        tagAssignments = try c.decodeIfPresent([CodableTagAssignment].self, forKey: .tagAssignments) ?? []
    }

    var finalImage: EntryImage? {
        images.first { $0.rank == .final }
    }

    var imageCount: Int {
        images.filter { $0.rank != .discarded }.count
    }

    var totalImageCount: Int {
        images.count
    }

    var hasCaptionContent: Bool {
        !captionText.isEmpty || !tagAssignments.isEmpty
    }
}

enum CaptionMode: String, Codable, Sendable, CaseIterable {
    case tagged
    case manual
    case ollama

    var label: String {
        switch self {
        case .tagged: "Tagged"
        case .manual: "Manual"
        case .ollama: "Ollama"
        }
    }
}

struct CodableTagAssignment: Codable, Sendable, Hashable {
    let tagID: UUID
    var selectionOrder: Int
}

struct EntryImage: Identifiable, Codable, Sendable {
    let id: UUID
    var rank: ImageRank
    let filename: String

    init(id: UUID = UUID(), rank: ImageRank = .candidate, filename: String) {
        self.id = id
        self.rank = rank
        self.filename = filename
    }
}

enum ImageRank: String, Codable, CaseIterable, Sendable {
    case `final`
    case shortlist
    case candidate
    case discarded

    var label: String {
        switch self {
        case .final: "Final"
        case .shortlist: "Shortlist"
        case .candidate: "Candidate"
        case .discarded: "Discarded"
        }
    }

    var systemImage: String? {
        switch self {
        case .final: "star.fill"
        case .shortlist: "star"
        case .candidate: nil
        case .discarded: "trash"
        }
    }

    var defaultVisible: Bool {
        self != .discarded
    }
}
