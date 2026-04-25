import Foundation
import Testing
import NotoSearch

@Suite("MarkdownSearchIndexer")
struct MarkdownSearchIndexerTests {
    @Test("Indexer rebuilds fixture vault and ignores hidden .noto files")
    func indexerRebuildsFixtureVault() throws {
        let vault = try makeFixtureVault()
        let indexDirectory = try makeTempDirectory("NotoSearchIndex")
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let indexer = MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDirectory)
        let result = try indexer.rebuild()

        #expect(result.scanned == 3)
        #expect(result.stats.noteCount == 3)
        #expect(result.stats.sectionCount >= 5)
        #expect(FileManager.default.fileExists(atPath: indexDirectory.appendingPathComponent("search.sqlite").path))
    }

    @Test("Changed-file refresh updates edited notes and removes deleted notes")
    func refreshChangedFilesReconcilesEditsAndDeletes() throws {
        let vault = try makeFixtureVault()
        let indexDirectory = try makeTempDirectory("NotoSearchIndex")
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let indexer = MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDirectory)
        _ = try indexer.rebuild()
        let editedURL = vault.appendingPathComponent("Body Only.md")
        try "# Body Only Match\n\nNewly searchable nebula phrase.".write(to: editedURL, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Captures/Reader Capture.md"))

        let result = try indexer.refreshChangedFiles()
        let engine = MarkdownSearchEngine(store: try indexer.openStore(), vaultURL: vault)

        #expect(result.scanned == 2)
        #expect(result.upserted == 1)
        #expect(result.deleted == 1)
        #expect(try engine.search("nebula").first?.title == "Body Only Match")
        #expect(try engine.search("retention loops").isEmpty)
    }

    @Test("Changed-file refresh removes stale paths after note move")
    func refreshChangedFilesRemovesStalePathsAfterMove() throws {
        let vault = try makeFixtureVault()
        let indexDirectory = try makeTempDirectory("NotoSearchIndex")
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let indexer = MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDirectory)
        _ = try indexer.rebuild()
        let movedDirectory = vault.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: movedDirectory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: vault.appendingPathComponent("Body Only.md"),
            to: movedDirectory.appendingPathComponent("Renamed Body.md")
        )

        let result = try indexer.refreshChangedFiles()
        let engine = MarkdownSearchEngine(store: try indexer.openStore(), vaultURL: vault)
        let results = try engine.search("orchard velocity")

        #expect(result.scanned == 3)
        #expect(result.upserted == 1)
        #expect(result.deleted == 1)
        #expect(results.first?.fileURL.lastPathComponent == "Renamed Body.md")
        #expect(results.allSatisfy { !$0.fileURL.path.hasSuffix("Body Only.md") })
    }

    @Test("Rebuild after deleting search.sqlite restores equivalent counts")
    func rebuildRestoresDeletedIndex() throws {
        let vault = try makeFixtureVault()
        let indexDirectory = try makeTempDirectory("NotoSearchIndex")
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let indexer = MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDirectory)
        let first = try indexer.rebuild().stats
        try FileManager.default.removeItem(at: indexDirectory.appendingPathComponent("search.sqlite"))
        let second = try indexer.rebuild().stats

        #expect(first == second)
    }
}
