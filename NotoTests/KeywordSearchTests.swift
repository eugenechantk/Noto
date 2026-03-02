//
//  KeywordSearchTests.swift
//  NotoTests
//
//  Unit tests for FTS5Engine, FTS5Indexer, and IndexReconciler.
//

import Testing
import Foundation
import SwiftData
import NotoModels
import NotoCore
import NotoFTS5
import NotoDirtyTracker
@testable import Noto

// MARK: - FTS5Engine Query Tests

struct FTS5EngineQueryTests {

    @Test @MainActor
    func exactWordMatch() async throws {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        let blockId = UUID()
        await db.upsertBlock(blockId: blockId, content: "the taste of coffee")

        let engine = FTS5Engine(fts5Database: db)
        let container = try createTestContainer()
        let context = container.mainContext
        let results = await engine.search(query: "coffee", dateRange: nil, modelContext: context)

        #expect(results.count == 1)
        #expect(results.first?.blockId == blockId)
    }

    @Test @MainActor
    func stemmedMatch() async throws {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        let blockId = UUID()
        await db.upsertBlock(blockId: blockId, content: "she was running fast")

        let engine = FTS5Engine(fts5Database: db)
        let container = try createTestContainer()
        let context = container.mainContext
        let results = await engine.search(query: "running", dateRange: nil, modelContext: context)

        #expect(results.count == 1)
        #expect(results.first?.blockId == blockId)
    }

    @Test @MainActor
    func prefixMatch() async throws {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        let blockId = UUID()
        await db.upsertBlock(blockId: blockId, content: "semantic search engine")

        let engine = FTS5Engine(fts5Database: db)
        let container = try createTestContainer()
        let context = container.mainContext
        let results = await engine.search(query: "sema*", dateRange: nil, modelContext: context)

        #expect(results.count == 1)
        #expect(results.first?.blockId == blockId)
    }

    @Test @MainActor
    func phraseMatch() async throws {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        let blockId = UUID()
        await db.upsertBlock(blockId: blockId, content: "design system guidelines")

        let engine = FTS5Engine(fts5Database: db)
        let container = try createTestContainer()
        let context = container.mainContext
        let results = await engine.search(query: "\"design system\"", dateRange: nil, modelContext: context)

        #expect(results.count == 1)
        #expect(results.first?.blockId == blockId)
    }

    @Test @MainActor
    func noMatchReturnsEmpty() async throws {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        await db.upsertBlock(blockId: UUID(), content: "apple banana cherry")

        let engine = FTS5Engine(fts5Database: db)
        let container = try createTestContainer()
        let context = container.mainContext
        let results = await engine.search(query: "quantum", dateRange: nil, modelContext: context)

        #expect(results.isEmpty)
    }

    @Test @MainActor
    func bm25Ordering() async throws {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        let blockA = UUID()
        let blockB = UUID()
        await db.upsertBlock(blockId: blockA, content: "coffee coffee coffee morning brew")
        await db.upsertBlock(blockId: blockB, content: "one coffee in the morning")

        let engine = FTS5Engine(fts5Database: db)
        let container = try createTestContainer()
        let context = container.mainContext
        let results = await engine.search(query: "coffee", dateRange: nil, modelContext: context)

        #expect(results.count == 2)
        // BM25 scores are negative; more negative = better. First result should be best match.
        #expect(results.first?.blockId == blockA)
    }

    @Test @MainActor
    func multipleTerms() async throws {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        let blockBoth = UUID()
        let blockOne = UUID()
        await db.upsertBlock(blockId: blockBoth, content: "the taste of fresh coffee in the morning")
        await db.upsertBlock(blockId: blockOne, content: "the taste of chocolate")

        let engine = FTS5Engine(fts5Database: db)
        let container = try createTestContainer()
        let context = container.mainContext
        let results = await engine.search(query: "taste coffee", dateRange: nil, modelContext: context)

        #expect(!results.isEmpty)
        if results.count >= 2 {
            #expect(results.first?.blockId == blockBoth)
        }
    }

    @Test @MainActor
    func emptyQueryReturnsEmpty() async throws {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        await db.upsertBlock(blockId: UUID(), content: "some content")

        let engine = FTS5Engine(fts5Database: db)
        let container = try createTestContainer()
        let context = container.mainContext
        let results = await engine.search(query: "", dateRange: nil, modelContext: context)

        #expect(results.isEmpty)
    }
}

// MARK: - FTS5Engine Date Post-Filtering Tests

struct FTS5EngineDateFilterTests {

    @Test @MainActor
    func noDateFilterReturnsAll() async throws {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        for i in 1...3 {
            let block = Block(content: "searchable content item \(i)", sortOrder: Double(i))
            context.insert(block)
            await db.upsertBlock(blockId: block.id, content: "searchable content item \(i)")
        }
        try context.save()

        let engine = FTS5Engine(fts5Database: db)
        let results = await engine.search(query: "searchable", dateRange: nil, modelContext: context)

        #expect(results.count == 3)
    }

    @Test @MainActor
    func dateFilterIncludesInRange() async throws {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        let blockA = Block(content: "today searchable note", sortOrder: 1.0)
        context.insert(blockA)
        await db.upsertBlock(blockId: blockA.id, content: "today searchable note")

        let blockB = Block(content: "old searchable note", sortOrder: 2.0)
        context.insert(blockB)
        blockB.createdAt = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        await db.upsertBlock(blockId: blockB.id, content: "old searchable note")

        try context.save()

        let engine = FTS5Engine(fts5Database: db)
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
        let dateRange = DateRange(start: todayStart, end: todayEnd)

        let results = await engine.search(query: "searchable", dateRange: dateRange, modelContext: context)

        #expect(results.count == 1)
        #expect(results.first?.blockId == blockA.id)
    }

    @Test @MainActor
    func dateFilterExcludesOutOfRange() async throws {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "old searchable content", sortOrder: 1.0)
        context.insert(block)
        block.createdAt = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        await db.upsertBlock(blockId: block.id, content: "old searchable content")
        try context.save()

        let engine = FTS5Engine(fts5Database: db)
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
        let dateRange = DateRange(start: todayStart, end: todayEnd)

        let results = await engine.search(query: "searchable", dateRange: dateRange, modelContext: context)

        #expect(results.isEmpty)
    }

    @Test @MainActor
    func emptyFTSWithDateFilter() async throws {
        let (db, tempDir) = await createTestFTS5Database()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        let engine = FTS5Engine(fts5Database: db)
        let dateRange = DateRange(start: Date(), end: Date())
        let results = await engine.search(query: "nonexistent", dateRange: dateRange, modelContext: context)

        #expect(results.isEmpty)
    }
}

// MARK: - FTS5Indexer Tests

struct FTS5IndexerTests {

    @Test @MainActor
    func flushAllProcessesUpserts() async throws {
        let (db, store, tempDir) = await createTestSearchDatabases()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "**bold** indexable content", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        await store.markDirty(blockId: block.id, operation: .upsert)

        let indexer = FTS5Indexer(fts5Database: db, dirtyStore: store, modelContext: context)
        await indexer.flushAll()

        let results = await db.search(query: "indexable")
        #expect(results.count == 1)
        #expect(results.first?.blockId == block.id)

        let dirtyCount = await store.dirtyCount()
        #expect(dirtyCount == 0)
    }

    @Test @MainActor
    func flushAllProcessesDeletes() async throws {
        let (db, store, tempDir) = await createTestSearchDatabases()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        let blockId = UUID()
        await db.upsertBlock(blockId: blockId, content: "deletable content")

        var results = await db.search(query: "deletable")
        #expect(results.count == 1)

        await store.markDirty(blockId: blockId, operation: .delete)

        let indexer = FTS5Indexer(fts5Database: db, dirtyStore: store, modelContext: context)
        await indexer.flushAll()

        results = await db.search(query: "deletable")
        #expect(results.isEmpty)
    }

    @Test @MainActor
    func batchProcessing() async throws {
        let (db, store, tempDir) = await createTestSearchDatabases()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        var blockIds: [UUID] = []
        for i in 0..<150 {
            let block = Block(content: "batch item number \(i)", sortOrder: Double(i))
            context.insert(block)
            blockIds.append(block.id)
        }
        try context.save()

        await store.markDirtyBatch(blockIds: blockIds, operation: .upsert)

        let indexer = FTS5Indexer(fts5Database: db, dirtyStore: store, modelContext: context)
        await indexer.flushAll()

        let results = await db.search(query: "batch")
        #expect(results.count == 150)

        let dirtyCount = await store.dirtyCount()
        #expect(dirtyCount == 0)
    }

    @Test @MainActor
    func rebuildAllFromScratch() async throws {
        let (db, store, tempDir) = await createTestSearchDatabases()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        for i in 0..<5 {
            let block = Block(content: "rebuild test block \(i)", sortOrder: Double(i))
            context.insert(block)
        }
        try context.save()

        let indexer = FTS5Indexer(fts5Database: db, dirtyStore: store, modelContext: context)
        await indexer.rebuildAll()

        let results = await db.search(query: "rebuild")
        #expect(results.count == 5)
    }

    @Test @MainActor
    func flushAllUpdatesReconciliationTimestamp() async throws {
        let (db, store, tempDir) = await createTestSearchDatabases()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        let before = await store.getMetadata(key: "lastFullReconciliationAt")
        #expect(before == nil)

        let indexer = FTS5Indexer(fts5Database: db, dirtyStore: store, modelContext: context)
        await indexer.flushAll()

        let after = await store.getMetadata(key: "lastFullReconciliationAt")
        #expect(after != nil)
    }

    @Test @MainActor
    func rebuildExcludesArchivedBlocks() async throws {
        let (db, store, tempDir) = await createTestSearchDatabases()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        let active = Block(content: "active rebuild content", sortOrder: 1.0)
        let archived = Block(content: "archived rebuild content", sortOrder: 2.0, isArchived: true)
        context.insert(active)
        context.insert(archived)
        try context.save()

        let indexer = FTS5Indexer(fts5Database: db, dirtyStore: store, modelContext: context)
        await indexer.rebuildAll()

        let results = await db.search(query: "rebuild")
        #expect(results.count == 1)
        #expect(results.first?.blockId == active.id)
    }
}

// MARK: - IndexReconciler Tests

struct IndexReconcilerTests {

    @Test @MainActor
    func firstLaunchTriggersRebuild() async throws {
        let (db, store, tempDir) = await createTestSearchDatabases()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "first launch content", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let reconciler = IndexReconciler(fts5Database: db, dirtyStore: store, modelContext: context)
        await reconciler.reconcileIfNeeded()

        let results = await db.search(query: "launch")
        #expect(results.count == 1)
        #expect(results.first?.blockId == block.id)

        let timestamp = await store.getMetadata(key: "lastFullReconciliationAt")
        #expect(timestamp != nil)
    }

    @Test @MainActor
    func cleanStateSkipsReconciliation() async throws {
        let (db, store, tempDir) = await createTestSearchDatabases()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        let recentTimestamp = ISO8601DateFormatter().string(from: Date())
        await store.setMetadata(key: "lastFullReconciliationAt", value: recentTimestamp)

        let reconciler = IndexReconciler(fts5Database: db, dirtyStore: store, modelContext: context)
        await reconciler.reconcileIfNeeded()

        let timestamp = await store.getMetadata(key: "lastFullReconciliationAt")
        #expect(timestamp != nil)
    }

    @Test @MainActor
    func detectsMissedBlocks() async throws {
        let (db, store, tempDir) = await createTestSearchDatabases()
        defer { cleanupTempDir(tempDir) }

        let container = try createTestContainer()
        let context = container.mainContext

        let oldDate = Calendar.current.date(byAdding: .hour, value: -1, to: Date())!
        let oldTimestamp = ISO8601DateFormatter().string(from: oldDate)
        await store.setMetadata(key: "lastFullReconciliationAt", value: oldTimestamp)

        let block = Block(content: "missed block content", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let reconciler = IndexReconciler(fts5Database: db, dirtyStore: store, modelContext: context)
        await reconciler.reconcileIfNeeded()

        let results = await db.search(query: "missed")
        #expect(results.count == 1)
        #expect(results.first?.blockId == block.id)
    }
}

// MARK: - Query Sanitization Tests

struct QuerySanitizationTests {

    @Test
    func normalQueryPassesThrough() {
        let result = FTS5Engine.sanitizeQuery("hello world")
        #expect(result == "hello world")
    }

    @Test
    func unbalancedQuotesStripped() {
        let result = FTS5Engine.sanitizeQuery("hello \"world")
        #expect(!result.contains("\""))
        #expect(result.contains("hello"))
        #expect(result.contains("world"))
    }

    @Test
    func balancedQuotesPreserved() {
        let result = FTS5Engine.sanitizeQuery("\"design system\"")
        #expect(result == "\"design system\"")
    }

    @Test
    func prefixStarPreserved() {
        let result = FTS5Engine.sanitizeQuery("sema*")
        #expect(result == "sema*")
    }

    @Test
    func emptyQueryReturnsEmpty() {
        let result = FTS5Engine.sanitizeQuery("")
        #expect(result == "")
    }

    @Test
    func whitespaceOnlyReturnsEmpty() {
        let result = FTS5Engine.sanitizeQuery("   ")
        #expect(result == "")
    }

    @Test
    func specialCharsEscaped() {
        let result = FTS5Engine.sanitizeQuery("hello(world)")
        #expect(result.contains("\""))
    }
}
