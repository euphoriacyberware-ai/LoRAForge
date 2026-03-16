import SwiftUI

#if DEBUG

// MARK: - Sample Data

enum PreviewData {

    static let sourceImageID1 = UUID()
    static let sourceImageID2 = UUID()
    static let promptID1 = UUID()
    static let promptID2 = UUID()
    static let promptID3 = UUID()

    static let sourceImages: [SourceImage] = [
        SourceImage(id: sourceImageID1, filename: "portrait_01.png", label: "Portrait"),
        SourceImage(id: sourceImageID2, filename: "landscape_01.png", label: nil),
    ]

    static let generatedImages: [GeneratedImage] = [
        GeneratedImage(id: UUID(), filename: "gen1.png", rank: .candidate, caption: nil, generatedAt: Date(), seed: 42),
        GeneratedImage(id: UUID(), filename: "gen2.png", rank: .shortlisted, caption: "A vibrant portrait", generatedAt: Date(), seed: 108),
        GeneratedImage(id: UUID(), filename: "gen3.png", rank: .final_, caption: "Final selected image", generatedAt: Date(), seed: 256),
        GeneratedImage(id: UUID(), filename: "gen4.png", rank: .discarded, caption: nil, generatedAt: Date(), seed: 999),
    ]

    static let prompts: [Prompt] = [
        Prompt(
            id: promptID1,
            order: 0,
            text: "A portrait of a person in dramatic lighting, oil painting style",
            sourceImageIDs: [sourceImageID1],
            generateCount: 4,
            configurationOverrideJSON: nil,
            generatedImages: generatedImages
        ),
        Prompt(
            id: promptID2,
            order: 1,
            text: "Landscape at sunset with rolling hills",
            sourceImageIDs: [sourceImageID2],
            generateCount: 4,
            configurationOverrideJSON: nil,
            generatedImages: []
        ),
        Prompt(
            id: promptID3,
            order: 2,
            text: "",
            sourceImageIDs: [],
            generateCount: 4,
            configurationOverrideJSON: nil,
            generatedImages: []
        ),
    ]

    static var sampleProject: Project {
        Project(
            id: UUID(),
            name: "Sample Project",
            createdAt: Date(),
            modifiedAt: Date(),
            generationConnectionID: nil,
            captionConnectionID: nil,
            baseConfigurationJSON: "{\n  \"steps\": 20,\n  \"seed\": 0\n}",
            sourceImages: sourceImages,
            prompts: prompts
        )
    }

    static var sampleDocument: LoRAForgeDocument {
        let doc = LoRAForgeDocument()
        doc.project = sampleProject
        return doc
    }
}

#endif
