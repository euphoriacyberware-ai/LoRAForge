import Foundation

/// A common image proportion, written long side first (16:9, not 9:16).
nonisolated struct AspectRatio: Hashable, Identifiable, Sendable {
    let long: Int
    let short: Int

    var id: String { label }
    var label: String { "\(long):\(short)" }
    var value: Double { Double(long) / Double(short) }
    var isSquare: Bool { long == short }

    /// The label as shown in the given orientation (9:16 when portrait).
    func label(landscape: Bool) -> String {
        landscape || isSquare ? label : "\(short):\(long)"
    }

    static let common: [AspectRatio] = [
        AspectRatio(long: 1, short: 1),
        AspectRatio(long: 5, short: 4),
        AspectRatio(long: 4, short: 3),
        AspectRatio(long: 3, short: 2),
        AspectRatio(long: 16, short: 9),
        AspectRatio(long: 21, short: 9),
    ]
}

/// Width and height arithmetic for the configuration form's size controls.
///
/// Draw Things sizes are multiples of 64, so sizes derived from a ratio and a pixel target are
/// the nearest multiples of 64 and only approximate both.
nonisolated enum ImageSize {
    /// One megapixel, in Draw Things' sense: 1024 × 1024.
    static let megapixel = 1024.0 * 1024.0
    static let step = 64

    static let megapixelPresets: [Double] = [1, 1.5, 2, 3, 4]

    /// Ratio tolerance when recognising a size as one of the common ratios.
    static let ratioTolerance = 0.05
    /// Pixel-count tolerance when recognising a size as one of the megapixel presets.
    static let megapixelTolerance = 0.15

    /// The multiple-of-64 size closest to `ratio` with about `pixels` pixels.
    ///
    /// Searches the multiples of 64 near the ideal long and short sides and keeps the pair
    /// with the smallest combined proportion and area error. `accept` can rule pairs out.
    static func dimensions(
        ratio: Double, landscape: Bool, pixels: Double,
        accept: (_ long: Int, _ short: Int) -> Bool = { _, _ in true }
    ) -> (width: Int, height: Int) {
        let ratio = max(ratio, 1)
        let idealLong = (pixels * ratio).squareRoot()
        let idealShort = idealLong / ratio

        var best: (long: Int, short: Int)?
        var bestScore = Double.infinity
        for long in candidates(around: idealLong) {
            for short in candidates(around: idealShort) where short <= long && accept(long, short) {
                let ratioError = abs(log(Double(long) / Double(short) / ratio))
                let areaError = abs(log(Double(long * short) / pixels))
                // Proportion matters more than hitting the pixel target exactly.
                let score = ratioError * 2 + areaError
                if score < bestScore {
                    bestScore = score
                    best = (long, short)
                }
            }
        }
        let pick = best ?? (step, step)
        return landscape ? (pick.long, pick.short) : (pick.short, pick.long)
    }

    /// As above for a common ratio, keeping only sizes that read back as that ratio — at small
    /// sizes, 64-pixel steps can otherwise make 4:3 indistinguishable from 5:4.
    static func dimensions(ratio: AspectRatio, landscape: Bool, megapixels: Double) -> (width: Int, height: Int) {
        let pixels = megapixels * megapixel
        return dimensions(ratio: ratio.value, landscape: landscape, pixels: pixels) { long, short in
            matchingRatio(width: long, height: short) == ratio
        }
    }

    private static func candidates(around ideal: Double) -> [Int] {
        let center = Int((ideal / Double(step)).rounded())
        return (center - 2...center + 2).map { $0 * step }.filter { $0 >= step }
    }

    static func isLandscape(width: Int, height: Int) -> Bool {
        width >= height
    }

    static func megapixels(width: Int, height: Int) -> Double {
        Double(width * height) / megapixel
    }

    /// The common ratio closest to the size's proportion, if within tolerance; nil is custom.
    static func matchingRatio(width: Int, height: Int) -> AspectRatio? {
        guard width > 0, height > 0 else { return nil }
        let value = Double(max(width, height)) / Double(min(width, height))
        let closest = AspectRatio.common.min { abs(log(value / $0.value)) < abs(log(value / $1.value)) }
        guard let closest, abs(value / closest.value - 1) <= ratioTolerance else { return nil }
        return closest
    }

    /// The megapixel preset closest to the size's pixel count, if within tolerance.
    static func matchingPreset(width: Int, height: Int) -> Double? {
        let actual = megapixels(width: width, height: height)
        guard actual > 0 else { return nil }
        let closest = megapixelPresets.min { abs(log(actual / $0)) < abs(log(actual / $1)) }
        guard let closest, abs(actual / closest - 1) <= megapixelTolerance else { return nil }
        return closest
    }
}
