import Foundation
import Testing
@testable import NotoReadwiseSyncCore

@Suite("Readwise Source Sync")
struct ReadwiseSyncTests {
    @Test func decodeFixture() throws {
        let books = try loadFixtureBooks()

        #expect(books.count == 2)
        #expect(books[0].userBookID == 123)
        #expect(books[0].highlights.count == 2)
        #expect(books[0].activeHighlights.count == 1)
    }

    @Test func decodeNumericNextPageCursor() throws {
        let data = #"{"count":1,"nextPageCursor":12345,"results":[]}"#.data(using: .utf8)!
        let page = try JSONDecoder.readwise.decode(ReadwiseExportPage.self, from: data)

        #expect(page.nextPageCursor == "12345")
    }

    @Test func decodeReaderFixture() throws {
        let documents = try loadReaderFixtureDocuments()

        #expect(documents.count == 1)
        #expect(documents[0].id == "01readerfullcontent")
        #expect(documents[0].location == "later")
        #expect(documents[0].tags == ["content-creation"])
        #expect(documents[0].contentMarkdown.contains("# Long Reader Article"))
        #expect(documents[0].contentMarkdown.contains("**bold text**"))
        #expect(documents[0].contentMarkdown.contains("[a link](https://example.com/link)"))
    }

    @Test func readerDocumentTagMatchingRequiresAllRequestedTags() throws {
        let document = try loadReaderFixtureDocuments()[0]

        #expect(document.matchesAllTags([]))
        #expect(document.matchesAllTags(["content-creation"]))
        #expect(document.matchesAllTags(["CONTENT-CREATION"]))
        #expect(!document.matchesAllTags(["content-creation", "missing-tag"]))
        #expect(!document.matchesAllTags(["missing-tag"]))
    }

    @Test func htmlToMarkdownConvertsImagesToImageSyntax() {
        let html = #"""
        <article>
          <p>Before</p>
          <a href="https://cdn.example.com/chart.png"><img src="https://cdn.example.com/chart.png" alt="Usage chart"></a>
          <p>After <img src="https://cdn.example.com/inline.webp" alt=""></p>
        </article>
        """#

        let markdown = HTMLToMarkdown.convert(html)

        #expect(markdown.contains("![Usage chart](https://cdn.example.com/chart.png)"))
        #expect(markdown.contains("![](https://cdn.example.com/inline.webp)"))
        #expect(!markdown.contains("<img"))
    }

    @Test func renderSourceNoteUsesUpdatedAndMinimalBodyMetadata() throws {
        let book = try loadFixtureBooks()[0]
        let capturedAt = ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        let note = SourceNoteRenderer.renderNewNote(
            for: book,
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: capturedAt,
            capturedAt: capturedAt
        )

        #expect(note.contains("updated: 2026-04-21T00:00:00Z"))
        #expect(!note.contains("modified:"))
        #expect(note.contains("<!-- readwise:metadata:start -->"))
        #expect(note.contains("<!-- readwise:metadata:end -->"))
        #expect(note.contains("<!-- readwise:highlights:start -->"))
        #expect(note.contains("<!-- readwise:highlights:end -->"))
        #expect(note.contains("<!-- readwise:content:start -->"))
        #expect(note.contains("<!-- readwise:content:end -->"))
        #expect(note.contains("Source: [How to Do What You Love](https://example.com/love)"))
        #expect(note.contains("Readwise: [Open in Readwise](https://readwise.io/bookreview/123)"))
        #expect(note.contains("Captured: 2026-04-21T00:00:00Z"))
        #expect(!note.contains("Capture status:"))
        #expect(note.contains("> To do great work, you need to do what you love."))
        #expect(note.contains("> Note: Central thesis"))
        #expect(!note.contains("Deleted highlight should not render."))
        #expect(!note.contains("No full content imported"))
    }

    @Test func replaceGeneratedBlockPreservesManualMarkdown() throws {
        let book = try loadFixtureBooks()[0]
        let capturedAt = ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        var existing = SourceNoteRenderer.renderNewNote(
            for: book,
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: capturedAt,
            capturedAt: capturedAt
        )
        existing += "\n\nManual note outside generated block.\n"

        var changed = book
        changed.highlights = [
            ReadwiseHighlight(
                id: 999,
                isDeleted: false,
                text: "Replacement highlight.",
                note: nil,
                location: nil,
                locationType: nil,
                highlightedAt: nil,
                updatedAt: nil,
                url: nil,
                readwiseURL: nil,
                externalID: nil
            )
        ]

        let updated = SourceNoteRenderer.renderUpdatedNote(
            existingMarkdown: existing,
            book: changed,
            capturedAt: capturedAt
        )

        #expect(updated.contains("Manual note outside generated block."))
        #expect(updated.contains("> Replacement highlight."))
        #expect(!updated.contains("To do great work"))
    }

    @Test func readwiseHighlightUpdatePreservesReaderContentBlock() throws {
        let document = try loadReaderFixtureDocuments()[0]
        let capturedAt = ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        var existing = SourceNoteRenderer.renderNewNote(
            for: document,
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            createdAt: capturedAt,
            capturedAt: capturedAt
        )
        var book = try loadFixtureBooks()[0]
        book.highlights = [
            ReadwiseHighlight(id: 999, text: "Reader-linked highlight.")
        ]

        existing = SourceNoteRenderer.renderUpdatedNote(
            existingMarkdown: existing,
            book: book,
            capturedAt: capturedAt
        )

        #expect(existing.contains("> Reader-linked highlight."))
        #expect(existing.contains("# Long Reader Article"))
        #expect(existing.contains("First paragraph with **bold text**"))
    }

    @Test func updateMigratesEmptyPlaceholdersToEmptyBlocks() throws {
        let book = try loadFixtureBooks()[0]
        let capturedAt = ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        let existing = """
        ---
        id: 11111111-1111-1111-1111-111111111111
        created: 2026-04-21T00:00:00Z
        updated: 2026-04-21T00:00:00Z
        ---
        # Placeholder Note

        Source: Placeholder
        Captured: 2026-04-21T00:00:00Z

        <!-- readwise:highlights:start -->
        _No highlights imported._
        <!-- readwise:highlights:end -->

        <!-- readwise:content:start -->
        _No full content imported._
        <!-- readwise:content:end -->
        """

        let updated = SourceNoteRenderer.renderUpdatedNote(
            existingMarkdown: existing,
            book: book,
            capturedAt: capturedAt
        )

        #expect(!updated.contains("No highlights imported"))
        #expect(!updated.contains("No full content imported"))
        #expect(updated.contains("<!-- readwise:content:start -->\n<!-- readwise:content:end -->"))
    }

    @Test func readerUpdateMigratesEmptyHighlightsPlaceholder() throws {
        let document = try loadReaderFixtureDocuments()[0]
        let capturedAt = ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        let existing = """
        ---
        id: 11111111-1111-1111-1111-111111111111
        created: 2026-04-21T00:00:00Z
        updated: 2026-04-21T00:00:00Z
        ---
        # Placeholder Note

        Source: Placeholder
        Captured: 2026-04-21T00:00:00Z

        <!-- readwise:highlights:start -->
        _No highlights imported._
        <!-- readwise:highlights:end -->

        <!-- readwise:content:start -->
        Old content.
        <!-- readwise:content:end -->
        """

        let updated = SourceNoteRenderer.renderUpdatedNote(
            existingMarkdown: existing,
            document: document,
            capturedAt: capturedAt
        )

        #expect(!updated.contains("No highlights imported"))
        #expect(updated.contains("<!-- readwise:highlights:start -->\n<!-- readwise:highlights:end -->"))
        #expect(updated.contains("First paragraph with **bold text**"))
    }

    @Test func readerUpdatePreservesManualMarkdownBetweenMetadataAndGeneratedBlocks() throws {
        let document = try loadReaderFixtureDocuments()[0]
        let capturedAt = ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        var existing = SourceNoteRenderer.renderNewNote(
            for: document,
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            createdAt: capturedAt,
            capturedAt: capturedAt
        )
        existing = existing.replacingOccurrences(
            of: "\n<!-- readwise:highlights:start -->",
            with: "\n## Thoughts\nmanual note before generated markers\n\n<!-- readwise:highlights:start -->"
        )

        let updated = SourceNoteRenderer.renderUpdatedNote(
            existingMarkdown: existing,
            document: document,
            capturedAt: ISO8601DateFormatter.noto.date(from: "2026-04-22T00:00:00Z")!
        )

        #expect(updated.contains("Captured: 2026-04-22T00:00:00Z"))
        #expect(!updated.contains("Captured: 2026-04-21T00:00:00Z"))
        #expect(updated.contains("<!-- readwise:metadata:start -->"))
        #expect(updated.contains("<!-- readwise:metadata:end -->"))
        #expect(updated.contains("## Thoughts\nmanual note before generated markers"))
        #expect(updated.contains("<!-- readwise:highlights:start -->\n<!-- readwise:highlights:end -->"))
        #expect(updated.contains("First paragraph with **bold text**"))
    }

    @Test func readerUpdateMigratesUnmarkedMetadataIntoGeneratedBlock() throws {
        let document = try loadReaderFixtureDocuments()[0]
        let existing = """
        ---
        id: 11111111-1111-1111-1111-111111111111
        created: 2026-04-21T00:00:00Z
        updated: 2026-04-21T00:00:00Z
        ---
        # Placeholder Note

        Source: Placeholder
        Readwise: [Open in Reader](https://read.readwise.io/read/old)
        Captured: 2026-04-21T00:00:00Z

        ## Thoughts
        Keep this.

        <!-- readwise:highlights:start -->
        <!-- readwise:highlights:end -->

        <!-- readwise:content:start -->
        Old content.
        <!-- readwise:content:end -->
        """

        let updated = SourceNoteRenderer.renderUpdatedNote(
            existingMarkdown: existing,
            document: document,
            capturedAt: ISO8601DateFormatter.noto.date(from: "2026-04-22T00:00:00Z")!
        )

        #expect(updated.contains("<!-- readwise:metadata:start -->\nSource: [Long Reader Article](https://example.com/full-article)"))
        #expect(updated.contains("Captured: 2026-04-22T00:00:00Z\n<!-- readwise:metadata:end -->"))
        #expect(!updated.contains("Source: Placeholder"))
        #expect(updated.contains("## Thoughts\nKeep this."))
    }

    @Test func readerUpdateReplacesExistingMetadataBlock() throws {
        let document = try loadReaderFixtureDocuments()[0]
        let existing = """
        ---
        id: 11111111-1111-1111-1111-111111111111
        created: 2026-04-21T00:00:00Z
        updated: 2026-04-21T00:00:00Z
        ---
        # Placeholder Note

        <!-- readwise:metadata:start -->
        Source: Placeholder
        Captured: 2026-04-21T00:00:00Z
        <!-- readwise:metadata:end -->

        ## Thoughts
        Keep this too.

        <!-- readwise:highlights:start -->
        <!-- readwise:highlights:end -->

        <!-- readwise:content:start -->
        Old content.
        <!-- readwise:content:end -->
        """

        let updated = SourceNoteRenderer.renderUpdatedNote(
            existingMarkdown: existing,
            document: document,
            capturedAt: ISO8601DateFormatter.noto.date(from: "2026-04-22T00:00:00Z")!
        )

        #expect(!updated.contains("Source: Placeholder"))
        #expect(updated.contains("<!-- readwise:metadata:start -->"))
        #expect(updated.contains("Captured: 2026-04-22T00:00:00Z\n<!-- readwise:metadata:end -->"))
        #expect(updated.contains("## Thoughts\nKeep this too."))
    }

    @Test func readerUpdatePreservesExistingFrontmatterTags() throws {
        let document = try loadReaderFixtureDocuments()[0]
        let capturedAt = ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        var existing = SourceNoteRenderer.renderNewNote(
            for: document,
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            createdAt: capturedAt,
            capturedAt: capturedAt
        )
        existing = existing.replacingOccurrences(
            of: "  - \"content-creation\"\n---",
            with: "  - \"content-creation\"\n  - \"manual/tag\"\n---"
        )

        let updated = SourceNoteRenderer.renderUpdatedNote(
            existingMarkdown: existing,
            document: document,
            capturedAt: ISO8601DateFormatter.noto.date(from: "2026-04-22T00:00:00Z")!
        )

        #expect(updated.contains("  - imported/reader"))
        #expect(updated.contains("  - \"content-creation\""))
        #expect(updated.contains("  - \"manual/tag\""))
    }

    @Test func syncCreatesFlatSourceNotesAndResolvesFilenameConflicts() throws {
        let books = try loadFixtureBooks()
        let tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoReadwiseSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempVault) }

        let result = try SourceNoteSyncEngine().sync(
            books: books,
            vaultURL: tempVault,
            sourceDirectory: "Sources",
            dryRun: false,
            syncedAt: ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        )

        #expect(result.created == 2)
        #expect(result.updated == 0)
        #expect(FileManager.default.fileExists(atPath: tempVault.appendingPathComponent("Sources/How to Do What You Love.md").path))
        #expect(FileManager.default.fileExists(atPath: tempVault.appendingPathComponent("Sources/How to Do What You Love (2).md").path))
        #expect(FileManager.default.fileExists(atPath: tempVault.appendingPathComponent(".noto/sync/readwise.json").path))
    }

    @Test func syncCanRunAgainstLimitedBookSet() throws {
        let books = Array(try loadFixtureBooks().prefix(1))
        let tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoReadwiseSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempVault) }

        let result = try SourceNoteSyncEngine().sync(
            books: books,
            vaultURL: tempVault,
            sourceDirectory: "Sources",
            dryRun: false,
            syncedAt: ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        )

        #expect(result.created == 1)
        #expect(FileManager.default.fileExists(atPath: tempVault.appendingPathComponent("Sources/How to Do What You Love.md").path))
        #expect(!FileManager.default.fileExists(atPath: tempVault.appendingPathComponent("Sources/How to Do What You Love (2).md").path))
    }

    @Test func syncUsesCapturesAsDefaultSourceDirectory() throws {
        let books = Array(try loadFixtureBooks().prefix(1))
        let tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoDefaultCaptureDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempVault) }

        let result = try SourceNoteSyncEngine().sync(
            books: books,
            vaultURL: tempVault,
            dryRun: false,
            syncedAt: ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        )

        #expect(result.sourceDirectoryURL.lastPathComponent == "Captures")
        #expect(FileManager.default.fileExists(atPath: tempVault.appendingPathComponent("Captures").path))
        #expect(FileManager.default.fileExists(atPath: tempVault.appendingPathComponent("Captures/How to Do What You Love.md").path))
    }

    @Test func syncReaderDocumentCreatesFullContentSourceNote() throws {
        let documents = try loadReaderFixtureDocuments()
        let tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoReaderSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempVault) }

        let result = try SourceNoteSyncEngine().syncReaderDocuments(
            documents,
            vaultURL: tempVault,
            sourceDirectory: "Sources",
            dryRun: false,
            syncedAt: ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        )
        let noteURL = tempVault.appendingPathComponent("Sources/Long Reader Article.md")
        let note = try String(contentsOf: noteURL, encoding: .utf8)

        #expect(result.created == 1)
        #expect(note.contains("capture_status: full"))
        #expect(note.contains("canonical_key: \"reader:01readerfullcontent\""))
        #expect(note.contains("reader_document_id: \"01readerfullcontent\""))
        #expect(note.contains("reader_location: \"later\""))
        #expect(note.contains("Source: [Long Reader Article](https://example.com/full-article)"))
        #expect(note.contains("Readwise: [Open in Reader](https://read.readwise.io/new/read/01readerfullcontent)"))
        #expect(note.contains("  - \"content-creation\""))
        #expect(note.contains("<!-- readwise:highlights:start -->"))
        #expect(!note.contains("No highlights imported"))
        #expect(note.contains("<!-- readwise:content:start -->"))
        #expect(note.contains("# Long Reader Article"))
        #expect(note.contains("**bold text**"))
    }

    @Test func syncReaderDocumentCanJoinMatchingReadwiseHighlights() throws {
        let documents = try loadReaderFixtureDocuments()
        let matchedBook = ReadwiseBook(
            userBookID: 987,
            title: documents[0].title,
            readableTitle: documents[0].title,
            author: documents[0].author,
            source: "reader",
            category: "articles",
            readwiseURL: "https://readwise.io/bookreview/987",
            sourceURL: documents[0].sourceURL,
            externalID: documents[0].id,
            highlights: [
                ReadwiseHighlight(id: 1, text: "Joined highlight.", note: "Joined note")
            ]
        )
        let tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoReaderJoinTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempVault) }

        let result = try SourceNoteSyncEngine().syncReaderDocuments(
            documents,
            matchedReadwiseBooks: [documents[0].id: matchedBook],
            vaultURL: tempVault,
            sourceDirectory: "Sources",
            dryRun: false,
            syncedAt: ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        )
        let noteURL = tempVault.appendingPathComponent("Sources/Long Reader Article.md")
        let note = try String(contentsOf: noteURL, encoding: .utf8)

        #expect(result.created == 1)
        #expect(note.contains("readwise_user_book_id: 987"))
        #expect(note.contains("reader_url: \"https://read.readwise.io/new/read/01readerfullcontent\""))
        #expect(note.contains("reader_location: \"later\""))
        #expect(note.contains("readwise_url: \"https://read.readwise.io/new/read/01readerfullcontent\""))
        #expect(note.contains("readwise_bookreview_url: \"https://readwise.io/bookreview/987\""))
        #expect(note.contains("Readwise: [Open in Reader](https://read.readwise.io/new/read/01readerfullcontent)"))
        #expect(note.contains("  - \"content-creation\""))
        #expect(note.contains("> Joined highlight."))
        #expect(note.contains("> Note: Joined note"))
        #expect(note.contains("# Long Reader Article"))
    }

    private func loadFixtureBooks() throws -> [ReadwiseBook] {
        let url = Bundle.module.url(forResource: "readwise-export", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder.readwise.decode(ReadwiseExportPage.self, from: data).results
    }

    private func loadReaderFixtureDocuments() throws -> [ReaderDocument] {
        let url = Bundle.module.url(forResource: "reader-list", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder.readwise.decode(ReaderListPage.self, from: data).results
    }
}
