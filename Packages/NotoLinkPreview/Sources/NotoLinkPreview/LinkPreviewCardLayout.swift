import CoreGraphics
import Foundation

/// Geometry of a preview card: a text column on the leading side and, when the page
/// has an image, a square thumbnail flush with the trailing edge. Both platform card
/// views lay out from this so their proportions cannot drift apart.
public struct LinkPreviewCardLayout: Equatable, Sendable {
    public static let defaultHeight: CGFloat = 104
    public static let defaultPadding: CGFloat = 12
    public static let cornerRadius: CGFloat = 12
    public static let iconSize: CGFloat = 14
    public static let iconTextGap: CGFloat = 6

    public let bounds: CGRect
    public let textRect: CGRect
    public let imageRect: CGRect?

    public init(
        width: CGFloat,
        height: CGFloat = LinkPreviewCardLayout.defaultHeight,
        hasImage: Bool,
        padding: CGFloat = LinkPreviewCardLayout.defaultPadding
    ) {
        let safeWidth = max(0, width)
        let safeHeight = max(0, height)
        bounds = CGRect(x: 0, y: 0, width: safeWidth, height: safeHeight)

        // The thumbnail is a square as tall as the card, but never wider than 40% of
        // it so narrow columns keep room for the title.
        let imageWidth = hasImage ? min(safeHeight, safeWidth * 0.4) : 0
        imageRect = hasImage && imageWidth > 0
            ? CGRect(x: safeWidth - imageWidth, y: 0, width: imageWidth, height: safeHeight)
            : nil

        let textTrailing = safeWidth - imageWidth - padding
        textRect = CGRect(
            x: padding,
            y: padding,
            width: max(0, textTrailing - padding),
            height: max(0, safeHeight - padding * 2)
        )
    }
}
