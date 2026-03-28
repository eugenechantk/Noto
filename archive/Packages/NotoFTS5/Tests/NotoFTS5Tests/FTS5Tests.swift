import Foundation
import SwiftData
import Testing
import NotoModels
import NotoCore
import NotoDirtyTracker
import NotoFTS5

private func createSearchInfra() async -> (FTS5Database, DirtyStore, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fts5-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let db = FTS5Database(directory: tempDir)
    await db.createTablesIfNeeded()

    let store = DirtyStore(directory: tempDir)
    await store.createTablesIfNeeded()

    return (db, store, tempDir)
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

struct FTS5PackageTests {
    @Test
    func databaseUpsertAndSearch() async {
        let (db, _, tempDir) = await createSearchInfra()
        defer { cleanup(tempDir) }

        let id = UUID()
        await db.upsertBlock(blockId: id, content: "coffee notes")

        let results = await db.search(query: "coffee")
        #expect(results.count == 1)
        #expect(results[0].blockId == id)

        await db.close()
    }

    @Test @MainActor
    func indexerFlushesDirtyUpserts() async throws {
        let (db, store, tempDir) = await createSearchInfra()
        defer { cleanup(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "**bold** index me", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        await store.markDirty(blockId: block.id, operation: .upsert)

        let indexer = FTS5Indexer(fts5Database: db, dirtyStore: store, modelContext: context)
        await indexer.flushAll()

        let results = await db.search(query: "index")
        #expect(results.count == 1)
        #expect(results.first?.blockId == block.id)

        await db.close()
        await store.close()
    }

    @Test
    func querySanitizationHandlesUnbalancedQuotes() {
        let sanitized = FTS5Engine.sanitizeQuery("hello \"world")
        #expect(sanitized == "hello world")
    }
}
