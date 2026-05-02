import Foundation
import Testing
import NotoSearch

@Suite("LiveVaultSearch")
struct LiveVaultSearchTests {
    @Test("Live vault indexes current Noto documents into a disposable temp index")
    func liveVaultIndexesCurrentDocuments() throws {
        guard FileManager.default.fileExists(atPath: liveVaultURL.path) else {
            return
        }
        let indexDirectory = try makeTempDirectory("NotoSearchLiveIndex")
        defer { removeDirectory(indexDirectory) }

        let indexer = MarkdownSearchIndexer(vaultURL: liveVaultURL, indexDirectory: indexDirectory)
        let result = try indexer.rebuild()

        #expect(result.stats.noteCount >= 500)
        #expect(result.stats.sectionCount >= result.stats.noteCount)
        #expect(FileManager.default.fileExists(atPath: indexDirectory.appendingPathComponent("search.sqlite").path))
    }

    @Test("Live vault search returns real capture/title matches")
    func liveVaultSearchReturnsRealMatches() throws {
        guard FileManager.default.fileExists(atPath: liveVaultURL.path) else {
            return
        }
        let indexDirectory = try makeTempDirectory("NotoSearchLiveIndex")
        defer { removeDirectory(indexDirectory) }

        let indexer = MarkdownSearchIndexer(vaultURL: liveVaultURL, indexDirectory: indexDirectory)
        _ = try indexer.rebuild()
        let engine = MarkdownSearchEngine(store: try indexer.openStore(), vaultURL: liveVaultURL)
        let appStoreResults = try engine.search("\"App Store\"", limit: 20)
        let captureResults = try engine.search("How I Built", limit: 20)

        #expect(!appStoreResults.isEmpty)
        #expect(captureResults.contains { $0.fileURL.path.contains("Captures") || $0.title.localizedCaseInsensitiveContains("App") })
    }

    @Test("Live vault partial title query finds Ideas Inventory")
    func liveVaultPartialTitleQueryFindsIdeasInventory() throws {
        guard FileManager.default.fileExists(atPath: liveVaultURL.path) else {
            return
        }
        let indexDirectory = try makeTempDirectory("NotoSearchLiveIndex")
        defer { removeDirectory(indexDirectory) }

        let indexer = MarkdownSearchIndexer(vaultURL: liveVaultURL, indexDirectory: indexDirectory)
        _ = try indexer.rebuild()
        let engine = MarkdownSearchEngine(store: try indexer.openStore(), vaultURL: liveVaultURL)
        let results = try engine.search("ideas inven", limit: 20)

        #expect(results.contains { result in
            result.kind == .note
                && result.title.localizedCaseInsensitiveCompare("Ideas Inventory") == .orderedSame
        })
    }
}
