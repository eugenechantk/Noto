#if canImport(USearch)
import Foundation
import Testing
import NotoHNSW

private func createIndex() async -> (HNSWIndex, VectorKeyStore, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hnsw-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let store = VectorKeyStore(directory: tempDir)
    await store.createTablesIfNeeded()

    let index = HNSWIndex(path: tempDir.appendingPathComponent("vectors.usearch"), vectorKeyStore: store)
    return (index, store, tempDir)
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

struct HNSWPackageTests {
    @Test
    func uuidToKeyIsDeterministic() {
        let id = UUID()
        #expect(HNSWIndex.uuidToKey(id) == HNSWIndex.uuidToKey(id))
    }

    @Test
    func vectorKeyStoreRoundTrip() async {
        let (_, store, tempDir) = await createIndex()
        defer { cleanup(tempDir) }

        let id = UUID()
        let key: UInt64 = 42
        await store.setVectorKey(blockId: id, key: key)

        #expect(await store.getVectorKey(blockId: id) == key)
        #expect(await store.getBlockId(vectorKey: key) == id)

        await store.close()
    }
}
#endif
