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
    private static let importerOwnedFrontmatterKeys: Set<String> = [
        "id",
        "created",
        "updated",
        "type",
        "source_kind",
        "capture_status",
        "canonical_key",
        "source_title",
        "reader_document_id",
        "readwise_user_book_id",
        "source_url",
        "reader_url",
        "reader_location",
        "readwise_url",
        "readwise_bookreview_url",
        "author",
        "site_name",
        "published",
        "word_count",
        "asin",
        "readwise_source",
        "tags",
    ]

    public static func renderNewNote(
        for book: ReadwiseBook,
        id: UUID,
        createdAt: Date,
        capturedAt: Date
    ) -> String {
        renderFrontmatter(frontmatterEntries(for: book, id: id, createdAt: createdAt, updatedAt: capturedAt))
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
        let contentBlock = normalizedExistingBlock(
            in: existingMarkdown,
            start: contentStartMarker,
            end: contentEndMarker,
            emptyBlock: emptyContentBlock(),
            legacyPlaceholders: ["_No full content imported._", "_No Reader content available._"]
        )
        let captureStatus = generatedBlockHasBody(contentBlock, start: contentStartMarker, end: contentEndMarker)
            ? "full"
            : "highlights_only"
        let markdownWithUpdatedFrontmatter = replaceFrontmatter(
            in: existingMarkdown,
            with: frontmatterEntries(
                for: book,
                id: id,
                createdAt: createdAt,
                updatedAt: capturedAt,
                preservingTags: metadata.tags,
                captureStatus: captureStatus
            )
        )
        return replaceGeneratedSection(
            in: markdownWithUpdatedFrontmatter,
            highlightsBlock: highlightsBlock(for: book),
            contentBlock: contentBlock
        )
    }

    public static func renderNewNote(
        for document: ReaderDocument,
        id: UUID,
        createdAt: Date,
        capturedAt: Date
    ) -> String {
        renderFrontmatter(frontmatterEntries(for: document, id: id, createdAt: createdAt, updatedAt: capturedAt))
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
        renderFrontmatter(frontmatterEntries(for: document, matchedBook: matchedBook, id: id, createdAt: createdAt, updatedAt: capturedAt))
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
            with: frontmatterEntries(for: document, id: id, createdAt: createdAt, updatedAt: capturedAt, preservingTags: metadata.tags)
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
            with: frontmatterEntries(for: document, matchedBook: matchedBook, id: id, createdAt: createdAt, updatedAt: capturedAt, preservingTags: metadata.tags)
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

    private static func generatedBlockHasBody(_ block: String, start: String, end: String) -> Bool {
        var body = block
        body = body.replacingOccurrences(of: start, with: "")
        body = body.replacingOccurrences(of: end, with: "")
        return body.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty != nil
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

    private static func frontmatterEntries(
        for book: ReadwiseBook,
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        preservingTags existingTags: [String] = [],
        captureStatus: String = "highlights_only"
    ) -> [FrontmatterEntry] {
        var entries: [FrontmatterEntry] = [
            .literal("id", id.uuidString),
            .literal("created", ISO8601DateFormatter.noto.string(from: createdAt)),
            .literal("updated", ISO8601DateFormatter.noto.string(from: updatedAt)),
            .literal("type", "source"),
            .scalar("source_kind", yamlScalar(book.sourceKind)),
            .literal("capture_status", captureStatus),
            .scalar("canonical_key", yamlScalar(book.canonicalKey)),
            .scalar("source_title", yamlScalar(book.displayTitle)),
            .literal("readwise_user_book_id", "\(book.userBookID)"),
        ]

        if book.source == "reader" {
            appendOptional("reader_document_id", book.externalID, to: &entries)
        }
        appendOptional("source_url", book.preferredSourceURL, to: &entries)
        if let readerWebURL = book.readerWebURL {
            appendOptional("reader_url", readerWebURL, to: &entries)
            appendOptional("readwise_url", readerWebURL, to: &entries)
            if readerWebURL.nonEmpty != book.readwiseURL.nonEmpty {
                appendOptional("readwise_bookreview_url", book.readwiseURL, to: &entries)
            }
        } else {
            appendOptional("readwise_url", book.readwiseURL, to: &entries)
        }
        appendOptional("author", book.author, to: &entries)
        appendOptional("asin", book.asin, to: &entries)
        appendOptional("readwise_source", book.source, to: &entries)
        appendTags(["imported/readwise"], preserving: existingTags, to: &entries)
        return entries
    }

    private static func frontmatterEntries(
        for document: ReaderDocument,
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        preservingTags existingTags: [String] = []
    ) -> [FrontmatterEntry] {
        var entries: [FrontmatterEntry] = [
            .literal("id", id.uuidString),
            .literal("created", ISO8601DateFormatter.noto.string(from: createdAt)),
            .literal("updated", ISO8601DateFormatter.noto.string(from: updatedAt)),
            .literal("type", "source"),
            .scalar("source_kind", yamlScalar(document.sourceKind)),
            .literal("capture_status", document.contentMarkdown.isEmpty ? "metadata_only" : "full"),
            .scalar("canonical_key", yamlScalar(document.canonicalKey)),
            .scalar("source_title", yamlScalar(document.displayTitle)),
            .scalar("reader_document_id", yamlScalar(document.id)),
        ]

        appendOptional("source_url", document.preferredSourceURL, to: &entries)
        appendOptional("reader_url", document.readerWebURL, to: &entries)
        appendOptional("reader_location", document.location, to: &entries)
        appendOptional("author", document.author, to: &entries)
        appendOptional("site_name", document.siteName, to: &entries)
        appendOptional("published", document.publishedDate, to: &entries)
        if let wordCount = document.wordCount {
            entries.append(.literal("word_count", "\(wordCount)"))
        }
        appendTags(["imported/reader"] + document.tags, preserving: existingTags, to: &entries)
        return entries
    }

    private static func frontmatterEntries(
        for document: ReaderDocument,
        matchedBook: ReadwiseBook,
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        preservingTags existingTags: [String] = []
    ) -> [FrontmatterEntry] {
        var entries: [FrontmatterEntry] = [
            .literal("id", id.uuidString),
            .literal("created", ISO8601DateFormatter.noto.string(from: createdAt)),
            .literal("updated", ISO8601DateFormatter.noto.string(from: updatedAt)),
            .literal("type", "source"),
            .scalar("source_kind", yamlScalar(document.sourceKind)),
            .literal("capture_status", document.contentMarkdown.isEmpty ? "highlights_only" : "full"),
            .scalar("canonical_key", yamlScalar(document.canonicalKey)),
            .scalar("source_title", yamlScalar(document.displayTitle)),
            .scalar("reader_document_id", yamlScalar(document.id)),
            .literal("readwise_user_book_id", "\(matchedBook.userBookID)"),
        ]

        appendOptional("source_url", document.preferredSourceURL, to: &entries)
        appendOptional("reader_url", document.readerWebURL, to: &entries)
        appendOptional("reader_location", document.location, to: &entries)
        appendOptional("readwise_url", document.readerWebURL, to: &entries)
        if document.readerWebURL.nonEmpty != matchedBook.readwiseURL.nonEmpty {
            appendOptional("readwise_bookreview_url", matchedBook.readwiseURL, to: &entries)
        }
        appendOptional("author", document.author ?? matchedBook.author, to: &entries)
        appendOptional("site_name", document.siteName, to: &entries)
        appendOptional("published", document.publishedDate, to: &entries)
        if let wordCount = document.wordCount {
            entries.append(.literal("word_count", "\(wordCount)"))
        }
        appendTags(["imported/reader", "imported/readwise"] + document.tags, preserving: existingTags, to: &entries)
        return entries
    }

    private static func appendTags(_ generatedTags: [String], preserving existingTags: [String], to entries: inout [FrontmatterEntry]) {
        var seen = Set<String>()
        var renderedTags: [String] = []
        for tag in generatedTags.compactMap(\.nonEmpty) + existingTags.compactMap(\.nonEmpty) {
            guard seen.insert(tag).inserted else { continue }
            renderedTags.append(tag.hasPrefix("imported/") ? tag : yamlScalar(tag))
        }
        entries.append(.list("tags", values: renderedTags))
    }

    private static func appendOptional(_ key: String, _ value: String?, to entries: inout [FrontmatterEntry]) {
        guard let value = value.nonEmpty else { return }
        entries.append(.scalar(key, yamlScalar(value)))
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

    private static func renderFrontmatter(_ entries: [FrontmatterEntry]) -> String {
        FrontmatterDocument.render(entries)
    }

    private static func replaceFrontmatter(in markdown: String, with importerEntries: [FrontmatterEntry]) -> String {
        let document = FrontmatterDocument(markdown: markdown)
        let mergedEntries = document.merging(
            importerEntries: importerEntries,
            importerOwnedKeys: importerOwnedFrontmatterKeys
        )
        return renderFrontmatter(mergedEntries) + "\n" + document.body
    }

    private static func parseFrontmatter(_ markdown: String) -> ExistingFrontmatter {
        let frontmatter = FrontmatterDocument(markdown: markdown)
        let id = frontmatter.scalarValue(for: "id").flatMap(UUID.init(uuidString:))
        let createdAt = frontmatter.scalarValue(for: "created").flatMap(ISO8601DateFormatter.noto.date(from:))
        return ExistingFrontmatter(id: id, createdAt: createdAt, tags: frontmatter.stringList(for: "tags"))
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
