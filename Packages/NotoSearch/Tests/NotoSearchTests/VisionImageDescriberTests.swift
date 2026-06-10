import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import NotoSearch

/// Test case index
/// 1. testEnglishTextIsRecognized — synthetic "Quarterly Budget Review 2026" render → ocrText contains "Budget"
/// 2. testChineseTextIsRecognized — synthetic "续租谈判 租金上涨" render (large glyphs) → ocrText contains "续租"
/// 3. testBlankImageProducesEmptyOCRWithoutThrowing — solid white image → no throw, empty ocrText
/// 4. testGarbageDataThrows — deterministic non-image bytes → undecodableImageData
/// 5. testDescriberVersion — stable version string recorded with every image chunk
struct VisionImageDescriberTests {
    private let describer = VisionImageDescriber()

    @Test func testEnglishTextIsRecognized() throws {
        let png = try DescriberTestImageRenderer.pngData(
            text: "Quarterly Budget Review 2026",
            fontSize: 48,
            width: 1024,
            height: 256
        )
        let description = try describer.describe(imageData: png)
        #expect(description.ocrText.range(of: "budget", options: .caseInsensitive) != nil,
                "OCR text was: \(description.ocrText)")
    }

    @Test func testChineseTextIsRecognized() throws {
        // Large glyphs on a big canvas — Vision's zh recognition needs
        // comfortably sized strokes on synthetic renders.
        let png = try DescriberTestImageRenderer.pngData(
            text: "续租谈判 租金上涨",
            fontSize: 96,
            width: 1024,
            height: 384
        )
        let description = try describer.describe(imageData: png)
        #expect(description.ocrText.contains("续租"),
                "OCR text was: \(description.ocrText)")
    }

    @Test func testBlankImageProducesEmptyOCRWithoutThrowing() throws {
        let png = try DescriberTestImageRenderer.pngData(
            text: nil,
            fontSize: 0,
            width: 256,
            height: 256
        )
        let description = try describer.describe(imageData: png)
        #expect(description.ocrText.isEmpty)
        // Labels may or may not be empty for a solid color — not asserted.
    }

    @Test func testGarbageDataThrows() {
        // Deterministic non-image bytes; no image format magic at offset 0.
        let garbage = Data((0..<512).map { UInt8(($0 * 73 + 19) % 251) })
        #expect(throws: VisionImageDescriberError.undecodableImageData) {
            _ = try describer.describe(imageData: garbage)
        }
    }

    @Test func testDescriberVersion() {
        #expect(describer.describerVersion == "vision-ocr-labels-v1")
    }
}

// MARK: - CoreGraphics/CoreText test-image rendering (no AppKit/UIKit)

enum DescriberTestImageRenderError: Error {
    case contextUnavailable
    case encodingFailed
}

/// Renders deterministic test images entirely with CoreGraphics + CoreText so
/// the package test target never touches AppKit/UIKit.
enum DescriberTestImageRenderer {
    /// White canvas; optional centered black text drawn as a single CTLine.
    /// The system UI font is used so CJK glyphs cascade to PingFang et al.
    static func pngData(text: String?, fontSize: CGFloat, width: Int, height: Int) throws -> Data {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw DescriberTestImageRenderError.contextUnavailable
        }

        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if let text, !text.isEmpty {
            let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
            ]
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: attributes)
            )
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            context.textPosition = CGPoint(
                x: max(0, (CGFloat(width) - lineWidth) / 2),
                y: CGFloat(height) / 2 - fontSize / 2
            )
            CTLineDraw(line, context)
        }

        guard let image = context.makeImage() else {
            throw DescriberTestImageRenderError.encodingFailed
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw DescriberTestImageRenderError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DescriberTestImageRenderError.encodingFailed
        }
        return data as Data
    }
}
