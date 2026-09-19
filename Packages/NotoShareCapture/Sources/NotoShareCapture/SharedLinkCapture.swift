import Foundation

/// Formats a shared link as the vault's markdown link — `[title](url)` — the
/// same shape the editor's link toggle writes and `HyperlinkMarkdown` parses:
/// the title may not contain `]` or a newline, the URL may not contain `)` or
/// a newline. Anything shared alongside the link (selected text) follows as a
/// second paragraph.
public enum SharedLinkCapture {
    /// The capture body for a link. `title` nil/blank → the URL is the link text
    /// (matches the editor's own bare-URL toggle). `text` is dropped when it is
    /// empty or merely repeats the URL or the title.
    public static func body(url: URL, title: String?, text: String? = nil) -> String {
        let urlText = linkDestination(for: url)
        let cleanTitle = sanitizedTitle(title) ?? urlText
        var body = "[\(cleanTitle)](\(urlText))"

        if let extra = sanitizedText(text),
           extra != url.absoluteString,
           extra != urlText,
           extra != cleanTitle {
            body += "\n\n" + extra
        }
        return body
    }

    /// Collapses whitespace runs (including newlines) to single spaces and
    /// replaces square brackets so the title can never close the link early.
    static func sanitizedTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    static func sanitizedText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Percent-encodes the characters that would end the markdown link early.
    /// Everything else stays as the URL was shared.
    static func linkDestination(for url: URL) -> String {
        url.absoluteString
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
            .replacingOccurrences(of: " ", with: "%20")
    }
}
