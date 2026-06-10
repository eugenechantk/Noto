import Foundation
import Testing
@testable import NotoSearch

/// Test case index
/// 1. testInitialRefreshEmbedsAllNotes — first sweep embeds every indexable note; second sweep is a no-op (SC3)
/// 2. testEditedNoteReembedsOnlyChangedChunks — unchanged sibling chunks are reused, not re-embedded (SC3)
/// 3. testDeletedNoteIsRemovedFromSemanticIndex — catalog diff purges vanished notes (SC3)
/// 4. testModelVersionBumpReembedsEverything — model swap invalidates all hashes (SC3)
/// 5. testMissingSearchIndexIsGracefulNoop — semantic refresh before FTS ever ran does nothing (SC3)
/// 6. testCancellationStopsBetweenNotesAndResumes — shouldContinue gates the sweep; next run finishes the rest (SC3)
/// 7. testSingleNoteEmbedFailureIsSkipped — one bad note doesn't abort the sweep; the rest index (bug 018)
/// 8. testConsecutiveEmbedFailuresAbortSweep — systemic embedder failure still surfaces as an error (bug 018)
struct SemanticIndexerTests {
    /// Builds a temp vault + FTS index sharing one index directory.
    private func makeIndexedVault(
        notes: [(path: String, markdown: String)]
    ) throws -> (vault: URL, indexDir: URL) {
        let vault = try makeTempDirectory("SemanticIndexerVault")
        let indexDir = try makeTempDirectory("SemanticIndexerIndex")
        for note in notes {
            _ = try writeMarkdown(note.markdown, to: note.path, in: vault)
        }
        let indexer = MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDir)
        _ = try indexer.refreshChangedFiles()
        return (vault, indexDir)
    }

    private func longSection(_ marker: String) -> String {
        Array(repeating: "The \(marker) section talks about strategy planning and execution detail.", count: 40)
            .joined(separator: "\n")
    }

    @Test func testInitialRefreshEmbedsAllNotes() throws {
        let (vault, indexDir) = try makeIndexedVault(notes: [
            ("A.md", "# Note A\n\nBudget planning for the quarter ahead."),
            ("Sub/B.md", "# Note B\n\nGarden seedlings and spring planting schedule."),
        ])
        defer { removeDirectory(vault); removeDirectory(indexDir) }

        let embedder = FakeEmbedder()
        let indexer = SemanticIndexer(vaultURL: vault, embedding: embedder, indexDirectory: indexDir)

        let first = try indexer.refreshFromSearchIndex()
        #expect(first.refreshedNotes == 2)
        #expect(first.embeddedChunks == 2)
        #expect(first.stats.noteCount == 2)
        #expect(first.stats.chunkCount == 2)

        let second = try indexer.refreshFromSearchIndex()
        #expect(second.refreshedNotes == 0)
        #expect(second.embeddedChunks == 0)
        #expect(embedder.embedCallTotal == 2)
    }

    @Test func testEditedNoteReembedsOnlyChangedChunks() throws {
        let original = "# Big Note\n\n## Alpha\n\n\(longSection("alpha"))\n\n## Beta\n\n\(longSection("beta"))"
        let (vault, indexDir) = try makeIndexedVault(notes: [("Big.md", original)])
        defer { removeDirectory(vault); removeDirectory(indexDir) }

        let embedder = FakeEmbedder()
        let indexer = SemanticIndexer(vaultURL: vault, embedding: embedder, indexDirectory: indexDir)
        let first = try indexer.refreshFromSearchIndex()
        #expect(first.embeddedChunks >= 2)
        let embedsAfterFirst = embedder.embedCallTotal

        // Edit only the Beta section.
        let edited = original.replacingOccurrences(
            of: "The beta section talks about strategy",
            with: "The beta section now discusses pricing"
        )
        _ = try writeMarkdown(edited, to: "Big.md", in: vault)
        _ = try MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDir).refreshChangedFiles()

        let second = try indexer.refreshFromSearchIndex()
        #expect(second.refreshedNotes == 1)
        #expect(second.embeddedChunks >= 1)
        #expect(second.reusedChunks >= 1)
        // Alpha chunks were reused: total embeds grew by less than the note's full chunk count.
        let newEmbeds = embedder.embedCallTotal - embedsAfterFirst
        #expect(newEmbeds == second.embeddedChunks)
        #expect(newEmbeds < first.embeddedChunks)
    }

    @Test func testDeletedNoteIsRemovedFromSemanticIndex() throws {
        let (vault, indexDir) = try makeIndexedVault(notes: [
            ("Keep.md", "# Keep\n\nThis note stays in the vault."),
            ("Drop.md", "# Drop\n\nThis note will be deleted."),
        ])
        defer { removeDirectory(vault); removeDirectory(indexDir) }

        let embedder = FakeEmbedder()
        let indexer = SemanticIndexer(vaultURL: vault, embedding: embedder, indexDirectory: indexDir)
        _ = try indexer.refreshFromSearchIndex()

        try FileManager.default.removeItem(at: vault.appendingPathComponent("Drop.md"))
        _ = try MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDir).refreshChangedFiles()

        let result = try indexer.refreshFromSearchIndex()
        #expect(result.deletedNotes == 1)
        #expect(result.stats.noteCount == 1)
    }

    @Test func testModelVersionBumpReembedsEverything() throws {
        let (vault, indexDir) = try makeIndexedVault(notes: [
            ("A.md", "# Note A\n\nBudget planning for the quarter ahead."),
            ("B.md", "# Note B\n\nGarden seedlings and spring planting schedule."),
        ])
        defer { removeDirectory(vault); removeDirectory(indexDir) }

        let v1 = FakeEmbedder(modelVersion: "v1")
        _ = try SemanticIndexer(vaultURL: vault, embedding: v1, indexDirectory: indexDir)
            .refreshFromSearchIndex()

        let v2 = FakeEmbedder(modelVersion: "v2")
        let result = try SemanticIndexer(vaultURL: vault, embedding: v2, indexDirectory: indexDir)
            .refreshFromSearchIndex()
        #expect(result.refreshedNotes == 2)
        #expect(result.embeddedChunks == 2)
        #expect(result.stats.modelVersion == "v2")
    }

    @Test func testMissingSearchIndexIsGracefulNoop() throws {
        let vault = try makeTempDirectory("SemanticNoFTSVault")
        let indexDir = try makeTempDirectory("SemanticNoFTSIndex")
        defer { removeDirectory(vault); removeDirectory(indexDir) }
        _ = try writeMarkdown("# A\n\nSome content here.", to: "A.md", in: vault)

        let embedder = FakeEmbedder()
        let indexer = SemanticIndexer(vaultURL: vault, embedding: embedder, indexDirectory: indexDir)
        let result = try indexer.refreshFromSearchIndex()
        #expect(result.scannedNotes == 0)
        #expect(result.refreshedNotes == 0)
        #expect(embedder.embedCallTotal == 0)
    }

    @Test func testCancellationStopsBetweenNotesAndResumes() throws {
        let (vault, indexDir) = try makeIndexedVault(notes: [
            ("A.md", "# Note A\n\nFirst note content for embedding."),
            ("B.md", "# Note B\n\nSecond note content for embedding."),
            ("C.md", "# Note C\n\nThird note content for embedding."),
        ])
        defer { removeDirectory(vault); removeDirectory(indexDir) }

        let embedder = FakeEmbedder()
        let indexer = SemanticIndexer(vaultURL: vault, embedding: embedder, indexDirectory: indexDir)

        // Allow exactly one note through, then cancel.
        let counter = Counter()
        let partial = try indexer.refreshFromSearchIndex(shouldContinue: {
            counter.next() <= 1
        })
        #expect(partial.refreshedNotes == 1)

        let resumed = try indexer.refreshFromSearchIndex()
        #expect(resumed.refreshedNotes == 2)
        #expect(try indexer.openStore().stats().noteCount == 3)
    }

    @Test func testSingleNoteEmbedFailureIsSkipped() throws {
        let (vault, indexDir) = try makeIndexedVault(notes: [
            ("A.md", "# Note A\n\nFirst note content for embedding."),
            ("B.md", "# Note B\n\nPOISON second note content."),
            ("C.md", "# Note C\n\nThird note content for embedding."),
        ])
        defer { removeDirectory(vault); removeDirectory(indexDir) }

        let embedder = PoisonableEmbedder(poisonMarker: "POISON")
        let indexer = SemanticIndexer(vaultURL: vault, embedding: embedder, indexDirectory: indexDir)
        let result = try indexer.refreshFromSearchIndex()

        #expect(result.refreshedNotes == 2)
        #expect(result.stats.noteCount == 2)
        // The poisoned note stays a candidate and is retried on the next sweep.
        embedder.disarm()
        let retry = try indexer.refreshFromSearchIndex()
        #expect(retry.refreshedNotes == 1)
        #expect(retry.stats.noteCount == 3)
    }

    @Test func testConsecutiveEmbedFailuresAbortSweep() throws {
        let (vault, indexDir) = try makeIndexedVault(notes: [
            ("A.md", "# Note A\n\nPOISON one."),
            ("B.md", "# Note B\n\nPOISON two."),
            ("C.md", "# Note C\n\nPOISON three."),
            ("D.md", "# Note D\n\nPOISON four."),
        ])
        defer { removeDirectory(vault); removeDirectory(indexDir) }

        let embedder = PoisonableEmbedder(poisonMarker: "POISON")
        let indexer = SemanticIndexer(vaultURL: vault, embedding: embedder, indexDirectory: indexDir)
        #expect(throws: (any Error).self) {
            try indexer.refreshFromSearchIndex()
        }
    }
}

/// Embedder that throws for texts containing a marker until disarmed.
private final class PoisonableEmbedder: TextEmbedding, @unchecked Sendable {
    let modelVersion = "poison-v1"
    let dimensions = 8
    private let lock = NSLock()
    private var marker: String?

    init(poisonMarker: String) {
        self.marker = poisonMarker
    }

    func disarm() {
        lock.lock()
        marker = nil
        lock.unlock()
    }

    func embed(_ texts: [String]) throws -> [[Float]] {
        lock.lock()
        let activeMarker = marker
        lock.unlock()
        if let activeMarker, texts.contains(where: { $0.contains(activeMarker) }) {
            throw NSError(domain: "poison", code: 1)
        }
        return texts.map { FakeEmbedder.vector(for: $0, dimensions: dimensions) }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
