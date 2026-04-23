import Foundation

public enum SourceNoteRenderer {
    public static let startMarker = "<!-- readwise:source:start -->"
    public static let endMarker = "<!-- readwise:source:end -->"
    public static let metadataStartMarker = "<!-- readwise:metadata:start -->"
    public static let metadataEndMarker = "<!-- readwise:metadata:end -->"
    public static let highlightsStartMarker = "<!-- readwise:highlights:start -->"
    public static let highlightsEndMarker = "<!-- readwise:highlights:end -->"
    public static let contentStartMarker = "<!-- readwise:content:start -->"
    public static let contentEndMarker = "<!-- readwise:content:end -->"

    public static func renderNewNote(
        for book: ReadwiseBook,
        id: UUID,
        createdAt: Date,
        capturedAt: Date
    ) -> String {
        frontmatter(for: book, id: id, createdAt: createdAt, updatedAt: capturedAt)
            + "\n# \(book.displayTitle)\n\n"
            + generatedBlock(for: book, capturedAt: capturedAt)
            + "\n"
    }

    public static func renderUpdatedNote(
        existingMarkdown: String,
        book: ReadwiseBook,
        capturedAt: Date
    ) -> String {
        let metadata = parseFrontmatter(existingMarkdown)
        let id = metadata.id ?? UUID()
        let createdAt = metadata.createdAt ?? capturedAt
        let markdownWithUpdatedFrontmatter = replaceFrontmatter(
            in: existingMarkdown,
            with: frontmatter(for: book, id: id, createdAt: createdAt, updatedAt: capturedAt, preservingTags: metadata.tags)
        )
        return replaceGeneratedSection(
            in: markdownWithUpdatedFrontmatter,
            highlightsBlock: highlightsBlock(for: book),
            contentBlock: normalizedExistingBlock(
                in: markdownWithUpdatedFrontmatter,
                start: contentStartMarker,
                end: contentEndMarker,
                emptyBlock: emptyContentBlock(),
                legacyPlaceholders: ["_No full content imported._", "_No Reader content available._"]
            )
        )
    }

    public static func renderNewNote(
        for document: ReaderDocument,
        id: UUID,
        createdAt: Date,
        capturedAt: Date
    ) -> String {
        frontmatter(for: document, id: id, createdAt: createdAt, updatedAt: capturedAt)
            + "\n# \(document.displayTitle)\n\n"
            + generatedBlock(for: document, capturedAt: capturedAt)
            + "\n"
    }

    public static func renderNewNote(
        for document: ReaderDocument,
        matchedBook: ReadwiseBook,
        id: UUID,
        createdAt: Date,
        capturedAt: Date
    ) -> String {
        frontmatter(for: document, matchedBook: matchedBook, id: id, createdAt: createdAt, updatedAt: capturedAt)
            + "\n# \(document.displayTitle)\n\n"
            + generatedBlock(for: document, matchedBook: matchedBook, capturedAt: capturedAt)
            + "\n"
    }

    public static func renderUpdatedNote(
        existingMarkdown: String,
        document: ReaderDocument,
        capturedAt: Date
    ) -> String {
        let metadata = parseFrontmatter(existingMarkdown)
        let id = metadata.id ?? UUID()
        let createdAt = metadata.createdAt ?? capturedAt
        let markdownWithUpdatedFrontmatter = replaceFrontmatter(
            in: existingMarkdown,
            with: frontmatter(for: document, id: id, createdAt: createdAt, updatedAt: capturedAt, preservingTags: metadata.tags)
        )
        return replaceGeneratedSection(
            in: markdownWithUpdatedFrontmatter,
            highlightsBlock: normalizedExistingBlock(
                in: markdownWithUpdatedFrontmatter,
                start: highlightsStartMarker,
                end: highlightsEndMarker,
                emptyBlock: emptyHighlightsBlock(),
                legacyPlaceholders: ["_No highlights imported._", "_No active highlights._"]
            ),
            contentBlock: contentBlock(for: document)
        )
    }

    public static func renderUpdatedNote(
        existingMarkdown: String,
        document: ReaderDocument,
        matchedBook: ReadwiseBook,
        capturedAt: Date
    ) -> String {
        let metadata = parseFrontmatter(existingMarkdown)
        let id = metadata.id ?? UUID()
        let createdAt = metadata.createdAt ?? capturedAt
        let markdownWithUpdatedFrontmatter = replaceFrontmatter(
            in: existingMarkdown,
            with: frontmatter(for: document, matchedBook: matchedBook, id: id, createdAt: createdAt, updatedAt: capturedAt, preservingTags: metadata.tags)
        )
        return replaceGeneratedSection(
            in: markdownWithUpdatedFrontmatter,
            highlightsBlock: highlightsBlock(for: matchedBook),
            contentBlock: contentBlock(for: document)
        )
    }

    public static func generatedBlock(for book: ReadwiseBook, capturedAt: Date) -> String {
        generatedSection(
            highlightsBlock: highlightsBlock(for: book),
            contentBlock: emptyContentBlock()
        )
    }

    public static func generatedBlock(for document: ReaderDocument, capturedAt: Date) -> String {
        generatedSection(
            highlightsBlock: emptyHighlightsBlock(),
            contentBlock: contentBlock(for: document)
        )
    }

    public static func generatedBlock(for document: ReaderDocument, matchedBook: ReadwiseBook, capturedAt: Date) -> String {
        generatedSection(
            highlightsBlock: highlightsBlock(for: matchedBook),
            contentBlock: contentBlock(for: document)
        )
    }

    public static func highlightsBlock(for book: ReadwiseBook) -> String {
        var lines: [String] = [highlightsStartMarker]
        let highlights = book.activeHighlights
        if !highlights.isEmpty {
            for (index, highlight) in highlights.enumerated() {
                if index > 0 {
                    lines.append("")
                }
                lines.append(contentsOf: blockquote(highlight.text))
                if let note = highlight.note.nonEmpty {
                    lines.append(">")
                    lines.append(contentsOf: blockquote("Note: \(note)"))
                }
            }
        }
        lines.append(highlightsEndMarker)
        return lines.joined(separator: "\n")
    }

    public static func contentBlock(for document: ReaderDocument) -> String {
        var lines: [String] = [contentStartMarker]
        let content = document.contentMarkdown
        if !content.isEmpty {
            lines.append(content)
        }
        lines.append(contentEndMarker)
        return lines.joined(separator: "\n")
    }

    public static func replaceGeneratedBlock(in markdown: String, with generatedBlock: String) -> String {
        guard let startRange = markdown.range(of: startMarker),
              let endRange = markdown.range(
                of: endMarker,
                range: startRange.upperBound..<markdown.endIndex
              ) else {
            return insertGeneratedBlock(markdown, generatedBlock: generatedBlock)
        }

        var updated = markdown
        updated.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: generatedBlock)
        return updated
    }

    public static func generatedBlockHash(for block: String) -> String {
        FNV1a64.hash(block)
    }

    private static func emptyHighlightsBlock() -> String {
        [highlightsStartMarker, highlightsEndMarker]
            .joined(separator: "\n")
    }

    private static func emptyContentBlock() -> String {
        [contentStartMarker, contentEndMarker]
            .joined(separator: "\n")
    }

    private static func generatedSection(highlightsBlock: String, contentBlock: String) -> String {
        [highlightsBlock, contentBlock].joined(separator: "\n\n")
    }

    private static func replaceGeneratedSection(
        in markdown: String,
        highlightsBlock: String,
        contentBlock: String
    ) -> String {
        if containsSplitBlocks(markdown) {
            var updated = replaceBlock(
                in: markdown,
                start: highlightsStartMarker,
                end: highlightsEndMarker,
                with: highlightsBlock
            )
            updated = replaceBlock(
                in: updated,
                start: contentStartMarker,
                end: contentEndMarker,
                with: contentBlock
            )
            return removeMetadataBeforeFirstGeneratedBlock(in: updated)
        }

        return replaceGeneratedBlock(
            in: markdown,
            with: generatedSection(
                highlightsBlock: highlightsBlock,
                contentBlock: contentBlock
            )
        )
    }

    private static func containsSplitBlocks(_ markdown: String) -> Bool {
        markdown.contains(highlightsStartMarker) || markdown.contains(contentStartMarker)
    }

    private static func existingBlock(in markdown: String, start: String, end: String) -> String? {
        guard let startRange = markdown.range(of: start),
              let endRange = markdown.range(of: end, range: startRange.upperBound..<markdown.endIndex) else {
            return nil
        }
        return String(markdown[startRange.lowerBound..<endRange.upperBound])
    }

    private static func normalizedExistingBlock(
        in markdown: String,
        start: String,
        end: String,
        emptyBlock: String,
        legacyPlaceholders: [String]
    ) -> String {
        guard let block = existingBlock(in: markdown, start: start, end: end) else {
            return emptyBlock
        }

        var body = block
        body = body.replacingOccurrences(of: start, with: "")
        body = body.replacingOccurrences(of: end, with: "")
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty || legacyPlaceholders.contains(body) {
            return emptyBlock
        }
        return block
    }

    private static func replaceBlock(in markdown: String, start: String, end: String, with block: String) -> String {
        guard let startRange = markdown.range(of: start),
              let endRange = markdown.range(of: end, range: startRange.upperBound..<markdown.endIndex) else {
            return insertGeneratedBlock(markdown, generatedBlock: block)
        }

        var updated = markdown
        updated.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: block)
        return updated
    }

    private static func removeMetadataBeforeFirstGeneratedBlock(in markdown: String) -> String {
        var updated = markdown

        if let metadataRange = blockRange(in: updated, start: metadataStartMarker, end: metadataEndMarker) {
            let rangeWithTrailingSpacing = extendedRangeRemovingTrailingBlankLines(in: updated, range: metadataRange)
            updated.removeSubrange(rangeWithTrailingSpacing)
        }

        guard let firstMarkerRange = firstGeneratedMarkerRange(in: updated) else {
            return updated
        }

        let prefix = String(updated[..<firstMarkerRange.lowerBound])
        guard let metadataRange = generatedMetadataRange(in: prefix) else {
            return updated
        }

        let lowerOffset = prefix.distance(from: prefix.startIndex, to: metadataRange.lowerBound)
        let upperOffset = prefix.distance(from: prefix.startIndex, to: metadataRange.upperBound)
        let metadataStart = updated.index(updated.startIndex, offsetBy: lowerOffset)
        let metadataEnd = updated.index(updated.startIndex, offsetBy: upperOffset)
        updated.removeSubrange(metadataStart..<metadataEnd)
        return updated
    }

    private static func firstGeneratedMarkerRange(in markdown: String) -> Range<String.Index>? {
        [highlightsStartMarker, contentStartMarker]
            .compactMap { markdown.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    private static func generatedMetadataRange(in markdownPrefix: String) -> Range<String.Index>? {
        var cursor = markdownPrefix.startIndex
        var bestRange: Range<String.Index>?

        while cursor < markdownPrefix.endIndex {
            let lineStart = cursor
            let lineEnd = markdownPrefix[cursor...].firstIndex(of: "\n") ?? markdownPrefix.endIndex
            let line = String(markdownPrefix[lineStart..<lineEnd])

            if line.hasPrefix("Source: ") {
                var scanCursor = lineStart
                var metadataEnd = lineStart
                var sawCaptured = false

                while scanCursor < markdownPrefix.endIndex {
                    let scanLineEnd = markdownPrefix[scanCursor...].firstIndex(of: "\n") ?? markdownPrefix.endIndex
                    let scanLine = String(markdownPrefix[scanCursor..<scanLineEnd])
                    guard isGeneratedMetadataLine(scanLine) else { break }

                    if scanLine.hasPrefix("Captured: ") {
                        sawCaptured = true
                    }
                    metadataEnd = scanLineEnd == markdownPrefix.endIndex
                        ? markdownPrefix.endIndex
                        : markdownPrefix.index(after: scanLineEnd)
                    scanCursor = metadataEnd
                }

                if sawCaptured {
                    let rangeEnd = endOfFollowingBlankLines(in: markdownPrefix, from: metadataEnd)
                    bestRange = lineStart..<rangeEnd
                }
                let nextLineStart = lineEnd == markdownPrefix.endIndex
                    ? markdownPrefix.endIndex
                    : markdownPrefix.index(after: lineEnd)
                cursor = scanCursor > nextLineStart ? scanCursor : nextLineStart
            } else {
                cursor = lineEnd == markdownPrefix.endIndex
                    ? markdownPrefix.endIndex
                    : markdownPrefix.index(after: lineEnd)
            }
        }

        return bestRange
    }

    private static func isGeneratedMetadataLine(_ line: String) -> Bool {
        line.hasPrefix("Source: ")
            || line.hasPrefix("Readwise: ")
            || line.hasPrefix("Captured: ")
    }

    private static func endOfFollowingBlankLines(in markdown: String, from start: String.Index) -> String.Index {
        var cursor = start
        while cursor < markdown.endIndex {
            let lineEnd = markdown[cursor...].firstIndex(of: "\n") ?? markdown.endIndex
            let line = markdown[cursor..<lineEnd]
            guard line.trimmingCharacters(in: .whitespaces).isEmpty else {
                break
            }
            cursor = lineEnd == markdown.endIndex ? markdown.endIndex : markdown.index(after: lineEnd)
        }
        return cursor
    }

    private static func blockRange(in markdown: String, start: String, end: String) -> Range<String.Index>? {
        guard let startRange = markdown.range(of: start),
              let endRange = markdown.range(of: end, range: startRange.upperBound..<markdown.endIndex) else {
            return nil
        }
        return startRange.lowerBound..<endRange.upperBound
    }

    private static func extendedRangeRemovingTrailingBlankLines(in markdown: String, range: Range<String.Index>) -> Range<String.Index> {
        let extendedEnd = endOfFollowingBlankLines(in: markdown, from: range.upperBound)
        return range.lowerBound..<extendedEnd
    }

    private static func frontmatter(
        for book: ReadwiseBook,
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        preservingTags existingTags: [String] = []
    ) -> String {
        var lines: [String] = [
            "---",
            "id: \(id.uuidString)",
            "created: \(ISO8601DateFormatter.noto.string(from: createdAt))",
            "updated: \(ISO8601DateFormatter.noto.string(from: updatedAt))",
            "type: source",
            "source_kind: \(yamlScalar(book.sourceKind))",
            "capture_status: highlights_only",
            "canonical_key: \(yamlScalar(book.canonicalKey))",
            "source_title: \(yamlScalar(book.displayTitle))",
            "readwise_user_book_id: \(book.userBookID)",
        ]

        appendOptional("source_url", book.preferredSourceURL, to: &lines)
        appendOptional("readwise_url", book.readwiseURL, to: &lines)
        if book.source == "reader" {
            appendOptional("reader_document_id", book.externalID, to: &lines)
        }
        appendOptional("author", book.author, to: &lines)
        appendOptional("asin", book.asin, to: &lines)
        appendOptional("readwise_source", book.source, to: &lines)
        appendTags(["imported/readwise"], preserving: existingTags, to: &lines)
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func frontmatter(
        for document: ReaderDocument,
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        preservingTags existingTags: [String] = []
    ) -> String {
        var lines: [String] = [
            "---",
            "id: \(id.uuidString)",
            "created: \(ISO8601DateFormatter.noto.string(from: createdAt))",
            "updated: \(ISO8601DateFormatter.noto.string(from: updatedAt))",
            "type: source",
            "source_kind: \(yamlScalar(document.sourceKind))",
            "capture_status: \(document.contentMarkdown.isEmpty ? "metadata_only" : "full")",
            "canonical_key: \(yamlScalar(document.canonicalKey))",
            "source_title: \(yamlScalar(document.displayTitle))",
            "reader_document_id: \(yamlScalar(document.id))",
        ]

        appendOptional("source_url", document.preferredSourceURL, to: &lines)
        appendOptional("reader_url", document.url, to: &lines)
        appendOptional("reader_location", document.location, to: &lines)
        appendOptional("author", document.author, to: &lines)
        appendOptional("site_name", document.siteName, to: &lines)
        appendOptional("published", document.publishedDate, to: &lines)
        if let wordCount = document.wordCount {
            lines.append("word_count: \(wordCount)")
        }
        appendTags(["imported/reader"] + document.tags, preserving: existingTags, to: &lines)
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func frontmatter(
        for document: ReaderDocument,
        matchedBook: ReadwiseBook,
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        preservingTags existingTags: [String] = []
    ) -> String {
        var lines: [String] = [
            "---",
            "id: \(id.uuidString)",
            "created: \(ISO8601DateFormatter.noto.string(from: createdAt))",
            "updated: \(ISO8601DateFormatter.noto.string(from: updatedAt))",
            "type: source",
            "source_kind: \(yamlScalar(document.sourceKind))",
            "capture_status: \(document.contentMarkdown.isEmpty ? "highlights_only" : "full")",
            "canonical_key: \(yamlScalar(document.canonicalKey))",
            "source_title: \(yamlScalar(document.displayTitle))",
            "reader_document_id: \(yamlScalar(document.id))",
            "readwise_user_book_id: \(matchedBook.userBookID)",
        ]

        appendOptional("source_url", document.preferredSourceURL, to: &lines)
        appendOptional("reader_url", document.url, to: &lines)
        appendOptional("reader_location", document.location, to: &lines)
        appendOptional("readwise_url", document.url.nonEmpty ?? matchedBook.readwiseURL, to: &lines)
        if document.url.nonEmpty != matchedBook.readwiseURL.nonEmpty {
            appendOptional("readwise_bookreview_url", matchedBook.readwiseURL, to: &lines)
        }
        appendOptional("author", document.author ?? matchedBook.author, to: &lines)
        appendOptional("site_name", document.siteName, to: &lines)
        appendOptional("published", document.publishedDate, to: &lines)
        if let wordCount = document.wordCount {
            lines.append("word_count: \(wordCount)")
        }
        appendTags(["imported/reader", "imported/readwise"] + document.tags, preserving: existingTags, to: &lines)
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func appendTags(_ generatedTags: [String], preserving existingTags: [String], to lines: inout [String]) {
        lines.append("tags:")
        var seen = Set<String>()
        for tag in generatedTags.compactMap(\.nonEmpty) + existingTags.compactMap(\.nonEmpty) {
            guard seen.insert(tag).inserted else { continue }
            lines.append("  - \(tag.hasPrefix("imported/") ? tag : yamlScalar(tag))")
        }
    }

    private static func appendOptional(_ key: String, _ value: String?, to lines: inout [String]) {
        guard let value = value.nonEmpty else { return }
        lines.append("\(key): \(yamlScalar(value))")
    }

    private static func yamlScalar(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func blockquote(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { line in
            line.isEmpty ? ">" : "> \(line)"
        }
    }

    private static func replaceFrontmatter(in markdown: String, with frontmatter: String) -> String {
        guard markdown.hasPrefix("---"),
              let closeRange = markdown.range(
                of: "\n---",
                range: markdown.index(markdown.startIndex, offsetBy: 3)..<markdown.endIndex
              ) else {
            return frontmatter + "\n" + markdown
        }

        let afterClose = closeRange.upperBound
        let bodyStart = markdown.index(afterClose, offsetBy: markdown[afterClose...].hasPrefix("\n") ? 1 : 0)
        return frontmatter + "\n" + markdown[bodyStart...]
    }

    private static func parseFrontmatter(_ markdown: String) -> ExistingFrontmatter {
        guard markdown.hasPrefix("---"),
              let closeRange = markdown.range(
                of: "\n---",
                range: markdown.index(markdown.startIndex, offsetBy: 3)..<markdown.endIndex
              ) else {
            return ExistingFrontmatter(id: nil, createdAt: nil, tags: [])
        }

        let frontmatter = markdown[markdown.startIndex..<closeRange.upperBound]
        var id: UUID?
        var createdAt: Date?
        var tags: [String] = []
        var isReadingTags = false

        for line in frontmatter.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces) == "tags:" {
                isReadingTags = true
                continue
            }
            if isReadingTags {
                if let tag = parseTagLine(line) {
                    tags.append(tag)
                    continue
                }
                if line.hasPrefix(" ") || line.hasPrefix("\t") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }
                isReadingTags = false
            }

            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if key == "id" {
                id = UUID(uuidString: value)
            } else if key == "created" {
                createdAt = ISO8601DateFormatter.noto.date(from: value)
            }
        }

        return ExistingFrontmatter(id: id, createdAt: createdAt, tags: tags)
    }

    private static func parseTagLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") else { return nil }
        var value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
            value = value
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return value.nonEmpty
    }

    private static func insertGeneratedBlock(_ markdown: String, generatedBlock: String) -> String {
        let bodyStart = frontmatterBodyStart(in: markdown) ?? markdown.startIndex
        let body = markdown[bodyStart...]
        guard let headingEnd = body.firstIndex(of: "\n") else {
            return markdown + "\n\n" + generatedBlock
        }

        let insertionIndex = markdown.index(after: headingEnd)
        return String(markdown[..<insertionIndex]) + "\n" + generatedBlock + "\n" + markdown[insertionIndex...]
    }

    private static func frontmatterBodyStart(in markdown: String) -> String.Index? {
        guard markdown.hasPrefix("---"),
              let closeRange = markdown.range(
                of: "\n---",
                range: markdown.index(markdown.startIndex, offsetBy: 3)..<markdown.endIndex
              ) else {
            return nil
        }
        let afterClose = closeRange.upperBound
        if markdown[afterClose...].hasPrefix("\n") {
            return markdown.index(after: afterClose)
        }
        return afterClose
    }
}

private struct ExistingFrontmatter {
    let id: UUID?
    let createdAt: Date?
    let tags: [String]
}

private enum FNV1a64 {
    static func hash(_ string: String) -> String {
        var value: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value &*= 0x100000001b3
        }
        return String(format: "%016llx", value)
    }
}
