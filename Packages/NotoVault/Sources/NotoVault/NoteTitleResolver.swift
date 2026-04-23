import Foundation

public struct NoteTitleResolver: Sendable {
    private static let maxTitleBytes = 64 * 1024

    public init() {}

    public func title(forFileAt url: URL) -> String {
        let fallbackTitle = fallbackTitle(for: url)
        guard let markdown = MarkdownPrefixReader.readPrefix(from: url, maxBytes: Self.maxTitleBytes) else {
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

enum MarkdownPrefixReader {
    static func readPrefix(from url: URL, maxBytes: Int) -> String? {
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }

            let data = try handle.read(upToCount: maxBytes) ?? Data()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }
}
