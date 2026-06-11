import Foundation
import Testing
@testable import NotoSearch

/// Test case index (feature: search-folder-filter)
/// 1. testNormalizationAndMatching — prefix normalization ("/Captures/" → "Captures") and segment-safe, case-insensitive path matching (SC3)
/// 2. testKeywordSearchFiltersByFolder — FTS legs return only notes under the folder; subfolders in, root + prefix-sibling folders out (SC1)
/// 3. testHybridRunFiltersBothLegs — semantic-only hit inside the folder survives, semantic-only hit outside is dropped (SC2)
/// 4. testNoFolderFilterBehaviorUnchanged — nil folder returns vault-wide results (SC5)
struct SearchFolderFilterTests {
    /// Topic embedder à la HybridNoteSearchTests: "alpha" and the decoy topic
    /// "mountain hiking" share a vector, so hiking notes are semantic-only
    /// matches for an "alpha" query.
    private final class TopicEmbedder: TextEmbedding, @unchecked Sendable {
        let modelVersion = "topic-v1"
        let dimensions = 4
        func embed(_ texts: [String]) throws -> [[Float]] {
            texts.map { text in
                let lowered = text.lowercased()
                if lowered.contains("alpha") || lowered.contains("mountain hiking") {
                    return [1, 0, 0, 0]
                }
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

        var embedQuery: (String) throws -> [Float]? {
            { [embedder] query in try embedder.embed([query]).first }
        }
    }

    private func makeFixture() throws -> Fixture {
        let vault = try makeTempDirectory("FolderFilterVault")
        let indexDir = try makeTempDirectory("FolderFilterIndex")
        for (path, body) in [
            ("Captures/Sprint Review.md", "# Sprint Review\n\nThe alpha milestone shipped this week."),
            ("Captures/Sub/Nested.md", "# Nested\n\nAnother alpha note nested deeper."),
            ("Captures/Weekend Plans.md", "# Weekend Plans\n\nA long mountain hiking trip with trail snacks."),
            ("Root Alpha.md", "# Root Alpha\n\nAlpha note at the vault root."),
            ("Cap/Decoy.md", "# Decoy\n\nAlpha note in a folder whose name is a prefix of Captures."),
            ("Elsewhere/Hiking.md", "# Hiking\n\nA mountain hiking memoir outside the folder."),
        ] {
            _ = try writeMarkdown(body, to: path, in: vault)
        }
        _ = try MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDir).refreshChangedFiles()
        let embedder = TopicEmbedder()
        _ = try SemanticIndexer(vaultURL: vault, embedding: embedder, indexDirectory: indexDir, describer: nil, imageFetcher: nil)
            .refreshFromSearchIndex()
        return Fixture(vault: vault, indexDir: indexDir, embedder: embedder)
    }

    @Test func testNormalizationAndMatching() {
        #expect(SearchFolderFilter.normalizedPrefix(" /Captures/ ") == "Captures")
        #expect(SearchFolderFilter.normalizedPrefix("Projects/Alpha") == "Projects/Alpha")
        #expect(SearchFolderFilter.normalizedPrefix("   ") == nil)
        #expect(SearchFolderFilter.normalizedPrefix(nil) == nil)

        #expect(SearchFolderFilter.matches(relativePath: "Captures/x.md", normalizedPrefix: "Captures"))
        #expect(SearchFolderFilter.matches(relativePath: "Captures/Sub/x.md", normalizedPrefix: "Captures"))
        #expect(SearchFolderFilter.matches(relativePath: "captures/x.md", normalizedPrefix: "Captures"))
        // Segment-safe: a folder-name prefix is not a match.
        #expect(!SearchFolderFilter.matches(relativePath: "Captures/x.md", normalizedPrefix: "Cap"))
        // A file with the folder's name is not inside the folder.
        #expect(!SearchFolderFilter.matches(relativePath: "Captures.md", normalizedPrefix: "Captures"))
        #expect(!SearchFolderFilter.matches(relativePath: "Root.md", normalizedPrefix: "Captures"))
    }

    @Test func testKeywordSearchFiltersByFolder() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let store = try SearchIndexStore(indexDirectory: fixture.indexDir)

        let filtered = try store.search(
            query: "alpha", vaultURL: fixture.vault, limit: 20, folderPrefix: "Captures"
        )
        let paths = Set(filtered.map { $0.fileURL.lastPathComponent })
        #expect(paths == ["Sprint Review.md", "Nested.md"])

        // Unnormalized input behaves identically.
        let slashed = try store.search(
            query: "alpha", vaultURL: fixture.vault, limit: 20, folderPrefix: "/Captures/"
        )
        #expect(Set(slashed.map { $0.fileURL.lastPathComponent }) == paths)
    }

    @Test func testHybridRunFiltersBothLegs() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let results = try HybridNoteSearch.run(
            HybridNoteSearch.Request(query: "alpha", folderPrefix: "Captures"),
            vaultURL: fixture.vault,
            indexDirectory: fixture.indexDir,
            embedQuery: fixture.embedQuery
        )

        let titles = Set(results.map(\.title))
        #expect(titles.contains("Sprint Review"))
        #expect(titles.contains("Weekend Plans"))   // semantic-only, inside the folder
        #expect(!titles.contains("Hiking"))         // semantic-only, outside the folder
        #expect(!titles.contains("Root Alpha"))
        #expect(!titles.contains("Decoy"))
    }

    @Test func testNoFolderFilterBehaviorUnchanged() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let results = try HybridNoteSearch.run(
            HybridNoteSearch.Request(query: "alpha"),
            vaultURL: fixture.vault,
            indexDirectory: fixture.indexDir,
            embedQuery: fixture.embedQuery
        )

        let titles = Set(results.map(\.title))
        #expect(titles.contains("Root Alpha"))
        #expect(titles.contains("Sprint Review"))
        #expect(titles.contains("Decoy"))
    }
}
