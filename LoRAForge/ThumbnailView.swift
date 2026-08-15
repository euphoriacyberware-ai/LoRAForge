import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Displays an image thumbnail loaded asynchronously and downscaled.
///
/// Uses a shared `ThumbnailStore` that limits concurrent loads and caches
/// results. Each thumbnail is an `@Observable` item — only the specific
/// view re-renders when its image finishes loading. No per-view `.task`
/// modifiers.
struct ThumbnailView: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        let item = ThumbnailStore.shared.item(for: url, size: size)
        if let image = item.image {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .overlay {
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
        }
    }
}

// MARK: - Thumbnail Item

@Observable
final class ThumbnailItem {
    var image: Image?
}

// MARK: - Thumbnail Store

@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private var items: [URL: ThumbnailItem] = [:]
    private var activeLoads = 0
    private var pending: [(item: ThumbnailItem, url: URL, size: CGFloat)] = []
    private let maxConcurrent = 4
    private let maxCached = 600

    func clearAll() {
        items.removeAll()
        pending.removeAll()
    }

    func item(for url: URL, size: CGFloat) -> ThumbnailItem {
        if let existing = items[url] { return existing }
        let item = ThumbnailItem()
        items[url] = item
        enqueue(item: item, url: url, size: 200)
        return item
    }

    private func enqueue(item: ThumbnailItem, url: URL, size: CGFloat) {
        if activeLoads < maxConcurrent {
            startLoad(item: item, url: url, size: size)
        } else {
            pending.append((item, url, size))
        }
    }

    private func startLoad(item: ThumbnailItem, url: URL, size: CGFloat) {
        activeLoads += 1
        Task.detached(priority: .utility) {
            let image = Self.loadThumbnail(url: url, pointSize: size)
            await MainActor.run { [weak self] in
                item.image = image
                self?.didFinishLoad()
            }
        }
    }

    private func didFinishLoad() {
        activeLoads -= 1
        while activeLoads < maxConcurrent, !pending.isEmpty {
            let next = pending.removeFirst()
            startLoad(item: next.item, url: next.url, size: next.size)
        }
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        guard items.count > maxCached else { return }
        // Drop entries whose item has already been displayed (image loaded).
        // Keep the most recently added by removing from the front.
        var toRemove: [URL] = []
        for (url, item) in items {
            if item.image != nil { toRemove.append(url) }
            if items.count - toRemove.count <= maxCached / 2 { break }
        }
        for url in toRemove { items.removeValue(forKey: url) }
    }

    // MARK: - Image Loading (runs on detached task)

    nonisolated private static func loadThumbnail(url: URL, pointSize: CGFloat) -> Image? {
        #if os(macOS)
        let scale: CGFloat = 2.0
        #else
        let scale: CGFloat = 2.0
        #endif
        let pixelSize = pointSize * scale

        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        #if os(macOS)
        let cgW = CGFloat(cgImage.width)
        let cgH = CGFloat(cgImage.height)
        let nsSize = NSSize(width: cgW / scale, height: cgH / scale)
        let nsImage = NSImage(cgImage: cgImage, size: nsSize)
        return Image(nsImage: nsImage)
        #else
        let uiImage = UIImage(cgImage: cgImage)
        return Image(uiImage: uiImage)
        #endif
    }
}
