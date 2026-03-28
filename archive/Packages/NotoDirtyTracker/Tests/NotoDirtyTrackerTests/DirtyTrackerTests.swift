import Foundation
import Testing
import NotoDirtyTracker

private func createTempDirtyStore() async -> (DirtyStore, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("dirty-store-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let store = DirtyStore(directory: tempDir)
    await store.createTablesIfNeeded()
    return (store, tempDir)
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

struct DirtyTrackerPackageTests {
    @Test
    func dirtyStoreBatchLifecycle() async {
        let (store, tempDir) = await createTempDirtyStore()
        defer { cleanup(tempDir) }

        let ids = (0..<10).map { _ in UUID() }
        await store.markDirtyBatch(blockIds: ids, operation: .upsert)
        #expect(await store.dirtyCount() == 10)

        await store.removeDirty(blockIds: Array(ids.prefix(4)))
        #expect(await store.dirtyCount() == 6)

        await store.close()
    }

    @Test @MainActor
    func dirtyTrackerFlushesToStore() async {
        let (store, tempDir) = await createTempDirtyStore()
        defer { cleanup(tempDir) }

        let tracker = DirtyTracker(dirtyStore: store)
        tracker.cancelIdleTimer()

        let id = UUID()
        tracker.markDirty(id)
        await tracker.flush()

        let batch = await store.fetchDirtyBatch(limit: 10)
        #expect(batch.count == 1)
        #expect(batch[0].blockId == id)
        #expect(batch[0].operation == .upsert)

        await store.close()
    }
}
