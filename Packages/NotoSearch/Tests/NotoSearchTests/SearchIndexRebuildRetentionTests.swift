import Foundation
import Testing
import NotoSearch

// Test index (bug 020 — rebuild must not drop evicted iCloud notes):
// 1. rebuildRetainsRowsForUnavailablePaths — retained paths keep their rows; others are replaced/dropped
// 2. rebuildWithoutRetentionReplacesEverything — empty retention set keeps the original full-replace behavior
// 3. localVaultRebuildReportsNoSkippedFiles — local (non-iCloud) vault: skippedUnavailable == 0, all files indexed

@Suite("SearchIndexStore rebuild retention")
struct SearchIndexRebuildRetentionTests {
    @Test("Rebuild keeps rows for retained relative paths and drops the rest")
    func rebuildRetainsRowsForUnavailablePaths() throws {
        let indexDirectory = try makeTempDirectory("NotoSearchRetentionIndex")
        defer { removeDirectory(indexDirectory) }

        let store = try SearchIndexStore(indexDirectory: indexDirectory)
        let original = ["Available.md", "Evicted.md", "Deleted.md"].map(makeDocument(relativePath:))
        _ = try store.rebuild(documents: original.map { ($0, Date()) })

        let updatedAvailable = makeDocument(relativePath: "Available.md")
        let stats = try store.rebuild(
            documents: [SearchIndexedDocument(document: updatedAvailable, fileModifiedAt: Date(), fileSize: 10)],
            retainingRelativePaths: ["Evicted.md"]
        )

        let catalog = try store.noteCatalog()
        #expect(stats.noteCount == 2)
        #expect(Set(catalog.map(\.relativePath)) == ["Available.md", "Evicted.md"])
        // The available note was replaced (new noteID); the evicted note kept its row.
        #expect(catalog.first { $0.relativePath == "Available.md" }?.noteID == updatedAvailable.id)
        #expect(catalog.first { $0.relativePath == "Evicted.md" }?.noteID == original[1].id)
    }

    @Test("Rebuild with no retained paths replaces the whole index")
    func rebuildWithoutRetentionReplacesEverything() throws {
        let indexDirectory = try makeTempDirectory("NotoSearchRetentionIndex")
        defer { removeDirectory(indexDirectory) }

        let store = try SearchIndexStore(indexDirectory: indexDirectory)
        _ = try store.rebuild(documents: [(makeDocument(relativePath: "Old.md"), Date())])

        let replacement = makeDocument(relativePath: "New.md")
        let stats = try store.rebuild(
            documents: [SearchIndexedDocument(document: replacement, fileModifiedAt: Date(), fileSize: 10)]
        )

        #expect(stats.noteCount == 1)
        #expect(try store.noteCatalog().map(\.relativePath) == ["New.md"])
    }

    @Test("Local vault rebuild indexes every file and skips none")
    func localVaultRebuildReportsNoSkippedFiles() throws {
        let vault = try makeFixtureVault()
        let indexDirectory = try makeTempDirectory("NotoSearchRetentionIndex")
        defer {
            removeDirectory(vault)
            removeDirectory(indexDirectory)
        }

        let indexer = MarkdownSearchIndexer(vaultURL: vault, indexDirectory: indexDirectory)
        let result = try indexer.rebuild()

        #expect(result.skippedUnavailable == 0)
        #expect(result.scanned == 3)
        #expect(result.upserted == 3)
        #expect(result.stats.noteCount == 3)
    }

    private func makeDocument(relativePath: String) -> SearchDocument {
        SearchDocument(
            id: UUID(),
            relativePath: relativePath,
            title: (relativePath as NSString).deletingPathExtension,
            folderPath: "",
            contentHash: UUID().uuidString,
            plainText: "content for \(relativePath)",
            sections: []
        )
    }
}
