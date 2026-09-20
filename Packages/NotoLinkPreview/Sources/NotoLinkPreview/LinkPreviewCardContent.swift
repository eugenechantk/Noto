import Foundation

/// The strings a card shows for a URL in a given state. Pure mapping so both the
/// UIKit and AppKit card views render identical text without duplicating the rules.
public struct LinkPreviewCardContent: Equatable, Sendable {
    public static let loadingSubtitle = "Loading preview…"
    public static let unavailableSubtitle = "Preview unavailable"

    public let title: String
    public let subtitle: String?
    public let host: String
    public let imageData: Data?
    public let iconData: Data?

    public var hasImage: Bool { imageData != nil }
    public var hasIcon: Bool { iconData != nil }

    public init(title: String, subtitle: String?, host: String, imageData: Data? = nil, iconData: Data? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.host = host
        self.imageData = imageData
        self.iconData = iconData
    }

    public static func make(url: URL, state: LinkPreviewService.State) -> LinkPreviewCardContent {
        let host = LinkPreviewMetadata.displayHost(for: url)

        switch state {
        case .loading:
            return LinkPreviewCardContent(title: host, subtitle: loadingSubtitle, host: host)

        case .failed:
            return LinkPreviewCardContent(
                title: displayURL(url),
                subtitle: unavailableSubtitle,
                host: host
            )

        case .loaded(let metadata):
            let title = metadata.title.flatMap(nonEmpty) ?? displayURL(url)
            return LinkPreviewCardContent(
                title: title,
                subtitle: metadata.summary.flatMap(nonEmpty),
                host: metadata.host.isEmpty ? host : metadata.host,
                imageData: metadata.imageData,
                iconData: metadata.iconData
            )
        }
    }

    /// `https://www.example.com/path?x=1` → `example.com/path?x=1`
    static func displayURL(_ url: URL) -> String {
        var text = url.absoluteString
        for prefix in ["https://www.", "http://www.", "https://", "http://"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        if text.hasSuffix("/") {
            text = String(text.dropLast())
        }
        return text
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
