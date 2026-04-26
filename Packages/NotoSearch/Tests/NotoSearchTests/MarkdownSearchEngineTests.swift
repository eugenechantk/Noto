import Foundation
import Testing
import NotoSearch

@Suite("MarkdownSearchEngine")
struct MarkdownSearchEngineTests {
    @Test("Search finds words that appear only in note body")
    func searchFindsBodyOnlyWords() throws {
        let (vault, indexDirectory, engine) = try fixtureEngine()
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let results = try engine.search("orchard velocity")
        #expect(results.first?.title == "Body Only Match")
    }

    @Test("Title scope searches note titles only")
    func titleScopeSearchesNoteTitlesOnly() throws {
        let (vault, indexDirectory, engine) = try fixtureEngine()
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let titleResults = try engine.search("Launch", scope: .title)
        let bodyOnlyResults = try engine.search("orchard velocity", scope: .title)
        let headingOnlyResults = try engine.search("Monetization", scope: .title)
        let pathOnlyResults = try engine.search("Projects", scope: .title)

        #expect(titleResults.first?.kind == .note)
        #expect(titleResults.first?.title == "Launch Notes")
        #expect(bodyOnlyResults.isEmpty)
        #expect(headingOnlyResults.isEmpty)
        #expect(pathOnlyResults.isEmpty)
    }

    @Test("Title and content scope includes body and section matches")
    func titleAndContentScopeIncludesBodyAndSectionMatches() throws {
        let (vault, indexDirectory, engine) = try fixtureEngine()
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let bodyResults = try engine.search("orchard velocity", scope: .titleAndContent)
        let sectionResults = try engine.search("Monetization", scope: .titleAndContent)

        #expect(bodyResults.first?.title == "Body Only Match")
        #expect(sectionResults.first?.kind == .section)
        #expect(sectionResults.first?.title == "Launch Notes")
        #expect(sectionResults.first?.breadcrumb == "Projects/Launch Notes.md/## Monetization")
    }

    @Test("Search finds imported capture content")
    func searchFindsCaptureContent() throws {
        let (vault, indexDirectory, engine) = try fixtureEngine()
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let results = try engine.search("retention loops pricing")
        #expect(results.isEmpty)

        let phraseResults = try engine.search("retention loops")
        #expect(phraseResults.contains { $0.fileURL.lastPathComponent == "Reader Capture.md" })
    }

    @Test("Multi-word search requires an exact phrase match")
    func multiWordSearchRequiresExactPhraseMatch() throws {
        let (vault, indexDirectory, engine) = try fixtureEngine()
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let separatedWords = try engine.search("pricing churn")
        let adjacentWords = try engine.search("annual conversion")

        #expect(separatedWords.isEmpty)
        #expect(adjacentWords.contains { $0.kind == .section && $0.title == "Launch Notes" })
    }

    @Test("Heading matches rank sections highly")
    func headingMatchesRankSectionsHighly() throws {
        let (vault, indexDirectory, engine) = try fixtureEngine()
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let results = try engine.search("Monetization")
        #expect(results.first?.kind == .section)
        #expect(results.first?.title == "Launch Notes")
    }

    @Test("Section result uses note title and file path heading breadcrumb")
    func sectionResultUsesNoteTitleAndFilePathHeadingBreadcrumb() throws {
        let vault = try makeTempDirectory("NotoSearchFixtureVault")
        let indexDirectory = try makeTempDirectory("NotoSearchIndex")
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }
        _ = try writeMarkdown(
            """
            # 01

            ## first heading

            ### first subheading

            Text with matching word in context.
            """,
            to: "meeting_notes/01.md",
            in: vault
        )

        let indexer = MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDirectory)
        _ = try indexer.rebuild()
        let engine = MarkdownSearchEngine(store: try indexer.openStore(), vaultURL: vault)
        let sectionResult = try engine.search("matching", scope: .titleAndContent).first { $0.kind == .section }

        #expect(sectionResult?.title == "01")
        #expect(sectionResult?.breadcrumb == "meeting_notes/01.md/### first subheading")
    }

    @Test("Exact title matches rank above body-only matches")
    func titleMatchesRankAboveBodyOnlyMatches() throws {
        let (vault, indexDirectory, engine) = try fixtureEngine()
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let results = try engine.search("Launch Notes")
        #expect(results.first?.kind == .note)
        #expect(results.first?.title == "Launch Notes")
    }

    @Test("Query sanitizer supports prefix, phrase, punctuation, and unbalanced quotes")
    func querySanitizerSupportsExpectedInput() throws {
        #expect(MarkdownSearchEngine.ftsQuery(for: "orch") == "orch*")
        #expect(MarkdownSearchEngine.ftsQuery(for: "orchard velocity") == "\"orchard velocity\"")
        #expect(MarkdownSearchEngine.ftsQuery(for: "\"orchard velocity\"") == "\"orchard velocity\"")
        #expect(MarkdownSearchEngine.ftsQuery(for: "pricing/churn?") == "pricingchurn*")
        #expect(MarkdownSearchEngine.ftsQuery(for: "\"pricing churn") == "\"pricing churn\"")
    }

    @Test("Phrase search works")
    func phraseSearchWorks() throws {
        let (vault, indexDirectory, engine) = try fixtureEngine()
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let results = try engine.search("\"orchard velocity\"")
        #expect(results.first?.title == "Body Only Match")
    }

    @Test("Recently updated note ranks above older equivalent note match")
    func recentlyUpdatedNoteRanksAboveOlderEquivalentNoteMatch() throws {
        let vault = try makeTempDirectory("NotoSearchRecencyVault")
        let indexDirectory = try makeTempDirectory("NotoSearchIndex")
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let now = Date()
        let oldDate = now.addingTimeInterval(-365 * 86_400)
        let recentDate = now.addingTimeInterval(-60)
        let oldDocument = makeSearchDocument(
            relativePath: "A Old.md",
            title: "A Old",
            plainText: "shared recency phrase"
        )
        let recentDocument = makeSearchDocument(
            relativePath: "Z Recent.md",
            title: "Z Recent",
            plainText: "shared recency phrase"
        )
        let store = try SearchIndexStore(indexDirectory: indexDirectory)
        _ = try store.rebuild(documents: [
            (oldDocument, oldDate),
            (recentDocument, recentDate),
        ])
        let engine = MarkdownSearchEngine(store: store, vaultURL: vault)

        let noteResults = try engine.search("shared recency phrase", limit: 2).filter { $0.kind == .note }

        #expect(noteResults.map(\.title) == ["Z Recent", "A Old"])
    }

    @Test("Recently updated section ranks above older equivalent section match")
    func recentlyUpdatedSectionRanksAboveOlderEquivalentSectionMatch() throws {
        let vault = try makeTempDirectory("NotoSearchRecencyVault")
        let indexDirectory = try makeTempDirectory("NotoSearchIndex")
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let now = Date()
        let oldDate = now.addingTimeInterval(-365 * 86_400)
        let recentDate = now.addingTimeInterval(-60)
        let oldDocument = makeSearchDocument(
            relativePath: "A Old.md",
            title: "A Old",
            plainText: "unrelated note text",
            sectionText: "shared section phrase"
        )
        let recentDocument = makeSearchDocument(
            relativePath: "Z Recent.md",
            title: "Z Recent",
            plainText: "unrelated note text",
            sectionText: "shared section phrase"
        )
        let store = try SearchIndexStore(indexDirectory: indexDirectory)
        _ = try store.rebuild(documents: [
            (oldDocument, oldDate),
            (recentDocument, recentDate),
        ])
        let engine = MarkdownSearchEngine(store: store, vaultURL: vault)

        let sectionResults = try engine.search("shared section phrase", limit: 2).filter { $0.kind == .section }

        #expect(sectionResults.map(\.title) == ["Z Recent", "A Old"])
    }

    private func fixtureEngine() throws -> (URL, URL, MarkdownSearchEngine) {
        let vault = try makeFixtureVault()
        let indexDirectory = try makeTempDirectory("NotoSearchIndex")
        let indexer = MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDirectory)
        _ = try indexer.rebuild()
        return (vault, indexDirectory, MarkdownSearchEngine(store: try indexer.openStore(), vaultURL: vault))
    }

    private func makeSearchDocument(
        relativePath: String,
        title: String,
        plainText: String,
        sectionText: String? = nil
    ) -> SearchDocument {
        let noteID = UUID()
        let sections: [SearchSection]
        if let sectionText {
            sections = [
                SearchSection(
                    id: UUID(),
                    noteID: noteID,
                    heading: "Details",
                    level: 2,
                    lineStart: 3,
                    lineEnd: 5,
                    sectionIndex: 0,
                    contentHash: UUID().uuidString,
                    plainText: sectionText
                )
            ]
        } else {
            sections = []
        }

        return SearchDocument(
            id: noteID,
            relativePath: relativePath,
            title: title,
            folderPath: "",
            contentHash: UUID().uuidString,
            plainText: plainText,
            sections: sections
        )
    }
}
