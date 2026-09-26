import CoreGraphics
import Foundation

/// Geometry of a preview card: a full-width banner on top (the page's image, or a
/// placeholder with the site icon) and the text block below it — title, description,
/// site. The height is fixed whether or not an image arrives, so a note never
/// reflows while a preview loads; it matches an image line's reserved height.
public struct LinkPreviewCardLayout: Equatable, Sendable {
    public static let defaultHeight: CGFloat = 300
    public static let bannerHeight: CGFloat = 168
    public static let defaultPadding: CGFloat = 12
    public static let cornerRadius: CGFloat = 12
    public static let iconSize: CGFloat = 14
    public static let iconTextGap: CGFloat = 6
    public static let titleLineLimit = 2
    public static let summaryLineLimit = 3

    public let bounds: CGRect
    public let bannerRect: CGRect
    public let textRect: CGRect

    public init(
        width: CGFloat,
        height: CGFloat = LinkPreviewCardLayout.defaultHeight,
        padding: CGFloat = LinkPreviewCardLayout.defaultPadding
    ) {
        let safeWidth = max(0, width)
        let safeHeight = max(0, height)
        bounds = CGRect(x: 0, y: 0, width: safeWidth, height: safeHeight)
        bannerRect = CGRect(x: 0, y: 0, width: safeWidth, height: min(Self.bannerHeight, safeHeight))
        textRect = CGRect(
            x: padding,
            y: bannerRect.maxY + padding,
            width: max(0, safeWidth - padding * 2),
            height: max(0, safeHeight - bannerRect.maxY - padding * 2)
        )
    }
}
