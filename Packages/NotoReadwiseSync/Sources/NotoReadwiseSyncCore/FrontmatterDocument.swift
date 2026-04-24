import Foundation

struct FrontmatterEntry {
    let key: String
    let lines: [String]

    static func scalar(_ key: String, _ value: String) -> FrontmatterEntry {
        FrontmatterEntry(key: key, lines: ["\(key): \(value)"])
    }

    static func literal(_ key: String, _ value: String) -> FrontmatterEntry {
        FrontmatterEntry(key: key, lines: ["\(key): \(value)"])
    }

    static func list(_ key: String, values: [String]) -> FrontmatterEntry {
        FrontmatterEntry(
            key: key,
            lines: [key + ":"] + values.map { "  - \($0)" }
        )
    }
}

struct FrontmatterDocument {
    let entries: [FrontmatterEntry]
    let body: String

    init(markdown: String) {
        guard markdown.hasPrefix("---"),
              let closeRange = markdown.range(
                of: "\n---",
                range: markdown.index(markdown.startIndex, offsetBy: 3)..<markdown.endIndex
              ) else {
            self.entries = []
            self.body = markdown
            return
        }

        let frontmatterBody = markdown[
            markdown.index(markdown.startIndex, offsetBy: 4)..<closeRange.lowerBound
        ]
        self.entries = Self.parseEntries(String(frontmatterBody))

        let afterClose = closeRange.upperBound
        if markdown[afterClose...].hasPrefix("\n") {
            self.body = String(markdown[markdown.index(after: afterClose)...])
        } else {
            self.body = String(markdown[afterClose...])
        }
    }

    func scalarValue(for key: String) -> String? {
        guard let line = entries.first(where: { $0.key == key })?.lines.first,
              let value = line.split(separator: ":", maxSplits: 1).last else {
            return nil
        }
        return Self.unquote(String(value).trimmingCharacters(in: .whitespaces))
    }

    func stringList(for key: String) -> [String] {
        guard let entry = entries.first(where: { $0.key == key }) else {
            return []
        }
        return entry.lines.dropFirst().compactMap(Self.parseListValue)
    }

    func merging(importerEntries: [FrontmatterEntry], importerOwnedKeys: Set<String>) -> [FrontmatterEntry] {
        let importerByKey = Dictionary(uniqueKeysWithValues: importerEntries.map { ($0.key, $0) })
        let existingByKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })

        var orderedKeys = entries.map(\.key)
        for entry in importerEntries where !orderedKeys.contains(entry.key) {
            orderedKeys.append(entry.key)
        }

        return orderedKeys.compactMap { key in
            if let importerEntry = importerByKey[key] {
                return importerEntry
            }
            guard !importerOwnedKeys.contains(key) else {
                return nil
            }
            return existingByKey[key]
        }
    }

    static func render(_ entries: [FrontmatterEntry]) -> String {
        (["---"] + entries.flatMap(\.lines) + ["---"])
            .joined(separator: "\n")
    }

    private static func parseEntries(_ frontmatter: String) -> [FrontmatterEntry] {
        var parsedEntries: [FrontmatterEntry] = []
        var currentKey: String?
        var currentLines: [String] = []

        for line in frontmatter.components(separatedBy: "\n") {
            if let key = parseEntryKey(from: line) {
                if let currentKey {
                    parsedEntries.append(FrontmatterEntry(key: currentKey, lines: currentLines))
                }
                currentKey = key
                currentLines = [line]
            } else if currentKey != nil {
                currentLines.append(line)
            }
        }

        if let currentKey {
            parsedEntries.append(FrontmatterEntry(key: currentKey, lines: currentLines))
        }

        return parsedEntries
    }

    private static func parseEntryKey(from line: String) -> String? {
        guard !line.isEmpty,
              let first = line.first,
              first != " ",
              first != "\t",
              let colonIndex = line.firstIndex(of: ":") else {
            return nil
        }
        return String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    private static func parseListValue(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") else { return nil }
        return unquote(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }

    private static func unquote(_ value: String) -> String {
        guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else {
            return value
        }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
