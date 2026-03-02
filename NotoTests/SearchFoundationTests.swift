//
//  SearchFoundationTests.swift
//  NotoTests
//
//  Unit tests for FTS5Database, DirtyStore, DirtyTracker, and PlainTextExtractor.
//

import Testing
import Foundation
import NotoFTS5
import NotoDirtyTracker
import NotoCore
@testable import Noto

// MARK: - Shared Test Helpers

/// Creates a temp-directory FTS5 database for testing.
/// Shared by SearchFoundationTests, KeywordSearchTests, and SemanticSearchTests.
func createTestFTS5Database() async -> (FTS5Database, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fts5-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let db = FTS5Database(directory: tempDir)
    await db.createTablesIfNeeded()
    return (db, tempDir)
}

/// Creates a temp-directory DirtyStore for testing.
func createTestDirtyStore() async -> (DirtyStore, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("dirty-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let store = DirtyStore(directory: tempDir)
    await store.createTablesIfNeeded()
    return (store, tempDir)
}

/// Creates both FTS5Database and DirtyStore in the same temp directory.
func createTestSearchDatabases() async -> (FTS5Database, DirtyStore, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("search-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let db = FTS5Database(directory: tempDir)
    await db.createTablesIfNeeded()
    let store = DirtyStore(directory: tempDir)
    await store.createTablesIfNeeded()
    return (db, store, tempDir)
}

/// Cleans up a temp directory.
func cleanupTempDir(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - FTS5Database Tests

struct FTS5DatabaseTests {

    @Test
    func createTablesOnInit() async {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        // Verify we can insert and search
        let testId = UUID()
        await db.upsertBlock(blockId: testId, content: "test content")
        let results = await db.search(query: "test")
        #expect(results.count == 1)

        await db.close()
    }

    @Test
    func openExistingDatabase() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fts5-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { cleanupTempDir(tempDir) }

        // First: create and populate
        let db1 = FTS5Database(directory: tempDir)
        await db1.createTablesIfNeeded()
        let testId = UUID()
        await db1.upsertBlock(blockId: testId, content: "persistent content")
        await db1.close()

        // Second: reopen and verify data persists
        let db2 = FTS5Database(directory: tempDir)
        await db2.createTablesIfNeeded()
        let results = await db2.search(query: "persistent")
        #expect(results.count == 1)
        await db2.close()
    }

    @Test
    func destroyDeletesFile() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fts5-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { cleanupTempDir(tempDir) }

        let db = FTS5Database(directory: tempDir)
        await db.createTablesIfNeeded()

        let dbPath = tempDir.appendingPathComponent("search.sqlite").path
        #expect(FileManager.default.fileExists(atPath: dbPath))

        await db.destroy()
        #expect(!FileManager.default.fileExists(atPath: dbPath))
    }

    @Test
    func concurrentAccessViaActor() async {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        // Fire many concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let id = UUID()
                    await db.upsertBlock(blockId: id, content: "concurrent content \(i)")
                }
            }
        }

        let results = await db.search(query: "concurrent")
        #expect(results.count == 50)
        await db.close()
    }
}

// MARK: - DirtyStore Batch Operation Tests

struct DirtyBatchTests {

    @Test
    func markDirtyBatchInsertsMultiple() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        let ids = (0..<100).map { _ in UUID() }
        await store.markDirtyBatch(blockIds: ids, operation: .upsert)

        let count = await store.dirtyCount()
        #expect(count == 100)
    }

    @Test
    func fetchDirtyBatchRespectsLimit() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        let ids = (0..<100).map { _ in UUID() }
        await store.markDirtyBatch(blockIds: ids, operation: .upsert)

        let batch = await store.fetchDirtyBatch(limit: 50)
        #expect(batch.count == 50)
    }

    @Test
    func removeDirtyCleansUp() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        let ids = (0..<5).map { _ in UUID() }
        await store.markDirtyBatch(blockIds: ids, operation: .upsert)

        let toRemove = Array(ids.prefix(3))
        await store.removeDirty(blockIds: toRemove)

        let count = await store.dirtyCount()
        #expect(count == 2)
    }

    @Test
    func dirtyCountAccurate() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        let ids = (0..<10).map { _ in UUID() }
        await store.markDirtyBatch(blockIds: ids, operation: .upsert)

        let toRemove = Array(ids.prefix(4))
        await store.removeDirty(blockIds: toRemove)

        let count = await store.dirtyCount()
        #expect(count == 6)
    }
}

// MARK: - Metadata Tests

struct MetadataTests {

    @Test
    func setAndGetMetadata() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        await store.setMetadata(key: "version", value: "1.0")
        let retrieved = await store.getMetadata(key: "version")
        #expect(retrieved == "1.0")
    }

    @Test
    func nonExistentKeyReturnsNil() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        let retrieved = await store.getMetadata(key: "nonexistent")
        #expect(retrieved == nil)
    }

    @Test
    func updateExistingMetadata() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        await store.setMetadata(key: "version", value: "1.0")
        await store.setMetadata(key: "version", value: "2.0")

        let retrieved = await store.getMetadata(key: "version")
        #expect(retrieved == "2.0")
    }
}

// MARK: - DirtyTracker Tests

struct DirtyTrackerTests {

    @Test @MainActor
    func markDirtyAccumulates() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        let tracker = DirtyTracker(dirtyStore: store)
        tracker.cancelIdleTimer() // prevent auto-flush

        tracker.markDirty(UUID())
        tracker.markDirty(UUID())
        tracker.markDirty(UUID())

        #expect(tracker.hasDirtyBlocks == true)
    }

    @Test @MainActor
    func duplicateMarkDirtyDeduplicates() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        let tracker = DirtyTracker(dirtyStore: store)
        tracker.cancelIdleTimer()

        let id = UUID()
        tracker.markDirty(id)
        tracker.markDirty(id)

        // Flush and verify only 1 entry in database
        await tracker.flush()
        let count = await store.dirtyCount()
        #expect(count == 1)
    }

    @Test @MainActor
    func flushPersistsToDirtyBlocks() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        let tracker = DirtyTracker(dirtyStore: store)
        tracker.cancelIdleTimer()

        let id = UUID()
        tracker.markDirty(id)
        await tracker.flush()

        // In-memory set should be empty
        #expect(tracker.hasDirtyBlocks == false)

        // Database should have the entry
        let count = await store.dirtyCount()
        #expect(count == 1)

        let batch = await store.fetchDirtyBatch(limit: 10)
        #expect(batch.count == 1)
        #expect(batch[0].blockId == id)
        #expect(batch[0].operation == .upsert)
    }

    @Test @MainActor
    func markDeletedWritesImmediately() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        let tracker = DirtyTracker(dirtyStore: store)
        tracker.cancelIdleTimer()

        let id = UUID()
        tracker.markDeleted(id)

        // Wait briefly for the Task to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        let batch = await store.fetchDirtyBatch(limit: 10)
        #expect(batch.count == 1)
        #expect(batch[0].blockId == id)
        #expect(batch[0].operation == .delete)
    }

    @Test @MainActor
    func flushCancelsIdleTimer() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        let tracker = DirtyTracker(dirtyStore: store)

        tracker.markDirty(UUID())
        await tracker.flush()

        // After flush, hasDirtyBlocks should be false
        #expect(tracker.hasDirtyBlocks == false)
    }

    @Test @MainActor
    func multipleFlushCycles() async {
        let (store, tempDir) = await createTestDirtyStore()
        defer { cleanupTempDir(tempDir) }

        let tracker = DirtyTracker(dirtyStore: store)
        tracker.cancelIdleTimer()

        // First cycle
        let id1 = UUID()
        tracker.markDirty(id1)
        await tracker.flush()

        // Second cycle
        let id2 = UUID()
        tracker.markDirty(id2)
        await tracker.flush()

        let count = await store.dirtyCount()
        #expect(count == 2)
    }
}

// MARK: - PlainTextExtractor Tests

struct PlainTextExtractorTests {

    @Test
    func stripsBold() {
        let result = PlainTextExtractor.plainText(from: "**bold text**")
        #expect(result == "bold text")
    }

    @Test
    func stripsItalic() {
        let result = PlainTextExtractor.plainText(from: "*italic text*")
        #expect(result == "italic text")
    }

    @Test
    func stripsStrikethrough() {
        let result = PlainTextExtractor.plainText(from: "~~deleted~~")
        #expect(result == "deleted")
    }

    @Test
    func stripsInlineCode() {
        let result = PlainTextExtractor.plainText(from: "`codeSnippet`")
        #expect(result == "codeSnippet")
    }

    @Test
    func stripsListBullet() {
        let result = PlainTextExtractor.plainText(from: "* list item")
        #expect(result == "list item")
    }

    @Test
    func stripsListDash() {
        let result = PlainTextExtractor.plainText(from: "- list item")
        #expect(result == "list item")
    }

    @Test
    func stripsNumberedList() {
        let result = PlainTextExtractor.plainText(from: "1. first item")
        #expect(result == "first item")
    }

    @Test
    func stripsCheckboxChecked() {
        let result = PlainTextExtractor.plainText(from: "- [x] done task")
        #expect(result == "done task")
    }

    @Test
    func stripsCheckboxUnchecked() {
        let result = PlainTextExtractor.plainText(from: "- [ ] open task")
        #expect(result == "open task")
    }

    @Test
    func stripsMixedFormatting() {
        let result = PlainTextExtractor.plainText(from: "**bold** and *italic*")
        #expect(result == "bold and italic")
    }

    @Test
    func preservesPlainText() {
        let result = PlainTextExtractor.plainText(from: "plain text")
        #expect(result == "plain text")
    }

    @Test
    func handlesEmptyString() {
        let result = PlainTextExtractor.plainText(from: "")
        #expect(result == "")
    }
}
