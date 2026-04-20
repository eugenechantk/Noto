import Foundation

public struct NoteTitleResolver: Sendable {
    public init() {}

    public func title(forFileAt url: URL) -> String {
        let fallbackTitle = fallbackTitle(for: url)
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return fallbackTitle
        }

        return title(from: markdown, fallbackTitle: fallbackTitle)
    }

    public func title(from markdown: String, fallbackTitle: String = "Untitled") -> String {
        let body = Frontmatter.parse(markdown).body
        let firstLine = body.prefix { $0 != "\n" }
        var title = String(firstLine).trimmingCharacters(in: .whitespaces)
        if let headingRange = title.range(of: #"^#{1,3}\s*"#, options: .regularExpression) {
            title = String(title[headingRange.upperBound...])
        }
        title = title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? fallbackTitle : title
    }

    public func fallbackTitle(for url: URL) -> String {
        let fallback = url.deletingPathExtension().lastPathComponent
        return fallback.isEmpty || UUID(uuidString: fallback) != nil ? "Untitled" : fallback
    }
}
