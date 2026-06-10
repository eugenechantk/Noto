import Foundation
import Testing
@testable import NotoSearch

/// Test case index
/// 1. testTopKMatchesNaiveCosine — Accelerate scan returns exactly the naive-cosine top-k order (SC4)
/// 2. testCacheReloadsWhenStoreChanges — generation bump invalidates the cached matrix (SC4)
/// 3. testEmptyIndexReturnsNoHits — fresh store, no vectors (SC4)
/// 4. testMissingDatabaseReturnsNoHits — no semantic.sqlite at all (SC4)
/// 5. testDimensionMismatchThrows — query dims must match index dims (SC4)
/// 6. testMinScoreFiltersTail — low-similarity hits are dropped (SC4)
struct SemanticSearcherTests {
    private func seededVectors(count: Int, dims: Int) -> [[Float]] {
        (0..<count).map { FakeEmbedder.vector(for: "vector-\($0)", dimensions: dims) }
    }

    private func populate(_ store: SemanticIndexStore, vectors: [[Float]]) throws -> [UUID] {
        var chunkIDs: [UUID] = []
        for (index, vector) in vectors.enumerated() {
            let noteID = UUID()
            let chunk = SemanticChunk(
                id: UUID(),
                noteID: noteID,
                heading: "H\(index)",
                lineStart: 1,
                lineEnd: 2,
                embeddedText: "text \(index)",
                snippetText: "snippet \(index)",
                contentHash: "hash-\(index)"
            )
            chunkIDs.append(chunk.id)
            try store.replaceNote(
                noteID: noteID,
                relativePath: "N\(index).md",
                noteTitle: "Note \(index)",
                noteContentHash: "nh-\(index)",
                modelVersion: "v1",
                chunks: [(chunk, vector)]
            )
        }
        return chunkIDs
    }

    @Test func testTopKMatchesNaiveCosine() throws {
        let dir = try makeTempDirectory("SearcherTopK")
        defer { removeDirectory(dir) }
        let dims = 16
        let vectors = seededVectors(count: 200, dims: dims)
        let store = try SemanticIndexStore(indexDirectory: dir)
        let chunkIDs = try populate(store, vectors: vectors)

        let query = FakeEmbedder.vector(for: "the-query", dimensions: dims)
        let naive = vectors.enumerated()
            .map { (index: $0.offset, score: zip($0.element, query).reduce(Float(0)) { $0 + $1.0 * $1.1 }) }
            .sorted { $0.score > $1.score }
            .prefix(10)

        let searcher = SemanticSearcher(indexDirectory: dir)
        let hits = try searcher.search(queryVector: query, limit: 10, minScore: -2)

        #expect(hits.count == 10)
        #expect(hits.map(\.chunkID) == naive.map { chunkIDs[$0.index] })
        for (hit, expected) in zip(hits, naive) {
            #expect(abs(hit.score - expected.score) < 1e-5)
        }
    }

    @Test func testCacheReloadsWhenStoreChanges() throws {
        let dir = try makeTempDirectory("SearcherCache")
        defer { removeDirectory(dir) }
        let dims = 8
        let store = try SemanticIndexStore(indexDirectory: dir)
        _ = try populate(store, vectors: seededVectors(count: 3, dims: dims))

        let searcher = SemanticSearcher(indexDirectory: dir)
        let query = FakeEmbedder.vector(for: "q", dimensions: dims)
        let before = try searcher.search(queryVector: query, limit: 10, minScore: -2)
        #expect(before.count == 3)

        // Mutate the store after the searcher has cached the matrix.
        let noteID = UUID()
        let chunk = SemanticChunk(
            id: UUID(), noteID: noteID, heading: "new", lineStart: 1, lineEnd: 1,
            embeddedText: "new", snippetText: "new", contentHash: "new-hash"
        )
        try store.replaceNote(
            noteID: noteID, relativePath: "New.md", noteTitle: "New",
            noteContentHash: "nh-new", modelVersion: "v1",
            chunks: [(chunk, FakeEmbedder.vector(for: "new-vector", dimensions: dims))]
        )

        let after = try searcher.search(queryVector: query, limit: 10, minScore: -2)
        #expect(after.count == 4)
    }

    @Test func testEmptyIndexReturnsNoHits() throws {
        let dir = try makeTempDirectory("SearcherEmpty")
        defer { removeDirectory(dir) }
        _ = try SemanticIndexStore(indexDirectory: dir)

        let searcher = SemanticSearcher(indexDirectory: dir)
        let hits = try searcher.search(queryVector: [1, 0, 0, 0], limit: 5)
        #expect(hits.isEmpty)
    }

    @Test func testMissingDatabaseReturnsNoHits() throws {
        let dir = try makeTempDirectory("SearcherMissing")
        defer { removeDirectory(dir) }
        let searcher = SemanticSearcher(indexDirectory: dir)
        #expect(try searcher.search(queryVector: [1, 0], limit: 5).isEmpty)
    }

    @Test func testDimensionMismatchThrows() throws {
        let dir = try makeTempDirectory("SearcherDims")
        defer { removeDirectory(dir) }
        let store = try SemanticIndexStore(indexDirectory: dir)
        _ = try populate(store, vectors: seededVectors(count: 2, dims: 8))

        let searcher = SemanticSearcher(indexDirectory: dir)
        #expect(throws: (any Error).self) {
            try searcher.search(queryVector: [1, 0, 0], limit: 5)
        }
    }

    @Test func testMinScoreFiltersTail() throws {
        let dir = try makeTempDirectory("SearcherMinScore")
        defer { removeDirectory(dir) }
        let store = try SemanticIndexStore(indexDirectory: dir)
        // One aligned vector, one orthogonal.
        let aligned: [Float] = FakeEmbedder.normalized([1, 0, 0, 0])
        let orthogonal: [Float] = FakeEmbedder.normalized([0, 1, 0, 0])
        _ = try populate(store, vectors: [aligned, orthogonal])

        let searcher = SemanticSearcher(indexDirectory: dir)
        let hits = try searcher.search(queryVector: [1, 0, 0, 0], limit: 5, minScore: 0.5)
        #expect(hits.count == 1)
        #expect(hits[0].score > 0.99)
    }
}
