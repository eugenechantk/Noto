import Foundation

public enum HTMLToMarkdown {
    public static func convert(_ html: String) -> String {
        guard !html.isEmpty else { return "" }
        var text = html
        text = replaceLinkedImages(text)
        text = replaceImages(text)
        text = replaceBlockTags(text)
        text = replaceLinks(text)
        text = replaceInlineTags(text)
        text = stripTags(text)
        text = decodeEntities(text)
        text = normalizeWhitespace(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceBlockTags(_ html: String) -> String {
        var text = html
        let replacements: [(String, String)] = [
            (#"(?i)<\s*h1[^>]*>"#, "# "),
            (#"(?i)</\s*h1\s*>"#, "\n\n"),
            (#"(?i)<\s*h2[^>]*>"#, "## "),
            (#"(?i)</\s*h2\s*>"#, "\n\n"),
            (#"(?i)<\s*h3[^>]*>"#, "### "),
            (#"(?i)</\s*h3\s*>"#, "\n\n"),
            (#"(?i)<\s*p[^>]*>"#, ""),
            (#"(?i)</\s*p\s*>"#, "\n\n"),
            (#"(?i)<\s*br\s*/?\s*>"#, "\n"),
            (#"(?i)<\s*li[^>]*>"#, "- "),
            (#"(?i)</\s*li\s*>"#, "\n"),
            (#"(?i)</\s*(ul|ol|div|article|section|blockquote)\s*>"#, "\n\n"),
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return text
    }

    private static func replaceLinkedImages(_ html: String) -> String {
        let pattern = #"(?is)<a\s+[^>]*href\s*=\s*["']([^"']+)["'][^>]*>\s*(<img\b[^>]*>)\s*</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed()
        var text = html
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let imageRange = Range(match.range(at: 2), in: html),
                  let fullRange = Range(match.range(at: 0), in: text) else {
                continue
            }

            let href = String(html[hrefRange])
            let imageTag = String(html[imageRange])
            let src = attribute("src", in: imageTag).nonEmpty ?? href
            let alt = attribute("alt", in: imageTag) ?? ""
            text.replaceSubrange(fullRange, with: "![\(alt)](\(src))")
        }
        return text
    }

    private static func replaceImages(_ html: String) -> String {
        let pattern = #"(?is)<img\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed()
        var text = html
        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: text) else { continue }
            let imageTag = String(text[fullRange])
            guard let src = attribute("src", in: imageTag).nonEmpty else { continue }
            let alt = attribute("alt", in: imageTag) ?? ""
            text.replaceSubrange(fullRange, with: "![\(alt)](\(src))")
        }
        return text
    }

    private static func replaceLinks(_ html: String) -> String {
        let pattern = #"(?is)<a\s+[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed()
        var text = html
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let labelRange = Range(match.range(at: 2), in: html),
                  let fullRange = Range(match.range(at: 0), in: text) else {
                continue
            }
            let href = String(html[hrefRange])
            let label = stripTags(String(html[labelRange]))
            text.replaceSubrange(fullRange, with: "[\(label)](\(href))")
        }
        return text
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"(?is)\b\#(name)\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }

    private static func replaceInlineTags(_ html: String) -> String {
        var text = html
        let replacements: [(String, String)] = [
            (#"(?is)<\s*(strong|b)[^>]*>(.*?)</\s*\1\s*>"#, "**$2**"),
            (#"(?is)<\s*(em|i)[^>]*>(.*?)</\s*\1\s*>"#, "*$2*"),
            (#"(?is)<\s*code[^>]*>(.*?)</\s*code\s*>"#, "`$1`"),
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return text
    }

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return normalized
    }
}
