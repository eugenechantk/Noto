import CoreGraphics
import Testing
@testable import Noto

/// Cross-platform tests for the shared todo-marker renderer.
///
/// Deliberately **not** wrapped in `#if os(iOS)`. `NotoTests` is a member of both the
/// `Noto-iOS` and `Noto-macOS` schemes, so an ungated suite runs on both platforms and any
/// divergence in the shared drawing layer fails the build on whichever side broke.
///
/// This suite exists because todo markers rendered on iOS and silently did not render on
/// macOS: the drawing lived inside `TodoMarkerButton`, a `UIControl`, so it was compiled only
/// for iOS. The geometry was shared and tested; the *painting* was not, and that gap is what
/// these tests close.
///
/// | Test | Asserts |
/// |---|---|
/// | `uncheckedMarkerPaintsPixels` | An unchecked marker actually paints (outline circle) |
/// | `checkedMarkerPaintsPixels` | A checked marker actually paints (filled circle + tick) |
/// | `checkedMarkerPaintsMoreThanUnchecked` | Filled state covers more pixels than the outline |
/// | `rendererPaintsNothingOutsideMarkerRect` | Drawing stays inside its own marker rect |
/// | `markerRectTracksSymbolGeometry` | Symbol rect stays within the hit-target rect |
@Suite("Todo marker renderer (cross-platform)")
struct TodoMarkerRendererTests {

    /// Renders one marker into an isolated ARGB bitmap and returns the number of non-blank pixels.
    private func paintedPixelCount(
        isChecked: Bool,
        canvas: CGSize = CGSize(width: 64, height: 64),
        markerRect: CGRect? = nil
    ) throws -> Int {
        let width = Int(canvas.width)
        let height = Int(canvas.height)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        let context = try #require(pixels.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        })

        let rect = markerRect ?? CGRect(
            x: 8,
            y: 8,
            width: MarkdownVisualSpec.todoControlSize,
            height: MarkdownVisualSpec.todoControlSize
        )
        TodoMarkerRenderer.draw(in: context, markerRect: rect, isChecked: isChecked)

        let data = try #require(context.data)
        let buffer = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        var painted = 0
        for index in stride(from: 3, to: bytesPerRow * height, by: 4) where buffer[index] > 0 {
            painted += 1
        }
        return painted
    }

    @Test("An unchecked todo marker paints a visible outline on every platform")
    func uncheckedMarkerPaintsPixels() throws {
        let painted = try paintedPixelCount(isChecked: false)
        #expect(painted > 0, "unchecked marker drew nothing — macOS regression")
    }

    @Test("A checked todo marker paints a visible fill and checkmark on every platform")
    func checkedMarkerPaintsPixels() throws {
        let painted = try paintedPixelCount(isChecked: true)
        #expect(painted > 0, "checked marker drew nothing — macOS regression")
    }

    @Test("The checked marker is filled, so it covers more pixels than the outline")
    func checkedMarkerPaintsMoreThanUnchecked() throws {
        let unchecked = try paintedPixelCount(isChecked: false)
        let checked = try paintedPixelCount(isChecked: true)
        #expect(checked > unchecked)
    }

    @Test("Drawing stays inside the marker rect and does not bleed into the text column")
    func rendererPaintsNothingOutsideMarkerRect() throws {
        // Place the marker fully outside the canvas; nothing should be painted.
        let offscreen = CGRect(
            x: 200,
            y: 200,
            width: MarkdownVisualSpec.todoControlSize,
            height: MarkdownVisualSpec.todoControlSize
        )
        let painted = try paintedPixelCount(isChecked: true, markerRect: offscreen)
        #expect(painted == 0)
    }

    @Test("Symbol geometry stays within the hit-target rect on every platform")
    func markerRectTracksSymbolGeometry() {
        let marker = TodoMarkerGeometry.markerRect(contentLeadingX: 40, lineMidY: 20)
        let symbol = TodoMarkerGeometry.symbolRect(in: marker)

        #expect(marker.contains(symbol))
        #expect(abs(symbol.width - MarkdownVisualSpec.todoSymbolSize) < 0.5)
        #expect(abs(symbol.midY - marker.midY) < 0.5)
    }
}
