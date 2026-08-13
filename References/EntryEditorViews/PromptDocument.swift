import SwiftUI

// MARK: - Supporting types

enum PromptTab: String, CaseIterable, Identifiable {
    case prompt
    case negative

    var id: Self { self }

    var title: String {
        switch self {
        case .prompt: "Prompt"
        case .negative: "Negative"
        }
    }
}

enum CaptionMode: String, CaseIterable, Identifiable {
    case text
    case tags

    var id: Self { self }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .tags: "tag"
        }
    }
}

struct ImageSlot: Identifiable {
    let id = UUID()
    var image: Image?
}

// MARK: - Document

@Observable
final class PromptDocument {

    // Column 1
    var name = ""
    var prompt = ""
    var negativePrompt = ""

    var captionMode: CaptionMode = .text {
        didSet { reconcileCaption(from: oldValue) }
    }
    var caption = ""
    var captionTags: [String] = []

    // Column 2
    var useCustomSeed = false
    var seed = 0
    var images: [ImageSlot] = (0..<4).map { _ in ImageSlot() }
    var selectedImageID: ImageSlot.ID?

    var availableTags: [String] = [
        "portrait", "landscape", "studio lighting", "golden hour", "film grain",
        "wide angle", "macro", "monochrome", "high contrast", "soft focus",
        "watercolor", "oil painting", "line art", "isometric", "cinematic"
    ]
    var selectedTags: Set<String> = []

    // Column 3
    var useCustomConfiguration = false
    var configuration = PromptDocument.defaultConfiguration

    // MARK: Actions

    func randomizeSeed() {
        seed = Int.random(in: 0...4_294_967_295)
    }

    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    /// Stand-in for whatever generates a caption — a model call, an image
    /// analysis pass, etc. Replace the body; the call site stays the same.
    func generateCaption() {
        let generated = selectedTags.isEmpty
            ? ["untitled", "draft"]
            : selectedTags.sorted()

        switch captionMode {
        case .text:
            caption = generated.joined(separator: ", ")
        case .tags:
            captionTags = generated
        }
    }

    /// Keeps the two caption representations in sync when the mode flips, so
    /// switching back and forth never silently drops what was typed.
    private func reconcileCaption(from oldMode: CaptionMode) {
        guard oldMode != captionMode else { return }

        switch captionMode {
        case .tags:
            captionTags = caption
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        case .text:
            caption = captionTags.joined(separator: ", ")
        }
    }

    static let defaultConfiguration = """
    {
      "steps": 30,
      "cfg_scale": 7.0,
      "sampler": "dpmpp_2m",
      "scheduler": "karras",
      "width": 1024,
      "height": 1024,
      "batch_size": 4
    }
    """
}
