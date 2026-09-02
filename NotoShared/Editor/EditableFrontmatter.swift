import Foundation

struct EditableFrontmatterField: Equatable, Identifiable {
    let key: String
    let lines: [String]

    var id: String { key }

    var value: String {
        guard let firstLine = lines.first else { return "" }
        let scalarPrefix = "\(key):"
        let firstValue: String
        if firstLine.hasPrefix(scalarPrefix) {
            firstValue = String(firstLine.dropFirst(scalarPrefix.count))
                .trimmingCharacters(in: .whitespaces)
        } else {
            firstValue = firstLine.trimmingCharacters(in: .whitespaces)
        }

        guard lines.count > 1 else { return firstValue }
        let continuation = lines.dropFirst().joined(separator: "\n")
        return ([firstValue, continuation].filter { !$0.isEmpty }).joined(separator: "\n")
    }

    var isScalar: Bool {
        lines.count == 1 && !value.hasPrefix("|") && !value.hasPrefix(">")
    }

    var displayValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Empty" : trimmed
    }

    var url: URL? {
        Self.url(from: value)
    }

    static func url(from value: String) -> URL? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }
}

struct EditableFrontmatterDocument: Equatable {
    let fields: [EditableFrontmatterField]

    init?(markdown: String) {
        guard let range = MarkdownFrontmatter.range(in: markdown) else { return nil }
        let nsMarkdown = markdown as NSString
        let rawFrontmatter = nsMarkdown.substring(with: range)
        self.fields = Self.parseFields(from: rawFrontmatter)
    }

    static func parseFields(from rawFrontmatter: String) -> [EditableFrontmatterField] {
        let lines = rawFrontmatter.components(separatedBy: .newlines)
        guard lines.first == "---" else { return [] }

        var fields: [EditableFrontmatterField] = []
        var currentKey: String?
        var currentLines: [String] = []

        func flush() {
            guard let currentKey else { return }
            fields.append(EditableFrontmatterField(key: currentKey, lines: currentLines))
            currentLines = []
        }

        for line in lines.dropFirst() {
            if line == "---" {
                break
            }

            if let key = frontmatterKey(in: line) {
                flush()
                currentKey = key
                currentLines = [line]
            } else if currentKey != nil {
                currentLines.append(line)
            }
        }

        flush()
        return fields
    }

    static func updatingField(key: String, value: String, in markdown: String) -> String {
        replaceOrAddField(key: key, value: value, in: markdown, shouldReplaceExisting: true)
    }

    static func addingField(key: String, value: String, in markdown: String) -> String {
        replaceOrAddField(key: key, value: value, in: markdown, shouldReplaceExisting: false)
    }

    static func parsedFieldInput(_ input: String) -> (key: String, value: String)? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return nil }

        let key: String
        let value: String
        if let colonIndex = trimmedInput.firstIndex(of: ":") {
            key = String(trimmedInput[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            value = String(trimmedInput[trimmedInput.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            key = trimmedInput
            value = ""
        }

        guard isValidKey(key) else { return nil }
        return (key, value)
    }

    static func parsedFieldInput(key rawKey: String, value rawValue: String) -> (key: String, value: String)? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidKey(key) else { return nil }
        return (key, rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func deletingField(key: String, in markdown: String) -> String {
        guard let range = MarkdownFrontmatter.range(in: markdown) else { return markdown }
        let nsMarkdown = markdown as NSString
        let rawFrontmatter = nsMarkdown.substring(with: range)
        let lines = rawFrontmatter.components(separatedBy: .newlines)
        guard lines.first == "---" else { return markdown }

        var output: [String] = ["---"]
        var index = 1
        while index < lines.count {
            let line = lines[index]
            if line == "---" { break }

            if frontmatterKey(in: line) == key {
                index += 1
                while index < lines.count,
                      lines[index] != "---",
                      frontmatterKey(in: lines[index]) == nil {
                    index += 1
                }
                continue
            }

            output.append(line)
            index += 1
        }
        output.append("---")

        return replaceFrontmatter(range: range, with: output.joined(separator: "\n"), in: markdown)
    }

    private static func replaceOrAddField(
        key: String,
        value: String,
        in markdown: String,
        shouldReplaceExisting: Bool
    ) -> String {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { return markdown }
        let renderedLine = "\(normalizedKey): \(value.trimmingCharacters(in: .whitespacesAndNewlines))"

        guard let range = MarkdownFrontmatter.range(in: markdown) else {
            let separator = markdown.hasPrefix("\n") || markdown.isEmpty ? "" : "\n"
            return "---\n\(renderedLine)\n---\n\(separator)\(markdown)"
        }

        let nsMarkdown = markdown as NSString
        let rawFrontmatter = nsMarkdown.substring(with: range)
        let lines = rawFrontmatter.components(separatedBy: .newlines)
        guard lines.first == "---" else { return markdown }

        var output: [String] = ["---"]
        var didWrite = false
        var index = 1

        while index < lines.count {
            let line = lines[index]
            if line == "---" { break }

            if frontmatterKey(in: line) == normalizedKey {
                if shouldReplaceExisting {
                    output.append(renderedLine)
                    didWrite = true
                } else {
                    output.append(line)
                }
                index += 1
                while index < lines.count,
                      lines[index] != "---",
                      frontmatterKey(in: lines[index]) == nil {
                    if !shouldReplaceExisting {
                        output.append(lines[index])
                    }
                    index += 1
                }
                continue
            }

            output.append(line)
            index += 1
        }

        if !didWrite {
            output.append(renderedLine)
        }
        output.append("---")

        return replaceFrontmatter(range: range, with: output.joined(separator: "\n"), in: markdown)
    }

    private static func replaceFrontmatter(range: NSRange, with replacement: String, in markdown: String) -> String {
        let nsMarkdown = markdown as NSString
        return nsMarkdown.replacingCharacters(in: range, with: replacement)
    }

    private static func frontmatterKey(in line: String) -> String? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        return isValidKey(key) ? key : nil
    }

    private static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }
}
