import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import NotoLinkPreview

/// Card geometry and image shrinking (SC5).
///
/// | Test | Covers |
/// | --- | --- |
/// | `bannerOnTopTextBelow` | full-width banner, text block inset below it |
/// | `cardMatchesAnImageLine` | one fixed height (an image line's 300 pt), whatever loads |
/// | `shortCardClampsTheBanner` | a card shorter than the banner never produces negative rects |
/// | `zeroWidthIsSafe` | degenerate sizes produce empty, not negative, rects |
/// | `downsamplerBoundsTheLongestSide` | a 1200px image comes back ≤ 200px on its long side |
/// | `downsamplerRejectsGarbage` | non-image bytes return nil rather than crash |
/// | `downsamplerReportsPixelSize` | size probe reads dimensions without decoding |
@Suite("LinkPreviewCardLayout")
struct LinkPreviewCardLayoutTests {
    @Test("banner on top, text below")
    func bannerOnTopTextBelow() {
        let layout = LinkPreviewCardLayout(width: 320, height: 300, padding: 12)
        #expect(layout.bannerRect == CGRect(x: 0, y: 0, width: 320, height: LinkPreviewCardLayout.bannerHeight))
        #expect(layout.textRect == CGRect(x: 12, y: LinkPreviewCardLayout.bannerHeight + 12, width: 296, height: 300 - LinkPreviewCardLayout.bannerHeight - 24))
    }

    @Test("card height matches an image line")
    func cardMatchesAnImageLine() {
        #expect(LinkPreviewCardLayout.defaultHeight == 300)
        #expect(LinkPreviewCardLayout(width: 320).bounds.height == 300)
    }

    @Test("short card clamps the banner")
    func shortCardClampsTheBanner() {
        let layout = LinkPreviewCardLayout(width: 200, height: 100, padding: 12)
        #expect(layout.bannerRect.height == 100)
        #expect(layout.textRect.height == 0)
    }

    @Test("zero width is safe")
    func zeroWidthIsSafe() {
        let layout = LinkPreviewCardLayout(width: 0)
        #expect(layout.bannerRect.width == 0)
        #expect(layout.textRect.width == 0)
        #expect(layout.bounds == CGRect(x: 0, y: 0, width: 0, height: LinkPreviewCardLayout.defaultHeight))
    }

    @Test("downsampler bounds the longest side")
    func downsamplerBoundsTheLongestSide() throws {
        let source = try #require(Self.pngData(width: 1200, height: 600))
        let shrunk = try #require(LinkPreviewImageDownsampler.downsample(source, maxPixelSize: 200))
        let size = try #require(LinkPreviewImageDownsampler.pixelSize(of: shrunk))
        #expect(size.width <= 200)
        #expect(size.height <= 200)
        #expect(size.width > size.height)
    }

    @Test("downsampler rejects garbage")
    func downsamplerRejectsGarbage() {
        #expect(LinkPreviewImageDownsampler.downsample(Data("nope".utf8), maxPixelSize: 100) == nil)
        #expect(LinkPreviewImageDownsampler.pixelSize(of: Data("nope".utf8)) == nil)
    }

    @Test("downsampler reports pixel size")
    func downsamplerReportsPixelSize() throws {
        let source = try #require(Self.pngData(width: 30, height: 20))
        let size = try #require(LinkPreviewImageDownsampler.pixelSize(of: source))
        #expect(size.width == 30)
        #expect(size.height == 20)
    }

    private static func pngData(width: Int, height: Int) -> Data? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
