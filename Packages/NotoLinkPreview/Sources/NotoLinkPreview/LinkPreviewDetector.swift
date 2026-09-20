import Foundation

/// Decides whether a markdown paragraph is a *bare* web link — and therefore a
/// candidate for a preview card — as opposed to prose that happens to contain a URL.
///
/// The rule is deliberately narrow: the whole line, after trimming whitespace and an
/// optional `<...>` autolink wrapper, must be one `http(s)://` URL with a dotted host.
/// Inline links, `[text](url)` hyperlinks, and `![](url)` images are the editor's own
/// business and never reach this detector as bare lines.
public enum LinkPreviewDetector {
    /// Returns the URL when `line` is nothing but a web link, else `nil`.
    public static func url(inLine line: String) -> URL? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 2, text.hasPrefix("<"), text.hasSuffix(">") {
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
