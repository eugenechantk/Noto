import Foundation
import Testing
@testable import NotoSearch

/// Test case index (bug 019)
/// 1. testPartialTermMatchesSurfaceViaORFallback — a note matching only 2 of 4 query terms is returned
/// 2. testFullMatchesStillRankAbovePartialMatches — BM25 keeps all-terms notes on top
/// 3. testQuotedPhraseQueriesStayStrict — quotes disable the OR fallback (precision preserved)
/// 4. testSingleTermQueryUnchanged — no OR variant for one token
/// 5. testDateFilterAppliesToFallbackResults — the OR pass respects date bounds
struct KeywordORFallbackTests {
    private func makeIndexedVault() throws -> (vault: URL, indexDir: URL, store: SearchIndexStore) {
        let vault = try makeTempDirectory("ORFallbackVault")
        let indexDir = try makeTempDirectory("ORFallbackIndex")
        _ = try writeMarkdown(
            "# Gadget Capture\n\n你的 vibe coding 好搭子，新产品发布。",
            to: "Gadget.md", in: vault
        )
        _ = try writeMarkdown(
            "# TV Setup\n\nThe new remote control pairs over bluetooth.",
            to: "TV Setup.md", in: vault
        )
        _ = try writeMarkdown(
            "# Full Match\n\nUsing vibe code sessions to build a remote control simulator app.",
            to: "Full Match.md", in: vault
        )
        _ = try writeMarkdown(
            "# Unrelated\n\nGrocery list and weekend errands.",
            to: "Unrelated.md", in: vault
        )
        _ = try MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDir).refreshChangedFiles()
        return (vault, indexDir, try SearchIndexStore(indexDirectory: indexDir))
    }

    @Test func testPartialTermMatchesSurfaceViaORFallback() throws {
        let (vault, indexDir, store) = try makeIndexedVault()
        defer { removeDirectory(vault); removeDirectory(indexDir) }

        let results = try store.search(query: "vibe code remote control", vaultURL: vault, limit: 20)
        let titles = Set(results.map(\.title))
        #expect(titles.contains("Full Match"))
        #expect(titles.contains("Gadget Capture"))   // matches only vibe+code
        #expect(titles.contains("TV Setup"))         // matches only remote+control
        #expect(!titles.contains("Unrelated"))
    }

    @Test func testFullMatchesStillRankAbovePartialMatches() throws {
        let (vault, indexDir, store) = try makeIndexedVault()
        defer { removeDirectory(vault); removeDirectory(indexDir) }

        let results = try store.search(query: "vibe code remote control", vaultURL: vault, limit: 20)
        let firstTitles = results.prefix(2).map(\.title)
        #expect(firstTitles.contains("Full Match"))
        let fullIndex = results.firstIndex { $0.title == "Full Match" } ?? .max
        let partialIndex = results.firstIndex { $0.title == "Gadget Capture" } ?? .max
        #expect(fullIndex < partialIndex)
    }

    @Test func testQuotedPhraseQueriesStayStrict() throws {
        let (vault, indexDir, store) = try makeIndexedVault()
        defer { removeDirectory(vault); removeDirectory(indexDir) }

        let results = try store.search(query: "\"remote control\" vibe", vaultURL: vault, limit: 20)
        // Only Full Match contains both the exact phrase and "vibe"; the
        // fallback must NOT loosen quoted queries.
        #expect(results.map(\.title).allSatisfy { $0 == "Full Match" })
    }

    @Test func testSingleTermQueryUnchanged() {
        #expect(MarkdownSearchEngine.orFTSQuery(for: "vibe") == nil)
        #expect(MarkdownSearchEngine.orFTSQuery(for: "  ") == nil)
        #expect(MarkdownSearchEngine.orFTSQuery(for: "vibe code") == "vibe* OR code*")
    }

    @Test func testDateFilterAppliesToFallbackResults() throws {
        let (vault, indexDir, store) = try makeIndexedVault()
        defer { removeDirectory(vault); removeDirectory(indexDir) }

        let futureOnly = try store.search(
            query: "vibe code remote control", vaultURL: vault, limit: 20,
            dateFilter: SearchDateFilter(updatedAfter: Date().addingTimeInterval(3600))
        )
        #expect(futureOnly.isEmpty)
    }
}
