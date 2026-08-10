import Foundation

struct DatasetEntry: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var images: [EntryImage]

    init(id: UUID = UUID(), name: String, images: [EntryImage] = []) {
        self.id = id
        self.name = name
        self.images = images
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
