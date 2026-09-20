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
/// | `withoutImageTextSpansTheCard` | no thumbnail → text column fills the width |
/// | `withImageThumbnailIsTrailingSquare` | thumbnail is a square flush with the trailing edge |
/// | `narrowCardCapsThumbnailWidth` | thumbnail never eats more than 40% of a narrow card |
/// | `zeroWidthIsSafe` | degenerate sizes produce empty, not negative, rects |
/// | `downsamplerBoundsTheLongestSide` | a 1200px image comes back ≤ 200px on its long side |
/// | `downsamplerRejectsGarbage` | non-image bytes return nil rather than crash |
/// | `downsamplerReportsPixelSize` | size probe reads dimensions without decoding |
@Suite("LinkPreviewCardLayout")
struct LinkPreviewCardLayoutTests {
    @Test("without image the text column spans the card")
    func withoutImageTextSpansTheCard() {
        let layout = LinkPreviewCardLayout(width: 320, height: 96, hasImage: false, padding: 12)
        #expect(layout.imageRect == nil)
        #expect(layout.textRect == CGRect(x: 12, y: 12, width: 296, height: 72))
    }

    @Test("with image the thumbnail is a trailing square")
    func withImageThumbnailIsTrailingSquare() {
        let layout = LinkPreviewCardLayout(width: 320, height: 96, hasImage: true, padding: 12)
        #expect(layout.imageRect == CGRect(x: 224, y: 0, width: 96, height: 96))
        #expect(layout.textRect == CGRect(x: 12, y: 12, width: 200, height: 72))
    }

    @Test("narrow card caps the thumbnail width")
    func narrowCardCapsThumbnailWidth() {
        let layout = LinkPreviewCardLayout(width: 150, height: 96, hasImage: true, padding: 12)
        #expect(layout.imageRect?.width == 60)
        #expect(layout.imageRect?.maxX == 150)
        #expect(layout.textRect.maxX == 78)
    }

    @Test("zero width is safe")
    func zeroWidthIsSafe() {
        let layout = LinkPreviewCardLayout(width: 0, hasImage: true)
        #expect(layout.imageRect == nil)
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
