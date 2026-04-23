import Foundation

public enum SourceNoteRenderer {
    public static let startMarker = "<!-- noto:source:start -->"
    public static let endMarker = "<!-- noto:source:end -->"
    public static let highlightsStartMarker = "<!-- noto:highlights:start -->"
    public static let highlightsEndMarker = "<!-- noto:highlights:end -->"
    public static let contentStartMarker = "<!-- noto:content:start -->"
    public static let contentEndMarker = "<!-- noto:content:end -->"

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
            with: frontmatter(for: book, id: id, createdAt: createdAt, updatedAt: capturedAt)
        )
        return replaceGeneratedSection(
            in: markdownWithUpdatedFrontmatter,
            metadataBlock: metadataBlock(for: book, capturedAt: capturedAt),
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
            with: frontmatter(for: document, id: id, createdAt: createdAt, updatedAt: capturedAt)
        )
        return replaceGeneratedSection(
            in: markdownWithUpdatedFrontmatter,
            metadataBlock: metadataBlock(for: document, capturedAt: capturedAt),
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
            with: frontmatter(for: document, matchedBook: matchedBook, id: id, createdAt: createdAt, updatedAt: capturedAt)
        )
        return replaceGeneratedSection(
            in: markdownWithUpdatedFrontmatter,
            metadataBlock: metadataBlock(for: document, matchedBook: matchedBook, capturedAt: capturedAt),
            highlightsBlock: highlightsBlock(for: matchedBook),
            contentBlock: contentBlock(for: document)
        )
    }

    public static func generatedBlock(for book: ReadwiseBook, capturedAt: Date) -> String {
        generatedSection(
            metadataBlock: metadataBlock(for: book, capturedAt: capturedAt),
            highlightsBlock: highlightsBlock(for: book),
            contentBlock: emptyContentBlock()
        )
    }

    public static func generatedBlock(for document: ReaderDocument, capturedAt: Date) -> String {
        generatedSection(
            metadataBlock: metadataBlock(for: document, capturedAt: capturedAt),
            highlightsBlock: emptyHighlightsBlock(),
            contentBlock: contentBlock(for: document)
        )
    }

    public static func generatedBlock(for document: ReaderDocument, matchedBook: ReadwiseBook, capturedAt: Date) -> String {
        generatedSection(
            metadataBlock: metadataBlock(for: document, matchedBook: matchedBook, capturedAt: capturedAt),
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

    private static func metadataBlock(for book: ReadwiseBook, capturedAt: Date) -> String {
        var lines = ["Source: \(sourceMarkdown(for: book))"]
        if let readwiseURL = book.readwiseURL.nonEmpty {
            lines.append("Readwise: [Open in Readwise](\(readwiseURL))")
        }
        lines.append("Captured: \(ISO8601DateFormatter.noto.string(from: capturedAt))")
        return lines.joined(separator: "\n")
    }

    private static func metadataBlock(for document: ReaderDocument, capturedAt: Date) -> String {
        var lines = ["Source: \(sourceMarkdown(for: document))"]
        if let readwiseURL = document.url.nonEmpty {
            lines.append("Readwise: [Open in Reader](\(readwiseURL))")
        }
        lines.append("Captured: \(ISO8601DateFormatter.noto.string(from: capturedAt))")
        return lines.joined(separator: "\n")
    }

    private static func metadataBlock(for document: ReaderDocument, matchedBook: ReadwiseBook, capturedAt: Date) -> String {
        var lines = ["Source: \(sourceMarkdown(for: document))"]
        if let readerURL = document.url.nonEmpty {
            lines.append("Readwise: [Open in Reader](\(readerURL))")
        } else if let readwiseURL = matchedBook.readwiseURL.nonEmpty {
            lines.append("Readwise: [Open in Readwise](\(readwiseURL))")
        }
        lines.append("Captured: \(ISO8601DateFormatter.noto.string(from: capturedAt))")
        return lines.joined(separator: "\n")
    }

    private static func emptyHighlightsBlock() -> String {
        [highlightsStartMarker, highlightsEndMarker]
            .joined(separator: "\n")
    }

    private static func emptyContentBlock() -> String {
        [contentStartMarker, contentEndMarker]
            .joined(separator: "\n")
    }

    private static func generatedSection(
        metadataBlock: String,
        highlightsBlock: String,
        contentBlock: String
    ) -> String {
        [metadataBlock, highlightsBlock, contentBlock].joined(separator: "\n\n")
    }

    private static func replaceGeneratedSection(
        in markdown: String,
        metadataBlock: String,
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
            return replaceMetadataBeforeFirstGeneratedBlock(in: updated, with: metadataBlock)
        }

        return replaceGeneratedBlock(
            in: markdown,
            with: generatedSection(
                metadataBlock: metadataBlock,
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

    private static func replaceMetadataBeforeFirstGeneratedBlock(in markdown: String, with metadataBlock: String) -> String {
        guard let firstMarkerRange = firstGeneratedMarkerRange(in: markdown) else {
            return insertGeneratedBlock(markdown, generatedBlock: metadataBlock)
        }

        let lineStart = markdown[..<firstMarkerRange.lowerBound].lastIndex(of: "\n")
            .map { markdown.index(after: $0) } ?? markdown.startIndex
        let beforeMarker = markdown[..<lineStart]
        let beforeMarkerString = String(beforeMarker)
        let metadataStart: String.Index
        if let metadataStartInPrefix = sourceMetadataStart(in: beforeMarkerString) {
            let offset = beforeMarkerString.distance(from: beforeMarkerString.startIndex, to: metadataStartInPrefix)
            metadataStart = markdown.index(markdown.startIndex, offsetBy: offset)
        } else {
            metadataStart = lineStart
        }

        var updated = markdown
        updated.replaceSubrange(metadataStart..<lineStart, with: metadataBlock + "\n\n")
        return updated
    }

    private static func firstGeneratedMarkerRange(in markdown: String) -> Range<String.Index>? {
        [highlightsStartMarker, contentStartMarker]
            .compactMap { markdown.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    private static func sourceMetadataStart(in markdownPrefix: String) -> String.Index? {
        let patterns = ["\nSource: ", "\n\nSource: "]
        for pattern in patterns {
            if let range = markdownPrefix.range(of: pattern, options: .backwards) {
                return markdownPrefix.index(after: range.lowerBound)
            }
        }
        return nil
    }

    private static func frontmatter(
        for book: ReadwiseBook,
        id: UUID,
        createdAt: Date,
        updatedAt: Date
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
        lines.append("tags:")
        lines.append("  - imported/readwise")
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func frontmatter(
        for document: ReaderDocument,
        id: UUID,
        createdAt: Date,
        updatedAt: Date
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
        lines.append("tags:")
        lines.append("  - imported/reader")
        appendReaderTags(document.tags, to: &lines)
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func frontmatter(
        for document: ReaderDocument,
        matchedBook: ReadwiseBook,
        id: UUID,
        createdAt: Date,
        updatedAt: Date
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
        lines.append("tags:")
        lines.append("  - imported/reader")
        lines.append("  - imported/readwise")
        appendReaderTags(document.tags, to: &lines)
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func appendReaderTags(_ tags: [String], to lines: inout [String]) {
        for tag in tags.compactMap(\.nonEmpty) {
            lines.append("  - \(yamlScalar(tag))")
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

    private static func sourceMarkdown(for book: ReadwiseBook) -> String {
        guard let url = book.preferredSourceURL else {
            return book.displayTitle
        }
        return "[\(escapeLinkText(book.displayTitle))](\(url))"
    }

    private static func sourceMarkdown(for document: ReaderDocument) -> String {
        guard let url = document.preferredSourceURL else {
            return document.displayTitle
        }
        return "[\(escapeLinkText(document.displayTitle))](\(url))"
    }

    private static func escapeLinkText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
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
            return ExistingFrontmatter(id: nil, createdAt: nil)
        }

        let frontmatter = markdown[markdown.startIndex..<closeRange.upperBound]
        var id: UUID?
        var createdAt: Date?

        for line in frontmatter.components(separatedBy: "\n") {
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

        return ExistingFrontmatter(id: id, createdAt: createdAt)
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
