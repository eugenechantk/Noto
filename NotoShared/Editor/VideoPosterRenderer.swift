import AVFoundation
import CoreGraphics
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Turns a local video file into a still for the editor's image block: the
/// frame at 0.1 s with a play badge on top. Lets `![](.attachments/x.mp4)`
/// — how share-sheet media captures reference videos — render like an image.
/// Playback on tap is a separate follow-up.
enum VideoPosterRenderer {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static func isVideo(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    /// The URL to hand the player when a media line is tapped: only local
    /// video files (the poster renderer only draws those, too). Images and
    /// remote URLs are not playable targets.
    static func playableVideoURL(for url: URL?) -> URL? {
        guard let url, url.isFileURL, isVideo(url) else { return nil }
        return url
    }

    /// Calls back on an arbitrary queue with the poster, or nil when the file
    /// cannot be decoded.
    static func poster(for url: URL, completion: @escaping @Sendable (CGImage?) -> Void) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        generator.generateCGImageAsynchronously(for: CMTime(seconds: 0.1, preferredTimescale: 600)) { frame, _, _ in
            completion(frame.flatMap(withPlayBadge))
        }
    }

    /// Draws a translucent circle with a white triangle at the frame's centre.
    static func withPlayBadge(_ frame: CGImage) -> CGImage? {
        let width = frame.width, height = frame.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(frame, in: bounds)

        let diameter = min(max(CGFloat(min(width, height)) * 0.18, 44), 160)
        let circle = CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
        context.setFillColor(CGColor(gray: 0, alpha: 0.55))
        context.fillEllipse(in: circle)

        let side = diameter * 0.42
        let triangle = CGMutablePath()
        triangle.move(to: CGPoint(x: circle.midX - side * 0.35, y: circle.midY - side / 2))
        triangle.addLine(to: CGPoint(x: circle.midX - side * 0.35, y: circle.midY + side / 2))
        triangle.addLine(to: CGPoint(x: circle.midX + side * 0.55, y: circle.midY))
        triangle.closeSubpath()
        context.setFillColor(CGColor(gray: 1, alpha: 0.95))
        context.addPath(triangle)
        context.fillPath()
        return context.makeImage()
    }
}
