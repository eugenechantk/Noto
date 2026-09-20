import Foundation

/// Decides whether a markdown paragraph is *only* a web link — and therefore a
/// candidate for a preview card — as opposed to prose that happens to contain a URL.
///
/// Two shapes qualify, after trimming whitespace:
/// - a bare `http(s)://` URL with a dotted host, optionally wrapped in `<...>`;
/// - a single `[title](url)` markdown link (the shape share-sheet captures are filed
///   as), where `url` is such a web URL. The card replaces the link; the markdown —
///   title included — stays on disk and is revealed when the caret is on the line.
/// Inline links mid-sentence and `![](url)` images are the editor's own business and
/// never reach this detector as bare lines.
public enum LinkPreviewDetector {
    /// Returns the URL when `line` is nothing but a web link, else `nil`.
    public static func url(inLine line: String) -> URL? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let destination = markdownLinkDestination(in: text) {
            text = destination
        } else if text.count > 2, text.hasPrefix("<"), text.hasSuffix(">") {
            text = String(text.dropFirst().dropLast())
        }

        guard !text.isEmpty,
              !text.contains(where: { $0.isWhitespace }) else {
            return nil
        }

        let lowercased = text.lowercased()
        guard lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") else {
            return nil
        }

        guard let components = URLComponents(string: text) ?? percentEncodedComponents(from: text),
              let host = components.host,
              isPreviewableHost(host),
              let url = components.url else {
            return nil
        }

        return url
    }

    /// `[title](destination)` spanning the whole trimmed line → `destination`.
    /// `![alt](image)` is not a link. The title may not contain `]` and the
    /// destination may not contain `)` or whitespace — the same shape the editor's
    /// hyperlink renderer accepts.
    static func markdownLinkDestination(in text: String) -> String? {
        guard text.hasPrefix("["), text.hasSuffix(")"),
              let titleEnd = text.firstIndex(of: "]") else {
            return nil
        }
        let afterTitle = text.index(after: titleEnd)
        guard afterTitle < text.endIndex, text[afterTitle] == "(" else { return nil }
        let destination = String(text[text.index(after: afterTitle)..<text.index(before: text.endIndex)])
        guard !destination.isEmpty,
              !destination.contains(")"),
              !destination.contains(where: { $0.isWhitespace }) else {
            return nil
        }
        return destination
    }

    private static func percentEncodedComponents(from text: String) -> URLComponents? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "#[]%")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URLComponents(string: encoded)
    }

    /// A host must look finished (`example.com`) so a half-typed `https://exa` never
    /// flips into a card mid-keystroke. `localhost` is allowed for local dev servers.
    private static func isPreviewableHost(_ host: String) -> Bool {
        if host == "localhost" { return true }
        guard host.contains(".") else { return false }
        guard !host.hasPrefix("."), !host.hasSuffix(".") else { return false }
        return true
    }
}
