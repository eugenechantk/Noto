import Foundation

/// What the share sheet handed the extension, before any decision is made.
/// The extension collects these from its item providers; resolving them into
/// one link is pure so it can be tested without `NSItemProvider`.
public struct SharedLinkPayload: Equatable, Sendable {
    /// URL attachments (`public.url`) and any URL a preprocessing script returned.
    public var urls: [URL]
    /// Plain-text attachments and the item's `attributedContentText`.
    public var texts: [String]
    /// `document.title` from the Safari preprocessing script, when present.
    public var pageTitle: String?
    /// The item's own `attributedTitle`, a weaker title source.
    public var itemTitle: String?

    public init(urls: [URL] = [], texts: [String] = [], pageTitle: String? = nil, itemTitle: String? = nil) {
        self.urls = urls
        self.texts = texts
        self.pageTitle = pageTitle
        self.itemTitle = itemTitle
    }

    public struct Resolved: Equatable, Sendable {
        public let url: URL
        public let title: String?
        public let text: String?

        public var body: String {
            SharedLinkCapture.body(url: url, title: title, text: text)
        }
    }

    /// The link to capture, or nil when nothing shared was a web URL.
    /// An explicit URL attachment wins; otherwise the first http(s) URL found
    /// in the shared text is used and that text is kept as the note body.
    public func resolve() -> Resolved? {
        let title = firstNonBlank(pageTitle, itemTitle)
        let joinedText = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let text = joinedText.isEmpty ? nil : joinedText

        if let url = urls.first(where: Self.isWebURL) {
            return Resolved(url: url, title: title, text: text)
        }

        for candidate in texts {
            if let url = Self.firstWebURL(in: candidate) {
                return Resolved(url: url, title: title, text: text)
            }
        }
        return nil
    }

    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    static func firstWebURL(in text: String) -> URL? {
        for token in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            var candidate = String(token)
            // Prose punctuation around a URL: "see https://x.y/z." / "(https://…)"
            while let first = candidate.first, "([{<\"'".contains(first) {
                candidate.removeFirst()
            }
            while let last = candidate.last, ".,;:!?)]}>\"'".contains(last) {
                candidate.removeLast()
            }
            if let url = URL(string: candidate), isWebURL(url) {
                return url
            }
        }
        return nil
    }

    private func firstNonBlank(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }
}
