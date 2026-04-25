import Foundation

public struct MarkdownSearchDocumentExtractor: Sendable {
    private let vaultURL: URL

    public init(vaultURL: URL) {
        self.vaultURL = vaultURL.standardizedFileURL
    }

    public func extract(fileURL: URL) throws -> SearchDocument {
        let normalizedFileURL = fileURL.standardizedFileURL
        let markdown = try String(contentsOf: normalizedFileURL, encoding: .utf8)
        let relativePath = SearchUtilities.relativePath(for: normalizedFileURL, in: vaultURL)
        let parsed = parseFrontmatter(markdown)
        let body = parsed.body
        let fallbackTitle = normalizedFileURL.deletingPathExtension().lastPathComponent
        let title = title(in: body) ?? fallbackTitle
        let noteID = parsed.id ?? SearchUtilities.stableID(for: relativePath)
        let folderPath = folderPath(for: relativePath)
        let sections = sections(in: body, noteID: noteID, noteTitle: title, bodyStartLine: parsed.bodyStartLine)
        let plainText = plainText(from: body)

        return SearchDocument(
            id: noteID,
            relativePath: relativePath,
            title: title,
            folderPath: folderPath,
            contentHash: SearchUtilities.contentHash(markdown),
            plainText: plainText,
            sections: sections
        )
    }

    private func parseFrontmatter(_ markdown: String) -> (id: UUID?, body: String, bodyStartLine: Int) {
        guard markdown.hasPrefix("---\n") || markdown == "---" else {
            return (nil, markdown, 1)
        }

        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first == "---" else {
            return (nil, markdown, 1)
        }

        var closingIndex: Int?
        for index in lines.indices.dropFirst() where lines[index] == "---" {
            closingIndex = index
            break
        }
        guard let closingIndex else {
            return (nil, markdown, 1)
        }

        let frontmatterLines = lines[1..<closingIndex]
        let id = frontmatterLines
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("id:") }
            .flatMap { line -> UUID? in
                let raw = line
                    .split(separator: ":", maxSplits: 1)
                    .dropFirst()
                    .joined(separator: ":")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return UUID(uuidString: raw)
            }
        let bodyLines = lines.dropFirst(closingIndex + 1)
        return (id, bodyLines.joined(separator: "\n"), closingIndex + 2)
    }

    private func title(in body: String) -> String? {
        for line in body.components(separatedBy: .newlines) {
            guard let heading = heading(in: line), !heading.text.isEmpty else {
                continue
            }
            return heading.text
        }
        return nil
    }

    private func sections(in body: String, noteID: UUID, noteTitle: String, bodyStartLine: Int) -> [SearchSection] {
        let lines = body.components(separatedBy: .newlines)
        var starts: [(lineIndex: Int, heading: String, level: Int?)] = []

        for (index, line) in lines.enumerated() {
            if let heading = heading(in: line) {
                starts.append((index, heading.text, heading.level))
            }
        }

        if starts.isEmpty {
            let text = plainText(from: body)
            guard !text.isEmpty else { return [] }
            return [
                section(
                    noteID: noteID,
                    heading: noteTitle,
                    level: nil,
                    lineStart: bodyStartLine,
                    lineEnd: bodyStartLine + max(lines.count - 1, 0),
                    sectionIndex: 0,
                    rawText: body
                )
            ]
        }

        if starts.first?.lineIndex ?? 0 > 0 {
            starts.insert((0, noteTitle, nil), at: 0)
        }

        return starts.enumerated().compactMap { offset, start in
            let nextLineIndex = offset + 1 < starts.count ? starts[offset + 1].lineIndex : lines.count
            let rawLines = lines[start.lineIndex..<nextLineIndex]
            let rawText = rawLines.joined(separator: "\n")
            let text = plainText(from: rawText)
            guard !text.isEmpty else { return nil }
            return section(
                noteID: noteID,
                heading: start.heading,
                level: start.level,
                lineStart: bodyStartLine + start.lineIndex,
                lineEnd: bodyStartLine + max(nextLineIndex - 1, start.lineIndex),
                sectionIndex: offset,
                rawText: rawText
            )
        }
    }

    private func section(
        noteID: UUID,
        heading: String,
        level: Int?,
        lineStart: Int,
        lineEnd: Int,
        sectionIndex: Int,
        rawText: String
    ) -> SearchSection {
        let plainText = plainText(from: rawText)
        let idSeed = "\(noteID.uuidString):\(sectionIndex):\(heading)"
        return SearchSection(
            id: SearchUtilities.stableID(for: idSeed),
            noteID: noteID,
            heading: heading,
            level: level,
            lineStart: lineStart,
            lineEnd: lineEnd,
            sectionIndex: sectionIndex,
            contentHash: SearchUtilities.contentHash(rawText),
            plainText: plainText
        )
    }

    private func heading(in line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefix = trimmed.prefix { $0 == "#" }
        guard !prefix.isEmpty, prefix.count <= 6 else { return nil }
        let afterHashes = trimmed.dropFirst(prefix.count)
        guard afterHashes.first == " " || afterHashes.first == "\t" else { return nil }
        let text = afterHashes.trimmingCharacters(in: .whitespacesAndNewlines)
        return (prefix.count, stripMarkdownInline(text))
    }

    private func folderPath(for relativePath: String) -> String {
        let url = URL(fileURLWithPath: relativePath)
        let parent = url.deletingLastPathComponent().relativePath
        return parent == "." ? "" : parent
    }

    private func plainText(from markdown: String) -> String {
        markdown
            .components(separatedBy: .newlines)
            .map(plainTextLine)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func plainTextLine(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        if let heading = heading(in: text) {
            return heading.text
        }
        if text.hasPrefix(">") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        text = text.replacingOccurrences(
            of: #"^[-*+]\s+\[[ xX]\]\s+"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"^([-*+]|\d+[.)])\s+"#,
            with: "",
            options: .regularExpression
        )
        return stripMarkdownInline(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripMarkdownInline(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        for marker in ["**", "__", "~~", "`", "*", "_"] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        return result
    }
}
