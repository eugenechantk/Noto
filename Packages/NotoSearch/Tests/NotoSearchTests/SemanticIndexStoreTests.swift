import Foundation
import Testing
@testable import NotoSearch

/// Test case index
/// 1. testReplaceNoteRoundTripsChunksAndVectors — insert + allEmbeddings read-back (SC2)
/// 2. testExistingVectorsKeyedByContentHash — reuse lookup for incremental embedding (SC2, SC3)
/// 3. testDeleteNoteCascadesChunks — note deletion removes its vectors (SC2)
/// 4. testGenerationBumpsOnEveryMutation — cache-invalidation counter (SC2, SC4)
/// 5. testReplaceNoteHandlesPathReuseAfterRename — path-derived note ID change keeps UNIQUE(relative_path) intact (SC2)
/// 6. testVectorEncodeDecodeRoundTrip — fp32 blob codec (SC2)
/// 7. testDestroyRemovesDatabase — rebuild hatch (SC2)
/// 8. testStatsReportCountsAndModelVersion — Settings surface (SC2)
struct SemanticIndexStoreTests {
    private func makeStore() throws -> (store: SemanticIndexStore, dir: URL) {
        let dir = try makeTempDirectory("SemanticStore")
        return (try SemanticIndexStore(indexDirectory: dir), dir)
    }

    private func makeChunk(noteID: UUID, seed: String, hash: String) -> SemanticChunk {
        SemanticChunk(
            id: UUID(),
            noteID: noteID,
            heading: "Heading \(seed)",
            lineStart: 1,
            lineEnd: 5,
            embeddedText: "Title > Heading \(seed)\nbody",
            snippetText: "body \(seed)",
            contentHash: hash
        )
    }

    @Test func testReplaceNoteRoundTripsChunksAndVectors() throws {
        let (store, dir) = try makeStore()
        defer { removeDirectory(dir) }
        let noteID = UUID()
        let vector: [Float] = FakeEmbedder.vector(for: "a", dimensions: 8)

        try store.replaceNote(
            noteID: noteID,
            relativePath: "Projects/A.md",
            noteTitle: "A",
            noteContentHash: "h1",
            modelVersion: "v1",
            chunks: [(makeChunk(noteID: noteID, seed: "1", hash: "c1"), vector)]
        )

        let (dims, matrix, chunks) = try store.allEmbeddings()
        #expect(dims == 8)
        #expect(matrix.count == 8)
        #expect(chunks.count == 1)
        #expect(chunks[0].noteID == noteID)
        #expect(chunks[0].noteTitle == "A")
        #expect(chunks[0].relativePath == "Projects/A.md")
        #expect(zip(matrix, vector).allSatisfy { abs($0 - $1) < 1e-6 })
    }

    @Test func testExistingVectorsKeyedByContentHash() throws {
        let (store, dir) = try makeStore()
        defer { removeDirectory(dir) }
        let noteID = UUID()
        let v1: [Float] = FakeEmbedder.vector(for: "1", dimensions: 4)
        let v2: [Float] = FakeEmbedder.vector(for: "2", dimensions: 4)

        try store.replaceNote(
            noteID: noteID, relativePath: "A.md", noteTitle: "A",
            noteContentHash: "h", modelVersion: "v1",
            chunks: [
                (makeChunk(noteID: noteID, seed: "1", hash: "hash-1"), v1),
                (makeChunk(noteID: noteID, seed: "2", hash: "hash-2"), v2),
            ]
        )

        let vectors = try store.existingVectors(noteID: noteID)
        #expect(vectors.count == 2)
        #expect(vectors["hash-1"] == v1)
        #expect(vectors["hash-2"] == v2)
        #expect(try store.existingVectors(noteID: UUID()).isEmpty)
    }

    @Test func testDeleteNoteCascadesChunks() throws {
        let (store, dir) = try makeStore()
        defer { removeDirectory(dir) }
        let noteID = UUID()
        try store.replaceNote(
            noteID: noteID, relativePath: "A.md", noteTitle: "A",
            noteContentHash: "h", modelVersion: "v1",
            chunks: [(makeChunk(noteID: noteID, seed: "1", hash: "c1"), [1, 0])]
        )

        #expect(try store.deleteNote(noteID: noteID))
        let stats = try store.stats()
        #expect(stats.noteCount == 0)
        #expect(stats.chunkCount == 0)
        #expect(try store.deleteNote(noteID: noteID) == false)
    }

    @Test func testGenerationBumpsOnEveryMutation() throws {
        let (store, dir) = try makeStore()
        defer { removeDirectory(dir) }
        let initial = try store.generation()
        let noteID = UUID()

        try store.replaceNote(
            noteID: noteID, relativePath: "A.md", noteTitle: "A",
            noteContentHash: "h", modelVersion: "v1",
            chunks: [(makeChunk(noteID: noteID, seed: "1", hash: "c1"), [1, 0])]
        )
        let afterInsert = try store.generation()
        #expect(afterInsert > initial)

        try store.deleteNote(noteID: noteID)
        #expect(try store.generation() > afterInsert)
    }

    @Test func testReplaceNoteHandlesPathReuseAfterRename() throws {
        let (store, dir) = try makeStore()
        defer { removeDirectory(dir) }
        let oldID = UUID()
        let newID = UUID()

        try store.replaceNote(
            noteID: oldID, relativePath: "Same.md", noteTitle: "Old",
            noteContentHash: "h1", modelVersion: "v1",
            chunks: [(makeChunk(noteID: oldID, seed: "1", hash: "c1"), [1, 0])]
        )
        try store.replaceNote(
            noteID: newID, relativePath: "Same.md", noteTitle: "New",
            noteContentHash: "h2", modelVersion: "v1",
            chunks: [(makeChunk(noteID: newID, seed: "2", hash: "c2"), [0, 1])]
        )

        let catalog = try store.noteCatalog()
        #expect(catalog.count == 1)
        #expect(catalog[0].noteID == newID)
        #expect(try store.stats().chunkCount == 1)
    }

    @Test func testVectorEncodeDecodeRoundTrip() {
        let vector: [Float] = [0.25, -1.5, 3.75, 0]
        let data = SemanticIndexStore.encode(vector)
        #expect(data.count == 16)
        #expect(SemanticIndexStore.decode(data, dims: 4) == vector)
        #expect(SemanticIndexStore.decode(data, dims: 3) == nil)
    }

    @Test func testDestroyRemovesDatabase() throws {
        let (store, dir) = try makeStore()
        defer { removeDirectory(dir) }
        let databaseURL = store.databaseURL
        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
        try store.destroy()
        #expect(!FileManager.default.fileExists(atPath: databaseURL.path))
    }

    @Test func testStatsReportCountsAndModelVersion() throws {
        let (store, dir) = try makeStore()
        defer { removeDirectory(dir) }
        let noteID = UUID()
        try store.replaceNote(
            noteID: noteID, relativePath: "A.md", noteTitle: "A",
            noteContentHash: "h", modelVersion: "granite-97m-r2-int8",
            chunks: [
                (makeChunk(noteID: noteID, seed: "1", hash: "c1"), [1, 0]),
                (makeChunk(noteID: noteID, seed: "2", hash: "c2"), [0, 1]),
            ]
        )
        let stats = try store.stats()
        #expect(stats.noteCount == 1)
        #expect(stats.chunkCount == 2)
        #expect(stats.modelVersion == "granite-97m-r2-int8")
    }
}
