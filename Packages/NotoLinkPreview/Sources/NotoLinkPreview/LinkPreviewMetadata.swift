import Foundation

/// What a preview card knows about a page: the Open Graph / Twitter-card style
/// metadata that `LinkPresentation` resolves, flattened into plain `Codable` data so
/// it can live on disk and travel between the fetcher, the cache, and the editor.
public struct LinkPreviewMetadata: Codable, Equatable, Sendable {
    /// The URL the note contains (not the canonical URL the page may redirect to).
    public var url: URL
    public var title: String?
    public var summary: String?
    /// Host of the page as it should be shown to the user (`www.` stripped).
    public var host: String
    /// Downsampled preview image (JPEG/PNG bytes), if the page provided one.
    public var imageData: Data?
    /// Site icon bytes, if the page provided one.
    public var iconData: Data?
    public var fetchedAt: Date

    public init(
        url: URL,
        title: String? = nil,
        summary: String? = nil,
        host: String,
        imageData: Data? = nil,
        iconData: Data? = nil,
        fetchedAt: Date = Date()
    ) {
        self.url = url
        self.title = title
        self.summary = summary
        self.host = host
        self.imageData = imageData
        self.iconData = iconData
        self.fetchedAt = fetchedAt
    }

    /// `www.example.com` → `example.com`; keeps everything else as-is.
    public static func displayHost(for url: URL) -> String {
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return url.absoluteString
        }
        if host.hasPrefix("www."), host.count > 4 {
            return String(host.dropFirst(4))
        }
        return host
    }
}
