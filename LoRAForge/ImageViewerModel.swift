import Foundation
import Observation

// The Image Viewer runs in its own window, a separate SwiftUI tree from the view that owns the
// project document. A binding or value handed to it at open time goes stale: nothing re-renders
// that tree when the document changes. The owning view instead pushes a small snapshot of what
// the viewer shows into an @Observable model, which the viewer's window observes directly.

// MARK: - Entry images

/// What the entry Image Viewer shows: entries in order, each with its images in the visible ranks.
nonisolated struct ImageViewerContent: Equatable, Sendable {
    struct Image: Equatable, Sendable {
        let id: UUID
        let filename: String
        let rank: ImageRank
    }

    struct Entry: Equatable, Sendable {
        let id: UUID
        let position: Int
        let name: String
        /// Only the images in the visible ranks.
        let images: [Image]
    }

    /// Every entry, including those with no visible images, so positions stay meaningful.
    var entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    init(document: ProjectDocument, visibleRanks: Set<ImageRank>) {
        entries = document.entries.map { entry in
            Entry(
                id: entry.id,
                position: entry.position,
                name: entry.name,
                images: entry.images
                    .filter { visibleRanks.contains($0.rank) }
                    .map { Image(id: $0.id, filename: $0.filename, rank: $0.rank) }
            )
        }
    }

    struct Selection: Equatable, Sendable {
        var entryID: UUID
        var imageID: UUID
    }

    func entry(_ id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Entries that have at least one visible image, in order.
    var navigableEntries: [Entry] {
        entries.filter { !$0.images.isEmpty }
    }

    func contains(_ selection: Selection) -> Bool {
        entry(selection.entryID)?.images.contains { $0.id == selection.imageID } ?? false
    }

    /// Where the viewer should be after the content changed from `old` to `self`.
    ///
    /// Keeps the current image while it is still visible, so images arriving never move the
    /// viewer. When it was removed or hidden: the image now at its old index in the same entry,
    /// then the next entry with a visible image, then the previous one. Nil when nothing is left.
    func reconciled(_ selection: Selection, from old: ImageViewerContent) -> Selection? {
        if contains(selection) { return selection }

        let oldIndex = old.entry(selection.entryID)?.images.firstIndex { $0.id == selection.imageID } ?? 0
        if let entry = entry(selection.entryID), !entry.images.isEmpty {
            let image = entry.images[min(oldIndex, entry.images.count - 1)]
            return Selection(entryID: entry.id, imageID: image.id)
        }

        // Look for a neighbouring entry, using the old order to find where the entry was.
        let oldOrder = old.entries.map(\.id)
        guard let oldPosition = oldOrder.firstIndex(of: selection.entryID) else {
            return navigableEntries.first.map { Selection(entryID: $0.id, imageID: $0.images[0].id) }
        }
        let after = oldOrder[(oldPosition + 1)...]
        let before = oldOrder[..<oldPosition].reversed()
        for id in Array(after) + Array(before) {
            if let entry = entry(id), let image = entry.images.first {
                return Selection(entryID: entry.id, imageID: image.id)
            }
        }
        return nil
    }
}

@Observable
@MainActor
final class ImageViewerModel {
    var content: ImageViewerContent

    init(content: ImageViewerContent = ImageViewerContent()) {
        self.content = content
    }
}

// MARK: - Reference images

/// What the reference Image Viewer shows: the project's reference images in order.
nonisolated struct ReferenceViewerContent: Equatable, Sendable {
    struct Image: Equatable, Sendable {
        let id: UUID
        let filename: String
    }

    var images: [Image]

    init(images: [Image] = []) {
        self.images = images
    }

    init(referenceImages: [ReferenceImageDocument]) {
        images = referenceImages.map { Image(id: $0.id, filename: $0.filename) }
    }

    /// Keeps the current reference while it exists; otherwise the one now at its old index;
    /// nil when there are none left.
    func reconciled(_ id: UUID, from old: ReferenceViewerContent) -> UUID? {
        if images.contains(where: { $0.id == id }) { return id }
        guard !images.isEmpty else { return nil }
        let oldIndex = old.images.firstIndex { $0.id == id } ?? 0
        return images[min(oldIndex, images.count - 1)].id
    }
}

@Observable
@MainActor
final class ReferenceViewerModel {
    var content: ReferenceViewerContent

    init(content: ReferenceViewerContent = ReferenceViewerContent()) {
        self.content = content
    }
}
