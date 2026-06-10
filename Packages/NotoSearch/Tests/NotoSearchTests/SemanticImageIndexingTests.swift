import Foundation
import Testing
@testable import NotoSearch

/// Test case index
/// 1. testVaultImageBecomesImageChunk — attached image described + embedded as an image-kind chunk with path + line (SC16)
/// 2. testUnchangedImageIsNotRedescribed — note text edit re-indexes the note but reuses the image chunk (no describe/embed) (SC16)
/// 3. testChangedImageBytesRedescribe — overwriting the image file re-describes and re-embeds it (SC16)
/// 4. testRemovedImageDropsChunk — deleting the markdown reference removes the image chunk (SC16)
/// 5. testRemoteImageGoesThroughFetcher — http URL fetched via RemoteImageFetching and indexed (SC17)
/// 6. testRemoteFetchFailureSkipsQuietly — fetcher nil → no image chunk, no error, text chunks intact (SC17)
/// 7. testAltTextChangeInvalidatesImageChunk — invalidation hash covers alt text (SC16)
/// 8. testImageHitSurfacesThroughSearchAndFusion — searcher returns image hit; fusion synthesizes an image-marked result (SC18)
struct SemanticImageIndexingTests {
    // MARK: Fakes

    private final class FakeDescriber: ImageDescribing, @unchecked Sendable {
        let describerVersion = "fake-describer-v1"
        private let lock = NSLock()
        private(set) var describedBytes: [Int] = []
        var ocrByByteCount: [Int: String] = [:]

        func describe(imageData: Data) throws -> ImageDescription {
            lock.lock()
            describedBytes.append(imageData.count)
            lock.unlock()
            let ocr = ocrByByteCount[imageData.count] ?? "ocr text bytes \(imageData.count)"
            return ImageDescription(ocrText: ocr, labels: ["receipt", "document"])
        }

        var describeCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return describedBytes.count
        }
    }

    private final class FakeFetcher: RemoteImageFetching, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var fetchedURLs: [URL] = []
        var responses: [String: Data] = [:]

        func fetch(url: URL) -> Data? {
            lock.lock()
            fetchedURLs.append(url)
            lock.unlock()
            return responses[url.absoluteString]
        }
    }

    private struct Fixture {
        let vault: URL
        let indexDir: URL
        let embedder: FakeEmbedder
        let describer: FakeDescriber
        let fetcher: FakeFetcher
        let indexer: SemanticIndexer

        func ftsRefresh() throws {
            _ = try MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDir).refreshChangedFiles()
        }

        func tearDown() {
            removeDirectory(vault)
            removeDirectory(indexDir)
        }
    }

    private func makeFixture() throws -> Fixture {
        let vault = try makeTempDirectory("ImageIndexVault")
        let indexDir = try makeTempDirectory("ImageIndexIndex")
        let embedder = FakeEmbedder()
        let describer = FakeDescriber()
        let fetcher = FakeFetcher()
        let indexer = SemanticIndexer(
            vaultURL: vault,
            embedding: embedder,
            indexDirectory: indexDir,
            describer: describer,
            imageFetcher: fetcher
        )
        return Fixture(vault: vault, indexDir: indexDir, embedder: embedder,
                       describer: describer, fetcher: fetcher, indexer: indexer)
    }

    private func writeImage(_ bytes: Int, to relativePath: String, in vault: URL) throws {
        let url = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: bytes).write(to: url)
    }

    private func imageChunks(_ fixture: Fixture) throws -> [SemanticIndexStore.ChunkRecord] {
        try SemanticIndexStore(indexDirectory: fixture.indexDir).allEmbeddings().chunks.filter { $0.kind == .image }
    }

    // MARK: Tests

    @Test func testVaultImageBecomesImageChunk() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        try writeImage(100, to: ".attachments/My Receipt.png", in: fixture.vault)
        _ = try writeMarkdown(
            "# Expenses\n\nLunch meeting receipt:\n\n![receipt scan](.attachments/My%20Receipt.png)",
            to: "Expenses.md", in: fixture.vault
        )
        try fixture.ftsRefresh()
        let result = try fixture.indexer.refreshFromSearchIndex()

        #expect(result.refreshedNotes == 1)
        let images = try imageChunks(fixture)
        #expect(images.count == 1)
        #expect(images[0].imagePath == ".attachments/My Receipt.png")
        #expect(images[0].heading == "receipt scan")
        #expect(images[0].lineStart == 5)
        #expect(images[0].snippet.contains("ocr text"))
        #expect(fixture.describer.describeCount == 1)
    }

    @Test func testUnchangedImageIsNotRedescribed() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        try writeImage(100, to: ".attachments/pic.png", in: fixture.vault)
        _ = try writeMarkdown("# Note\n\nBody one.\n\n![pic](.attachments/pic.png)", to: "Note.md", in: fixture.vault)
        try fixture.ftsRefresh()
        _ = try fixture.indexer.refreshFromSearchIndex()
        #expect(fixture.describer.describeCount == 1)
        let embedsAfterFirst = fixture.embedder.embedCallTotal

        // Edit only the note text; image bytes unchanged.
        _ = try writeMarkdown("# Note\n\nBody two, edited.\n\n![pic](.attachments/pic.png)", to: "Note.md", in: fixture.vault)
        try fixture.ftsRefresh()
        let second = try fixture.indexer.refreshFromSearchIndex()

        #expect(second.refreshedNotes == 1)
        #expect(fixture.describer.describeCount == 1)   // image untouched
        // Only the text chunk re-embedded; the image vector was reused.
        let newEmbeds = fixture.embedder.embeddedTexts.suffix(fixture.embedder.embedCallTotal - embedsAfterFirst)
        #expect(!newEmbeds.contains { $0.contains("ocr text") })
        #expect(try imageChunks(fixture).count == 1)
    }

    @Test func testChangedImageBytesRedescribe() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        try writeImage(100, to: ".attachments/pic.png", in: fixture.vault)
        _ = try writeMarkdown("# Note\n\n![pic](.attachments/pic.png)\n\nBody.", to: "Note.md", in: fixture.vault)
        try fixture.ftsRefresh()
        _ = try fixture.indexer.refreshFromSearchIndex()

        // Replace the image with different bytes AND touch the note so it re-indexes.
        try writeImage(200, to: ".attachments/pic.png", in: fixture.vault)
        _ = try writeMarkdown("# Note\n\n![pic](.attachments/pic.png)\n\nBody updated.", to: "Note.md", in: fixture.vault)
        try fixture.ftsRefresh()
        _ = try fixture.indexer.refreshFromSearchIndex()

        #expect(fixture.describer.describeCount == 2)
        #expect(fixture.describer.describedBytes == [100, 200])
        let images = try imageChunks(fixture)
        #expect(images.count == 1)
        #expect(images[0].snippet.contains("200"))
    }

    @Test func testRemovedImageDropsChunk() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        try writeImage(100, to: ".attachments/pic.png", in: fixture.vault)
        _ = try writeMarkdown("# Note\n\n![pic](.attachments/pic.png)\n\nBody.", to: "Note.md", in: fixture.vault)
        try fixture.ftsRefresh()
        _ = try fixture.indexer.refreshFromSearchIndex()
        #expect(try imageChunks(fixture).count == 1)

        _ = try writeMarkdown("# Note\n\nBody without any image now.", to: "Note.md", in: fixture.vault)
        try fixture.ftsRefresh()
        _ = try fixture.indexer.refreshFromSearchIndex()
        #expect(try imageChunks(fixture).isEmpty)
    }

    @Test func testRemoteImageGoesThroughFetcher() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        fixture.fetcher.responses["https://example.com/chart.png"] = Data(repeating: 0xCD, count: 64)
        _ = try writeMarkdown(
            "# Report\n\n![quarterly chart](https://example.com/chart.png)",
            to: "Report.md", in: fixture.vault
        )
        try fixture.ftsRefresh()
        _ = try fixture.indexer.refreshFromSearchIndex()

        #expect(fixture.fetcher.fetchedURLs.map(\.absoluteString) == ["https://example.com/chart.png"])
        let images = try imageChunks(fixture)
        #expect(images.count == 1)
        #expect(images[0].imagePath == "https://example.com/chart.png")
    }

    @Test func testRemoteFetchFailureSkipsQuietly() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        _ = try writeMarkdown(
            "# Report\n\nIntro text body.\n\n![gone](https://example.com/missing.png)",
            to: "Report.md", in: fixture.vault
        )
        try fixture.ftsRefresh()
        let result = try fixture.indexer.refreshFromSearchIndex()

        #expect(result.refreshedNotes == 1)
        #expect(try imageChunks(fixture).isEmpty)
        #expect(result.stats.chunkCount >= 1)   // the text chunk still indexed
    }

    @Test func testAltTextChangeInvalidatesImageChunk() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        try writeImage(100, to: ".attachments/pic.png", in: fixture.vault)
        _ = try writeMarkdown("# Note\n\n![old alt](.attachments/pic.png)", to: "Note.md", in: fixture.vault)
        try fixture.ftsRefresh()
        _ = try fixture.indexer.refreshFromSearchIndex()

        // Different length so the FTS size/mtime skip heuristic sees a change.
        _ = try writeMarkdown("# Note\n\n![a much more descriptive alt](.attachments/pic.png)", to: "Note.md", in: fixture.vault)
        try fixture.ftsRefresh()
        _ = try fixture.indexer.refreshFromSearchIndex()

        #expect(fixture.describer.describeCount == 2)
        #expect(try imageChunks(fixture).first?.heading == "a much more descriptive alt")
    }

    @Test func testImageHitSurfacesThroughSearchAndFusion() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        try writeImage(100, to: ".attachments/receipt.png", in: fixture.vault)
        fixture.describer.ocrByByteCount[100] = "TOTAL 42.00 GROCERY MART"
        _ = try writeMarkdown("# Shopping\n\n![receipt](.attachments/receipt.png)", to: "Shopping.md", in: fixture.vault)
        try fixture.ftsRefresh()
        _ = try fixture.indexer.refreshFromSearchIndex()

        // Query with the exact embedded text so the deterministic fake embedder
        // produces an identical vector (cosine 1.0).
        let imageRow = try #require(try imageChunks(fixture).first)
        let queryVector = try fixture.embedder.embed(["Shopping > receipt\nreceipt\nTOTAL 42.00 GROCERY MART\nreceipt, document"])[0]
        let hits = try SemanticSearcher(indexDirectory: fixture.indexDir)
            .search(queryVector: queryVector, limit: 5, minScore: 0.5)

        let imageHit = try #require(hits.first { $0.kind == .image })
        #expect(imageHit.chunkID == imageRow.chunkID)
        #expect(imageHit.imagePath == ".attachments/receipt.png")

        let fused = HybridSearchFusion.fuse(keyword: [], semantic: [imageHit], vaultURL: fixture.vault, limit: 10)
        #expect(fused.count == 1)
        #expect(fused[0].breadcrumb.contains("image: receipt"))
        #expect(fused[0].lineStart == 3)
        #expect(fused[0].snippet.contains("GROCERY MART"))
    }
}
