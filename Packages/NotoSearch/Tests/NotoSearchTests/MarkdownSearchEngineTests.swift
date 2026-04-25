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

    @Test("Search finds imported capture content")
    func searchFindsCaptureContent() throws {
        let (vault, indexDirectory, engine) = try fixtureEngine()
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let results = try engine.search("retention loops pricing")
        #expect(results.contains { $0.fileURL.lastPathComponent == "Reader Capture.md" })
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
        #expect(results.first?.title == "Monetization")
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
        #expect(MarkdownSearchEngine.ftsQuery(for: "\"orchard velocity\"") == "\"orchard velocity\"")
        #expect(MarkdownSearchEngine.ftsQuery(for: "pricing/churn?") == "pricingchurn*")
        #expect(MarkdownSearchEngine.ftsQuery(for: "\"pricing churn") == "pricing churn*")
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

    private func fixtureEngine() throws -> (URL, URL, MarkdownSearchEngine) {
        let vault = try makeFixtureVault()
        let indexDirectory = try makeTempDirectory("NotoSearchIndex")
        let indexer = MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDirectory)
        _ = try indexer.rebuild()
        return (vault, indexDirectory, MarkdownSearchEngine(store: try indexer.openStore(), vaultURL: vault))
    }
}
