import Foundation

public struct WordCounter: Equatable, Sendable {
    public struct Count: Equatable, Sendable {
        public let words: Int
        public let characters: Int

        public init(words: Int, characters: Int) {
            self.words = words
            self.characters = characters
        }
    }

    public init() {}

    public func count(in markdown: String) -> Count {
        let body = Self.stripFrontmatter(from: markdown)
        return Count(
            words: Self.wordCount(in: body),
            characters: body.count
        )
    }

    public static func stripFrontmatter(from markdown: String) -> String {
        guard markdown.hasPrefix("---") else { return markdown }

        let lines = markdown.components(separatedBy: "\n")
        guard let firstDashIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return markdown
        }

        let remaining = lines.dropFirst(firstDashIndex + 1)
        guard let closingDashIndex = remaining.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return markdown
        }

        let bodyLines = lines[(closingDashIndex + 1)...]
        let body = bodyLines.joined(separator: "\n")
        if body.hasPrefix("\n") {
            return String(body.dropFirst())
        }
        return body
    }

    private static func wordCount(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}
