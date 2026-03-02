//
//  SearchServiceTests.swift
//  NotoTests
//
//  Integration tests for SearchService end-to-end pipeline:
//  dirty tracking -> index flush -> query -> ranked results.
//

import Testing
import Foundation
import SwiftData
import NotoModels
import NotoCore
import NotoFTS5
import NotoDirtyTracker
import NotoSearch
import NotoEmbedding
#if canImport(USearch)
import NotoHNSW
#endif
@testable import Noto

// MARK: - Test Helper

/// Creates a fully wired SearchService for keyword-only integration testing.
@MainActor
private func createTestSearchService() async throws -> (SearchService, ModelContext, DirtyTracker, FTS5Database, DirtyStore, URL) {
    let container = try createTestContainer()
    let context = container.mainContext

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("search-svc-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let db = FTS5Database(directory: tempDir)
    await db.createTablesIfNeeded()

    let store = DirtyStore(directory: tempDir)
    await store.createTablesIfNeeded()

    let tracker = DirtyTracker(dirtyStore: store)
    tracker.cancelIdleTimer()

    #if canImport(USearch)
    let service = SearchService(
        fts5Database: db,
        dirtyTracker: tracker,
        dirtyStore: store,
        modelContext: context,
        embeddingModel: nil,
        hnswIndex: nil,
        vectorKeyStore: nil
    )
    #else
    let service = SearchService(
        fts5Database: db,
        dirtyTracker: tracker,
        dirtyStore: store,
        modelContext: context
    )
    #endif

    return (service, context, tracker, db, store, tempDir)
}

/// Properly cancels timers, closes databases, and cleans up temp directory.
@MainActor
private func teardownSearchService(tracker: DirtyTracker, db: FTS5Database, store: DirtyStore, tempDir: URL) async {
    tracker.cancelIdleTimer()
    await db.close()
    await store.close()
    cleanupTempDir(tempDir)
}

// MARK: - Keyword Search Tests

struct SearchServiceKeywordTests {

    @Test @MainActor
    func keywordSearchFindsBlock() async throws {
        let (service, context, tracker, db, store, tempDir) = try await createTestSearchService()

        let block = Block(content: "quantum computing fundamentals", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        tracker.markDirty(block.id)
        await service.ensureIndexFresh()

        let results = await service.search(rawQuery: "quantum")
        #expect(results.count == 1)
        #expect(results.first?.id == block.id)
        #expect(results.first?.content == "quantum computing fundamentals")

        await teardownSearchService(tracker: tracker, db: db, store: store, tempDir: tempDir)
    }

    @Test @MainActor
    func keywordSearchRespectsDateFilter() async throws {
        let (service, context, tracker, db, store, tempDir) = try await createTestSearchService()

        // Block created today
        let todayBlock = Block(content: "searchable meeting notes", sortOrder: 1.0)
        context.insert(todayBlock)

        // Block created 30 days ago
        let oldBlock = Block(content: "searchable old notes", sortOrder: 2.0)
        context.insert(oldBlock)
        oldBlock.createdAt = Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        try context.save()

        tracker.markDirty(todayBlock.id)
        tracker.markDirty(oldBlock.id)
        await service.ensureIndexFresh()

        let results = await service.search(rawQuery: "searchable today")
        #expect(results.count == 1)
        #expect(results.first?.id == todayBlock.id)

        await teardownSearchService(tracker: tracker, db: db, store: store, tempDir: tempDir)
    }

    @Test @MainActor
    func keywordSearchBreadcrumb() async throws {
        let (service, context, tracker, db, store, tempDir) = try await createTestSearchService()

        let root = Block(content: "Projects", sortOrder: 1.0)
        context.insert(root)

        let parent = Block(content: "Mobile App", parent: root, sortOrder: 1.0)
        context.insert(parent)

        let child = Block(content: "implement authentication flow", parent: parent, sortOrder: 1.0)
        context.insert(child)
        try context.save()

        tracker.markDirty(child.id)
        await service.ensureIndexFresh()

        let results = await service.search(rawQuery: "authentication")
        #expect(results.count == 1)
        #expect(results.first?.breadcrumb == "Home / Mobile App")

        await teardownSearchService(tracker: tracker, db: db, store: store, tempDir: tempDir)
    }

    @Test @MainActor
    func keywordSearchUpdateBlock() async throws {
        let (service, context, tracker, db, store, tempDir) = try await createTestSearchService()

        let block = Block(content: "original placeholder content", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        // Index original content
        tracker.markDirty(block.id)
        await service.ensureIndexFresh()

        let before = await service.search(rawQuery: "placeholder")
        #expect(before.count == 1)

        // Update content
        block.updateContent("revised replacement content")
        try context.save()

        tracker.markDirty(block.id)
        await service.ensureIndexFresh()

        // Old content should no longer match
        let afterOld = await service.search(rawQuery: "placeholder")
        #expect(afterOld.isEmpty)

        // New content should match
        let afterNew = await service.search(rawQuery: "replacement")
        #expect(afterNew.count == 1)
        #expect(afterNew.first?.id == block.id)

        await teardownSearchService(tracker: tracker, db: db, store: store, tempDir: tempDir)
    }

    @Test @MainActor
    func keywordSearchDeleteBlock() async throws {
        let (service, context, tracker, db, store, tempDir) = try await createTestSearchService()

        let block = Block(content: "ephemeral deletable content", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        // Index it
        tracker.markDirty(block.id)
        await service.ensureIndexFresh()

        let before = await service.search(rawQuery: "ephemeral")
        #expect(before.count == 1)

        // Mark deleted and remove from SwiftData
        let blockId = block.id
        tracker.markDeleted(blockId)
        context.delete(block)
        try context.save()

        // Wait for markDeleted async Task to persist
        try await Task.sleep(nanoseconds: 100_000_000)
        await service.ensureIndexFresh()

        let after = await service.search(rawQuery: "ephemeral")
        #expect(after.isEmpty)

        await teardownSearchService(tracker: tracker, db: db, store: store, tempDir: tempDir)
    }

    @Test @MainActor
    func emptyQueryReturnsEmpty() async throws {
        let (service, context, tracker, db, store, tempDir) = try await createTestSearchService()

        let block = Block(content: "some content here", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        tracker.markDirty(block.id)
        await service.ensureIndexFresh()

        let results = await service.search(rawQuery: "")
        #expect(results.isEmpty)

        await teardownSearchService(tracker: tracker, db: db, store: store, tempDir: tempDir)
    }

    @Test @MainActor
    func dateOnlyQueryReturnsBlocksInRange() async throws {
        let (service, context, tracker, db, store, tempDir) = try await createTestSearchService()

        // Two blocks created today
        let block1 = Block(content: "morning standup notes", sortOrder: 1.0)
        context.insert(block1)

        let block2 = Block(content: "afternoon review", sortOrder: 2.0)
        context.insert(block2)

        // One block created 30 days ago
        let oldBlock = Block(content: "ancient history", sortOrder: 3.0)
        context.insert(oldBlock)
        oldBlock.createdAt = Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        try context.save()

        tracker.markDirty(block1.id)
        tracker.markDirty(block2.id)
        tracker.markDirty(oldBlock.id)
        await service.ensureIndexFresh()

        // "today" with no text triggers date-only search
        let results = await service.search(rawQuery: "today")
        #expect(results.count == 2)

        let resultIds = Set(results.map { $0.id })
        #expect(resultIds.contains(block1.id))
        #expect(resultIds.contains(block2.id))
        #expect(!resultIds.contains(oldBlock.id))

        await teardownSearchService(tracker: tracker, db: db, store: store, tempDir: tempDir)
    }
}

// MARK: - Semantic Graceful Degradation Tests

#if canImport(USearch)
struct SearchServiceSemanticTests {

    @Test @MainActor
    func semanticSearchGracefulWithoutModel() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-svc-sem-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let db = FTS5Database(directory: tempDir)
        await db.createTablesIfNeeded()

        let store = DirtyStore(directory: tempDir)
        await store.createTablesIfNeeded()

        let tracker = DirtyTracker(dirtyStore: store)
        tracker.cancelIdleTimer()

        // Pass nil for embeddingModel, hnswIndex, vectorKeyStore
        // SearchService should fall back to keyword-only mode
        let service = SearchService(
            fts5Database: db,
            dirtyTracker: tracker,
            dirtyStore: store,
            modelContext: context,
            embeddingModel: nil,
            hnswIndex: nil,
            vectorKeyStore: nil
        )

        let block = Block(content: "graceful degradation test", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        tracker.markDirty(block.id)
        await service.ensureIndexFresh()

        let results = await service.search(rawQuery: "graceful")
        #expect(results.count == 1)
        #expect(results.first?.id == block.id)

        await teardownSearchService(tracker: tracker, db: db, store: store, tempDir: tempDir)
    }
}
#endif
