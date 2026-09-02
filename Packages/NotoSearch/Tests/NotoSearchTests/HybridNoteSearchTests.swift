import Foundation
import Testing
@testable import NotoSearch

/// Test case index
/// 1. testExtractorParsesFrontmatterCreated — `created:` lands on SearchDocument.createdAt (SC10)
/// 2. testIndexStoresCreatedAtWithFileFallback — frontmatter wins, filesystem date fills the gap (SC10)
/// 3. testKeywordSearchHonorsDateFilters — created/updated bounds filter FTS results in SQL (SC10)
/// 4. testRunFusesKeywordAndSemanticLegs — hybrid one-shot returns both literal and meaning matches (SC11)
/// 5. testDateFilterAppliesToSemanticLeg — semantic-only hit outside the updated window is dropped (SC10, SC11)
/// 6. testCreatedFilterExcludesOldNote — frontmatter-created 2020 note fails createdAfter 2026 on both legs (SC10)
/// 7. testKeywordOnlyWhenEmbedderUnavailable — embedQuery nil → keyword results pass through (SC11)
struct HybridNoteSearchTests {
    /// Maps topic markers to fixed orthogonal vectors so semantic matches are
    /// fully deterministic: queries/chunks mentioning "alpha" (or the decoy
    /// topic "mountain hiking") share a vector; everything else is orthogonal.
    private final class TopicEmbedder: TextEmbedding, @unchecked Sendable {
        let modelVersion = "topic-v1"
        let dimensions = 4
        func embed(_ texts: [String]) throws -> [[Float]] {
            texts.map { text in
                let lowered = text.lowercased()
                if lowered.contains("alpha") || lowered.contains("mountain hiking") {
                    return [1, 0, 0, 0]
                }
                if lowered.contains("beta") { return [0, 1, 0, 0] }
                return [0, 0, 1, 0]
            }
        }
    }

    private struct Fixture {
        let vault: URL
        let indexDir: URL
        let embedder: TopicEmbedder

        func tearDown() {
            removeDirectory(vault)
            removeDirectory(indexDir)
        }
    }

    /// Three notes: a literal keyword match, a semantic-only match (no literal
    /// "alpha", but the embedder maps its topic to the alpha vector), and an
    /// old note (frontmatter created 2020) that also contains the keyword.
    private func makeFixture() throws -> Fixture {
        let vault = try makeTempDirectory("HybridVault")
        let indexDir = try makeTempDirectory("HybridIndex")
        _ = try writeMarkdown(
            "# Sprint Review\n\nThe alpha milestone shipped on schedule this week.",
            to: "Sprint Review.md", in: vault
        )
        _ = try writeMarkdown(
            "# Weekend Plans\n\nA long mountain hiking trip with early start and trail snacks.",
            to: "Weekend Plans.md", in: vault
        )
        _ = try writeMarkdown(
            """
            ---
            created: 2020-01-01T00:00:00Z
            ---
            # Legacy Alpha Archive

            Historic alpha launch retrospective from years ago.
            """,
            to: "Legacy.md", in: vault
        )
        _ = try MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDir).refreshChangedFiles()
        let embedder = TopicEmbedder()
        _ = try SemanticIndexer(vaultURL: vault, embedding: embedder, indexDirectory: indexDir)
            .refreshFromSearchIndex()
        return Fixture(vault: vault, indexDir: indexDir, embedder: embedder)
    }

    private func embedQuery(_ fixture: Fixture) -> (String) throws -> [Float]? {
        { query in try fixture.embedder.embed([query]).first }
    }

    @Test func testExtractorParsesFrontmatterCreated() throws {
        let vault = try makeTempDirectory("CreatedVault")
        defer { removeDirectory(vault) }
        let url = try writeMarkdown(
            "---\nid: 33333333-3333-4333-8333-333333333333\ncreated: 2026-02-03T10:00:00Z\n---\n# Note\n\nBody text.",
            to: "Note.md", in: vault
        )
        let document = try MarkdownSearchDocumentExtractor(vaultURL: vault).extract(fileURL: url)
        #expect(document.createdAt == SearchUtilities.iso8601.date(from: "2026-02-03T10:00:00Z"))
    }

    @Test func testIndexStoresCreatedAtWithFileFallback() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let catalog = try SearchIndexStore(indexDirectory: fixture.indexDir).noteCatalog()
        let byPath = Dictionary(uniqueKeysWithValues: catalog.map { ($0.relativePath, $0) })

        // Frontmatter wins for Legacy.md.
        #expect(byPath["Legacy.md"]?.createdAt == SearchUtilities.iso8601.date(from: "2020-01-01T00:00:00Z"))
        // Filesystem creation date (just now) fills the others.
        let sprintCreated = try #require(byPath["Sprint Review.md"]?.createdAt)
        #expect(abs(sprintCreated.timeIntervalSinceNow) < 120)
    }

    @Test func testKeywordSearchHonorsDateFilters() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let store = try SearchIndexStore(indexDirectory: fixture.indexDir)

        let unfiltered = try store.search(query: "alpha", vaultURL: fixture.vault, limit: 10)
        #expect(Set(unfiltered.map(\.title)) == ["Sprint Review", "Legacy Alpha Archive"])

        let recentOnly = try store.search(
            query: "alpha", vaultURL: fixture.vault, limit: 10,
            dateFilter: SearchDateFilter(createdAfter: SearchUtilities.iso8601.date(from: "2026-01-01T00:00:00Z"))
        )
        #expect(recentOnly.map(\.title).allSatisfy { $0 == "Sprint Review" })
        #expect(!recentOnly.isEmpty)

        let oldOnly = try store.search(
            query: "alpha", vaultURL: fixture.vault, limit: 10,
            dateFilter: SearchDateFilter(createdBefore: SearchUtilities.iso8601.date(from: "2021-01-01T00:00:00Z"))
        )
        #expect(oldOnly.map(\.title).allSatisfy { $0 == "Legacy Alpha Archive" })
        #expect(!oldOnly.isEmpty)

        let updatedFuture = try store.search(
            query: "alpha", vaultURL: fixture.vault, limit: 10,
            dateFilter: SearchDateFilter(updatedAfter: Date().addingTimeInterval(3600))
        )
        #expect(updatedFuture.isEmpty)
    }

    @Test func testRunFusesKeywordAndSemanticLegs() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let results = try HybridNoteSearch.run(
            HybridNoteSearch.Request(query: "alpha"),
            vaultURL: fixture.vault,
            indexDirectory: fixture.indexDir,
            embedQuery: embedQuery(fixture)
        )

        let titles = Set(results.map(\.title))
        #expect(titles.contains("Sprint Review"))      // keyword + semantic
        #expect(titles.contains("Weekend Plans"))      // semantic only — no literal "alpha"
        #expect(titles.contains("Legacy Alpha Archive"))
    }

    @Test func testDateFilterAppliesToSemanticLeg() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        // Backdate the semantic-only note: edit its content (a pure mtime
        // touch is deliberately ignored by the content-hash skip) and set the
        // modification date 10 days back, then re-index.
        let hikeURL = fixture.vault.appendingPathComponent("Weekend Plans.md")
        try "# Weekend Plans\n\nA long mountain hiking trip with early start, trail snacks, and maps."
            .write(to: hikeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-10 * 86_400)],
            ofItemAtPath: hikeURL.path
        )
        _ = try MarkdownSearchIndexer(vaultURL: fixture.vault, indexDirectory: fixture.indexDir).refreshChangedFiles()

        let results = try HybridNoteSearch.run(
            HybridNoteSearch.Request(
                query: "alpha",
                dateFilter: SearchDateFilter(updatedAfter: Date().addingTimeInterval(-5 * 86_400))
            ),
            vaultURL: fixture.vault,
            indexDirectory: fixture.indexDir,
            embedQuery: embedQuery(fixture)
        )

        let titles = Set(results.map(\.title))
        #expect(!titles.contains("Weekend Plans"))
        #expect(titles.contains("Sprint Review"))
    }

    @Test func testCreatedFilterExcludesOldNote() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let results = try HybridNoteSearch.run(
            HybridNoteSearch.Request(
                query: "alpha",
                dateFilter: SearchDateFilter(createdAfter: SearchUtilities.iso8601.date(from: "2026-01-01T00:00:00Z"))
            ),
            vaultURL: fixture.vault,
            indexDirectory: fixture.indexDir,
            embedQuery: embedQuery(fixture)
        )

        let titles = Set(results.map(\.title))
        #expect(!titles.contains("Legacy Alpha Archive"))
        #expect(titles.contains("Sprint Review"))
    }

    @Test func testKeywordOnlyWhenEmbedderUnavailable() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let results = try HybridNoteSearch.run(
            HybridNoteSearch.Request(query: "alpha"),
            vaultURL: fixture.vault,
            indexDirectory: fixture.indexDir,
            embedQuery: { _ in nil }
        )

        let titles = Set(results.map(\.title))
        #expect(titles.contains("Sprint Review"))
        #expect(!titles.contains("Weekend Plans"))   // semantic leg disabled
    }
}

/// Test case index
/// 1. relativeGapKeepsHitsNearTheBest — hits more than `gap` below the top score are dropped; nil gap is a no-op
/// 2. relativeGapOnEmptyIsEmpty — no hits → no hits
struct HybridRelativeGapTests {
    private func hit(_ score: Float) -> SemanticSearchHit {
        SemanticSearchHit(chunkID: UUID(), noteID: UUID(), relativePath: "n.md", noteTitle: "n", heading: "", snippet: "", lineStart: 0, score: score)
    }

    @Test func relativeGapKeepsHitsNearTheBest() {
        let hits = [hit(0.86), hit(0.82), hit(0.80), hit(0.72), hit(0.70)]
        #expect(HybridNoteSearch.applyRelativeGap(hits, gap: 0.12).map(\.score) == [0.86, 0.82, 0.80])
        #expect(HybridNoteSearch.applyRelativeGap(hits, gap: nil).count == 5)
    }

    @Test func relativeGapOnEmptyIsEmpty() {
        #expect(HybridNoteSearch.applyRelativeGap([], gap: 0.1).isEmpty)
    }

    /// 3. peakTestSeparatesFlatFromPeaked — measured granite distributions: gibberish (top−median ≈ 0.04) fails, real queries (≥ 0.11) pass; nil margin or < 4 scores always pass
    @Test func peakTestSeparatesFlatFromPeaked() {
        let gibberish: [Float] = [0.780, 0.749, 0.740, 0.733, 0.730, 0.725, 0.716]
        let granite: [Float] = [0.859, 0.816, 0.801, 0.724, 0.711, 0.706, 0.698]
        #expect(HybridNoteSearch.passesPeakTest(scores: gibberish, margin: 0.07) == false)
        #expect(HybridNoteSearch.passesPeakTest(scores: granite, margin: 0.07) == true)
        #expect(HybridNoteSearch.passesPeakTest(scores: gibberish, margin: nil) == true)
        #expect(HybridNoteSearch.passesPeakTest(scores: [0.78, 0.75, 0.74], margin: 0.07) == true)
    }
}
