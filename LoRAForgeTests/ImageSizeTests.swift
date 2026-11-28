import Testing
@testable import LoRAForge

struct ImageSizeTests {

    @Test func squareAtOneMegapixelIs1024() {
        let size = ImageSize.dimensions(ratio: AspectRatio(long: 1, short: 1), landscape: true, megapixels: 1)
        #expect(size.width == 1024 && size.height == 1024)
    }

    @Test func portraitSwapsSides() {
        let ratio = AspectRatio(long: 16, short: 9)
        let landscape = ImageSize.dimensions(ratio: ratio, landscape: true, megapixels: 1)
        let portrait = ImageSize.dimensions(ratio: ratio, landscape: false, megapixels: 1)
        #expect(landscape.width == 1344 && landscape.height == 768)
        #expect(portrait.width == 768 && portrait.height == 1344)
    }

    /// Every ratio at every preset, both orientations: multiples of 64, and the size reads back
    /// as the ratio and preset that produced it.
    @Test(arguments: AspectRatio.common)
    func everyRatioRoundTrips(ratio: AspectRatio) {
        for preset in ImageSize.megapixelPresets {
            for landscape in [true, false] {
                let size = ImageSize.dimensions(ratio: ratio, landscape: landscape, megapixels: preset)
                #expect(size.width % 64 == 0 && size.height % 64 == 0)
                #expect(size.width >= 64 && size.height >= 64)
                #expect(ImageSize.matchingRatio(width: size.width, height: size.height) == ratio,
                        "\(ratio.label) at \(preset) MP gave \(size.width)×\(size.height)")
                #expect(ImageSize.matchingPreset(width: size.width, height: size.height) == preset,
                        "\(ratio.label) at \(preset) MP gave \(size.width)×\(size.height)")
                if !ratio.isSquare {
                    #expect(ImageSize.isLandscape(width: size.width, height: size.height) == landscape)
                }
            }
        }
    }

    @Test func twoToOneIsRecognised() {
        #expect(ImageSize.matchingRatio(width: 1024, height: 512)?.label == "2:1")
        #expect(AspectRatio(long: 2, short: 1).label(landscape: false) == "1:2")
    }

    @Test func closeRatiosAreNotConfused() {
        #expect(ImageSize.matchingRatio(width: 1280, height: 1024)?.label == "5:4")
        #expect(ImageSize.matchingRatio(width: 1024, height: 768)?.label == "4:3")
        #expect(ImageSize.matchingRatio(width: 768, height: 1024)?.label == "4:3")
    }

    @Test func oddProportionIsCustom() {
        #expect(ImageSize.matchingRatio(width: 1024, height: 640) == nil)  // 1.6, between 3:2 and 16:9
        #expect(ImageSize.matchingRatio(width: 1344, height: 576) == nil)  // 21:9 is no longer offered
        #expect(ImageSize.matchingRatio(width: 1152, height: 1024) == nil) // 1.125
    }

    @Test func megapixelPresetMatching() {
        #expect(ImageSize.matchingPreset(width: 832, height: 1216) == 1)
        #expect(ImageSize.matchingPreset(width: 3072, height: 3072) == nil) // 9 MP
        #expect(ImageSize.megapixels(width: 1024, height: 512) == 0.5)
    }

    @Test func customProportionKeepsShapeWhenScaled() {
        // 1.125 proportion at 2 MP stays near 1.125.
        let size = ImageSize.dimensions(ratio: 1.125, landscape: true, pixels: 2 * ImageSize.megapixel)
        let proportion = Double(size.width) / Double(size.height)
        #expect(abs(proportion / 1.125 - 1) < 0.05)
        #expect(ImageSize.matchingPreset(width: size.width, height: size.height) == 2)
    }

    @Test func portraitLabelsFlip() {
        let ratio = AspectRatio(long: 16, short: 9)
        #expect(ratio.label(landscape: false) == "9:16")
        #expect(AspectRatio(long: 1, short: 1).label(landscape: false) == "1:1")
    }
}
