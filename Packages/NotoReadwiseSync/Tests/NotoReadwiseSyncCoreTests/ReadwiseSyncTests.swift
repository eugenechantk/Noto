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
        #expect(note.contains("<!-- readwise:highlights:start -->"))
        #expect(note.contains("<!-- readwise:highlights:end -->"))
        #expect(note.contains("<!-- readwise:content:start -->"))
        #expect(note.contains("<!-- readwise:content:end -->"))
        #expect(!note.contains("Source: "))
        #expect(!note.contains("Readwise: "))
        #expect(!note.contains("Captured: "))
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
        #expect(existing.contains("capture_status: full"))
        #expect(existing.contains("reader_url: \"https://read.readwise.io/read/01readerarticle\""))
        #expect(existing.contains("readwise_url: \"https://read.readwise.io/read/01readerarticle\""))
        #expect(existing.contains("readwise_bookreview_url: \"https://readwise.io/bookreview/123\""))
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

        #expect(!updated.contains("Captured: 2026-04-22T00:00:00Z"))
        #expect(!updated.contains("Captured: 2026-04-21T00:00:00Z"))
        #expect(!updated.contains("<!-- readwise:metadata:start -->"))
        #expect(!updated.contains("<!-- readwise:metadata:end -->"))
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

        #expect(!updated.contains("Source: Placeholder"))
        #expect(!updated.contains("Readwise: [Open in Reader](https://read.readwise.io/read/old)"))
        #expect(!updated.contains("Captured: 2026-04-22T00:00:00Z"))
        #expect(!updated.contains("<!-- readwise:metadata:start -->"))
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
        #expect(!updated.contains("<!-- readwise:metadata:start -->"))
        #expect(!updated.contains("Captured: 2026-04-22T00:00:00Z"))
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

    @Test func readerUpdatePreservesManualFrontmatterFields() throws {
        let document = try loadReaderFixtureDocuments()[0]
        let existing = """
        ---
        id: 11111111-1111-1111-1111-111111111111
        created: 2026-04-21T00:00:00Z
        updated: 2026-04-21T00:00:00Z
        type: source
        canonical_key: "reader:01readerfullcontent"
        mood: "keep"
        aliases:
          - "Long Form"
        tags:
          - "manual/tag"
        ---
        # Placeholder Note

        Manual content before generated markers.

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

        #expect(updated.contains("mood: \"keep\""))
        #expect(updated.contains("aliases:\n  - \"Long Form\""))
        #expect(updated.contains("  - \"manual/tag\""))
        #expect(updated.contains("reader_document_id: \"01readerfullcontent\""))
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

    @Test func syncReportsWrittenURLsForEveryNonDeletedBook() throws {
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

        let nonDeletedCount = books.filter { !$0.isDeleted }.count
        #expect(result.writtenURLs.count == nonDeletedCount)
        for url in result.writtenURLs {
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(url.standardizedFileURL == url)
            #expect(url.path.hasPrefix(tempVault.standardizedFileURL.path))
        }
    }

    @Test func dryRunSyncReportsNoWrittenURLs() throws {
        let books = try loadFixtureBooks()
        let tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoReadwiseSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempVault) }

        let result = try SourceNoteSyncEngine().sync(
            books: books,
            vaultURL: tempVault,
            sourceDirectory: "Sources",
            dryRun: true,
            syncedAt: ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        )

        #expect(result.writtenURLs.isEmpty)
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

    @Test func syncSkipsDeletedReadwiseSourceWithoutDeletingLocalNote() throws {
        let tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoDeletedReadwiseSourceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempVault) }

        let capturesURL = tempVault.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: capturesURL, withIntermediateDirectories: true)
        let existingBook = try loadFixtureBooks()[0]
        let noteURL = capturesURL.appendingPathComponent("How to Do What You Love.md")
        try SourceNoteRenderer.renderNewNote(
            for: existingBook,
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            createdAt: ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!,
            capturedAt: ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        ).write(to: noteURL, atomically: true, encoding: .utf8)

        var deletedBook = existingBook
        deletedBook = ReadwiseBook(
            userBookID: existingBook.userBookID,
            isDeleted: true,
            title: existingBook.title,
            readableTitle: existingBook.readableTitle,
            author: existingBook.author,
            source: existingBook.source,
            category: existingBook.category,
            readwiseURL: existingBook.readwiseURL,
            sourceURL: existingBook.sourceURL,
            externalID: existingBook.externalID,
            highlights: existingBook.highlights
        )

        let result = try SourceNoteSyncEngine().sync(
            books: [deletedBook],
            vaultURL: tempVault,
            dryRun: false,
            syncedAt: ISO8601DateFormatter.noto.date(from: "2026-04-22T00:00:00Z")!
        )

        #expect(result.created == 0)
        #expect(result.updated == 0)
        #expect(result.skippedDeleted == 1)
        #expect(FileManager.default.fileExists(atPath: noteURL.path))
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
        #expect(!note.contains("Source: "))
        #expect(!note.contains("Readwise: "))
        #expect(!note.contains("Captured: "))
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
        #expect(!note.contains("Readwise: "))
        #expect(note.contains("  - \"content-creation\""))
        #expect(note.contains("> Joined highlight."))
        #expect(note.contains("> Note: Joined note"))
        #expect(note.contains("# Long Reader Article"))
    }

    @Test func joinedReaderDocumentFallsBackToReaderURLFromDocumentID() throws {
        let data = Data("""
        {
          "count": 1,
          "nextPageCursor": null,
          "results": [
            {
              "id": "01readerwithouturl",
              "source_url": "https://example.com/source",
              "title": "Reader Without URL",
              "category": "article",
              "location": "later",
              "tags": {},
              "html_content": "<article><p>Reader body.</p></article>"
            }
          ]
        }
        """.utf8)
        let document = try JSONDecoder.readwise.decode(ReaderListPage.self, from: data).results[0]
        let matchedBook = ReadwiseBook(
            userBookID: 988,
            title: document.title,
            readableTitle: document.title,
            source: "reader",
            category: "articles",
            readwiseURL: "https://readwise.io/bookreview/988",
            sourceURL: document.sourceURL,
            externalID: document.id,
            highlights: [
                ReadwiseHighlight(id: 1, text: "Joined highlight.")
            ]
        )
        let tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoReaderJoinFallbackTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempVault) }

        _ = try SourceNoteSyncEngine().syncReaderDocuments(
            [document],
            matchedReadwiseBooks: [document.id: matchedBook],
            vaultURL: tempVault,
            sourceDirectory: "Sources",
            dryRun: false,
            syncedAt: ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        )
        let note = try String(
            contentsOf: tempVault.appendingPathComponent("Sources/Reader Without URL.md"),
            encoding: .utf8
        )

        #expect(note.contains("reader_url: \"https://read.readwise.io/read/01readerwithouturl\""))
        #expect(note.contains("readwise_url: \"https://read.readwise.io/read/01readerwithouturl\""))
        #expect(note.contains("readwise_bookreview_url: \"https://readwise.io/bookreview/988\""))
        #expect(note.contains("> Joined highlight."))
    }

    @Test func incrementalSyncDoesNotDeleteReaderNoteWhenReaderReturnsNoDocuments() async throws {
        let document = try loadReaderFixtureDocuments()[0]
        let tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoReaderNoDeleteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempVault) }

        let capturesURL = tempVault.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: capturesURL, withIntermediateDirectories: true)
        let noteURL = capturesURL.appendingPathComponent("Long Reader Article.md")
        try SourceNoteRenderer.renderNewNote(
            for: document,
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            createdAt: ISO8601DateFormatter.noto.date(from: "2026-04-20T00:00:00Z")!,
            capturedAt: ISO8601DateFormatter.noto.date(from: "2026-04-20T00:00:00Z")!
        ).write(to: noteURL, atomically: true, encoding: .utf8)

        let client = MockReadwiseSyncClient(
            readerDocuments: [],
            incrementalReadwiseBooks: [],
            exportBooksByID: [:]
        )

        _ = try await SourceLibrarySyncEngine(client: client).syncIncrementally(
            vaultURL: tempVault,
            syncedAt: ISO8601DateFormatter.noto.date(from: "2026-04-22T12:00:00Z")!
        )

        #expect(FileManager.default.fileExists(atPath: noteURL.path))
    }

    @Test func syncRecoversWhenSourceMapPathIsStale() throws {
        let documents = try loadReaderFixtureDocuments()
        let document = documents[0]
        let tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoStaleMapSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempVault) }

        let capturesURL = tempVault.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: capturesURL, withIntermediateDirectories: true)
        let existingNoteURL = capturesURL.appendingPathComponent("Existing Reader Note.md")
        let capturedAt = ISO8601DateFormatter.noto.date(from: "2026-04-21T00:00:00Z")!
        let existingMarkdown = SourceNoteRenderer.renderNewNote(
            for: document,
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            createdAt: capturedAt,
            capturedAt: capturedAt
        )
        try existingMarkdown.write(to: existingNoteURL, atomically: true, encoding: .utf8)
        try SyncStateStore.save(
            ReadwiseSyncState(
                lastSuccessfulReaderSyncAt: "2026-04-21T00:00:00Z",
                sources: [
                    document.canonicalKey: SourceMapping(
                        noteID: "33333333-3333-3333-3333-333333333333",
                        relativePath: "Captures/Missing Note.md",
                        generatedBlockHash: "abc123",
                        readerDocumentID: document.id,
                        updatedAt: "2026-04-21T00:00:00Z"
                    )
                ]
            ),
            to: tempVault
        )

        let result = try SourceNoteSyncEngine().syncReaderDocuments(
            documents,
            vaultURL: tempVault,
            dryRun: false,
            syncedAt: ISO8601DateFormatter.noto.date(from: "2026-04-22T00:00:00Z")!
        )

        #expect(result.created == 0)
        #expect(result.updated == 1)
        let captureFiles = try FileManager.default.contentsOfDirectory(at: capturesURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
        #expect(captureFiles.count == 1)

        let state = try SyncStateStore.load(from: tempVault)
        #expect(state.sources[document.canonicalKey]?.relativePath == "Captures/Existing Reader Note.md")
    }

    @Test func incrementalSyncUsesSavedTimestampsAndJoinsKnownReaderHighlights() async throws {
        let documents = try loadReaderFixtureDocuments()
        let document = documents[0]
        let tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoIncrementalSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempVault) }

        let existingReaderNote = SourceNoteRenderer.renderNewNote(
            for: document,
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            createdAt: ISO8601DateFormatter.noto.date(from: "2026-04-20T00:00:00Z")!,
            capturedAt: ISO8601DateFormatter.noto.date(from: "2026-04-20T00:00:00Z")!
        ) + "\nManual note outside generated block.\n"
        let capturesURL = tempVault.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: capturesURL, withIntermediateDirectories: true)
        try existingReaderNote.write(
            to: capturesURL.appendingPathComponent("Long Reader Article.md"),
            atomically: true,
            encoding: .utf8
        )
        try SyncStateStore.save(
            ReadwiseSyncState(
                lastSuccessfulSyncAt: "2026-04-21T00:00:00Z",
                lastSuccessfulReaderSyncAt: "2026-04-20T00:00:00Z",
                sources: [
                    document.canonicalKey: SourceMapping(
                        noteID: "44444444-4444-4444-4444-444444444444",
                        relativePath: "Captures/Long Reader Article.md",
                        generatedBlockHash: "hash",
                        readwiseUserBookID: 987,
                        readerDocumentID: document.id,
                        updatedAt: "2026-04-20T00:00:00Z"
                    )
                ]
            ),
            to: tempVault
        )

        let joinedBook = ReadwiseBook(
            userBookID: 987,
            title: document.title,
            readableTitle: document.title,
            author: document.author,
            source: "reader",
            category: "articles",
            readwiseURL: "https://readwise.io/bookreview/987",
            sourceURL: document.sourceURL,
            externalID: document.id,
            highlights: [ReadwiseHighlight(id: 111, text: "Joined during incremental sync.")]
        )
        let readwiseOnlyBook = ReadwiseBook(
            userBookID: 555,
            title: "Kindle Book",
            readableTitle: "Kindle Book",
            author: "Reader",
            source: "kindle",
            category: "books",
            readwiseURL: "https://readwise.io/bookreview/555",
            sourceURL: "https://example.com/kindle-book",
            highlights: [ReadwiseHighlight(id: 222, text: "Kindle highlight")]
        )

        let client = MockReadwiseSyncClient(
            readerDocuments: documents,
            incrementalReadwiseBooks: [readwiseOnlyBook],
            exportBooksByID: [987: joinedBook]
        )
        let syncedAt = ISO8601DateFormatter.noto.date(from: "2026-04-22T12:00:00Z")!

        let result = try await SourceLibrarySyncEngine(client: client).syncIncrementally(
            vaultURL: tempVault,
            syncedAt: syncedAt
        )

        let requests = await client.requests
        #expect(requests == [
            .reader(updatedAfter: "2026-04-20T00:00:00Z"),
            .export(updatedAfter: "2026-04-21T00:00:00Z", ids: nil),
            .export(updatedAfter: nil, ids: [987])
        ])
        #expect(result.reader.created == 0)
        #expect(result.reader.updated == 1)
        #expect(result.readwise.created == 1)
        #expect(result.readwise.updated == 0)

        let updatedReaderNote = try String(
            contentsOf: capturesURL.appendingPathComponent("Long Reader Article.md"),
            encoding: .utf8
        )
        #expect(updatedReaderNote.contains("Manual note outside generated block."))
        #expect(updatedReaderNote.contains("> Joined during incremental sync."))

        let readwiseOnlyNote = try String(
            contentsOf: capturesURL.appendingPathComponent("Kindle Book.md"),
            encoding: .utf8
        )
        #expect(readwiseOnlyNote.contains("canonical_key: \"readwise-book:555\""))
        #expect(readwiseOnlyNote.contains("> Kindle highlight"))

        let state = try SyncStateStore.load(from: tempVault)
        #expect(state.lastSuccessfulReaderSyncAt == "2026-04-22T12:00:00Z")
        #expect(state.lastSuccessfulSyncAt == "2026-04-22T12:00:00Z")
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

    @Test func saveDocumentRequestEncodesOnlyURLWhenOptionalFieldsAreNil() throws {
        let request = SaveDocumentRequest(url: "https://example.com/article")
        let data = try JSONEncoder.readwise.encode(request)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["url"] as? String == "https://example.com/article")
        #expect(object.keys.sorted() == ["url"])
    }

    @Test func saveDocumentRequestEncodesAllFieldsWithSnakeCaseKeys() throws {
        let request = SaveDocumentRequest(
            url: "https://example.com/article",
            title: "An Article",
            author: "Someone",
            tags: ["ai", "economics"],
            location: "new",
            category: "article",
            summary: "Short summary.",
            notes: "My thoughts.",
            publishedDate: "2026-04-21T00:00:00+00:00",
            imageURL: "https://example.com/cover.png"
        )
        let data = try JSONEncoder.readwise.encode(request)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["url"] as? String == "https://example.com/article")
        #expect(object["title"] as? String == "An Article")
        #expect(object["author"] as? String == "Someone")
        #expect(object["tags"] as? [String] == ["ai", "economics"])
        #expect(object["location"] as? String == "new")
        #expect(object["category"] as? String == "article")
        #expect(object["summary"] as? String == "Short summary.")
        #expect(object["notes"] as? String == "My thoughts.")
        #expect(object["published_date"] as? String == "2026-04-21T00:00:00+00:00")
        #expect(object["image_url"] as? String == "https://example.com/cover.png")
    }

    @Test func saveDocumentResponseDecodes() throws {
        let json = #"""
        {"id":"0000ffff2222eeee3333dddd4444","url":"https://read.readwise.io/new/read/0000ffff2222eeee3333dddd4444"}
        """#.data(using: .utf8)!

        let response = try JSONDecoder.readwise.decode(SaveDocumentResponse.self, from: json)

        #expect(response.id == "0000ffff2222eeee3333dddd4444")
        #expect(response.url == "https://read.readwise.io/new/read/0000ffff2222eeee3333dddd4444")
    }
}

private actor MockReadwiseSyncClient: ReadwiseSyncClient {
    enum Request: Equatable {
        case reader(updatedAfter: String?)
        case export(updatedAfter: String?, ids: [Int]?)
    }

    private(set) var requests: [Request] = []
    let readerDocuments: [ReaderDocument]
    let incrementalReadwiseBooks: [ReadwiseBook]
    let exportBooksByID: [Int: ReadwiseBook]

    init(
        readerDocuments: [ReaderDocument],
        incrementalReadwiseBooks: [ReadwiseBook],
        exportBooksByID: [Int: ReadwiseBook]
    ) {
        self.readerDocuments = readerDocuments
        self.incrementalReadwiseBooks = incrementalReadwiseBooks
        self.exportBooksByID = exportBooksByID
    }

    func fetchExport(
        updatedAfter: String?,
        includeDeleted: Bool,
        ids: [Int]?,
        limit: Int?
    ) async throws -> [ReadwiseBook] {
        requests.append(.export(updatedAfter: updatedAfter, ids: ids?.sorted()))
        let books: [ReadwiseBook]
        if let ids {
            books = ids.compactMap { exportBooksByID[$0] }
        } else {
            books = incrementalReadwiseBooks
        }
        if let limit {
            return Array(books.prefix(limit))
        }
        return books
    }

    func fetchReaderDocuments(
        id: String?,
        updatedAfter: String?,
        location: String?,
        category: String?,
        tags: [String],
        limit: Int?
    ) async throws -> [ReaderDocument] {
        requests.append(.reader(updatedAfter: updatedAfter))
        let filtered = readerDocuments
            .filter { id == nil || $0.id == id }
            .filter { tags.isEmpty || $0.matchesAllTags(tags) }
        if let limit {
            return Array(filtered.prefix(limit))
        }
        return filtered
    }

    func saveReaderDocument(_ request: SaveDocumentRequest) async throws -> SaveOutcome {
        SaveOutcome(
            status: .created,
            response: SaveDocumentResponse(id: "mock", url: "https://read.readwise.io/new/read/mock")
        )
    }

    func validateToken() async throws {}
}
