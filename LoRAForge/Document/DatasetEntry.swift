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

    // Generation
    var generationSettings: GenerationSettings

    init(id: UUID = UUID(), name: String, images: [EntryImage] = []) {
        self.id = id
        self.name = name
        self.images = images
        self.captionMode = .tagged
        self.captionText = ""
        self.isLocked = false
        self.lockedText = nil
        self.tagAssignments = []
        self.generationSettings = GenerationSettings()
    }

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
        generationSettings = try c.decodeIfPresent(GenerationSettings.self, forKey: .generationSettings) ?? GenerationSettings()
    }

    var finalImage: EntryImage? { images.first { $0.rank == .final } }
    var imageCount: Int { images.filter { $0.rank != .discarded }.count }
    var totalImageCount: Int { images.count }
    var hasCaptionContent: Bool { !captionText.isEmpty || !tagAssignments.isEmpty }
}

// MARK: - Generation Settings

struct GenerationSettings: Codable, Sendable {
    var prompt: String
    var negativePrompt: String
    var useCustomSeed: Bool
    var customSeed: Int64
    var configurationJSON: String

    init(prompt: String = "", negativePrompt: String = "",
         useCustomSeed: Bool = false, customSeed: Int64 = 0,
         configurationJSON: String = "{\n}") {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.useCustomSeed = useCustomSeed
        self.customSeed = customSeed
        self.configurationJSON = configurationJSON
    }
}

// MARK: - Image Provenance

struct ImageProvenance: Codable, Sendable {
    var prompt: String
    var negativePrompt: String
    var seed: Int64
    var configurationJSON: String
    var referenceImageIDs: [UUID]
}

// MARK: - Caption

enum CaptionMode: String, Codable, Sendable, CaseIterable {
    case tagged, manual, ollama
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

// MARK: - Entry Image

struct EntryImage: Identifiable, Codable, Sendable {
    let id: UUID
    var rank: ImageRank
    let filename: String
    var provenance: ImageProvenance?

    init(id: UUID = UUID(), rank: ImageRank = .candidate, filename: String, provenance: ImageProvenance? = nil) {
        self.id = id
        self.rank = rank
        self.filename = filename
        self.provenance = provenance
    }

    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        rank = try c.decode(ImageRank.self, forKey: .rank)
        filename = try c.decode(String.self, forKey: .filename)
        provenance = try c.decodeIfPresent(ImageProvenance.self, forKey: .provenance)
    }
}

enum ImageRank: String, Codable, CaseIterable, Sendable {
    case `final`, shortlist, candidate, discarded
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
    var defaultVisible: Bool { self != .discarded }
}
