import Foundation
import Testing
@testable import NotoShareCapture

/// Test case index
/// 1. enqueueWritesOneFilePerCapture — each capture is its own `.json` under pending-captures/ and round-trips (SC3)
/// 2. pendingReturnsOldestFirst — listing is ordered by createdAt regardless of write order (SC3)
/// 3. removeDeletesOnlyThatCapture — removing one leaves the others on disk (SC3)
/// 4. corruptFilesAreSkippedNotFatal — a garbage file in the folder does not hide the valid captures (SC3)
/// 5. missingFolderIsEmptyNotError — a store that was never written to lists nothing (SC3)
struct PendingCaptureStoreTests {
    private func makeContainer() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoShareCapture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func enqueueWritesOneFilePerCapture() throws {
        let store = PendingCaptureStore(containerURL: try makeContainer())
        let date = Date(timeIntervalSince1970: 1_787_000_000)
        let first = try store.enqueue(body: "[A](https://a.example)", at: date)
        let second = try store.enqueue(body: "[B](https://b.example)", at: date.addingTimeInterval(1))

        let files = try FileManager.default.contentsOfDirectory(atPath: store.folderURL.path).sorted()
        #expect(files.count == 2)
        #expect(files.allSatisfy { $0.hasSuffix(".json") })
        #expect(store.pending() == [first, second])
    }

    @Test func pendingReturnsOldestFirst() throws {
        let store = PendingCaptureStore(containerURL: try makeContainer())
        let base = Date(timeIntervalSince1970: 1_787_000_000)
        let late = try store.enqueue(body: "late", at: base.addingTimeInterval(60))
        let early = try store.enqueue(body: "early", at: base)
        let middle = try store.enqueue(body: "middle", at: base.addingTimeInterval(30))
        #expect(store.pending().map(\.body) == ["early", "middle", "late"])
        #expect(store.pending() == [early, middle, late])
    }

    @Test func removeDeletesOnlyThatCapture() throws {
        let store = PendingCaptureStore(containerURL: try makeContainer())
        let keep = try store.enqueue(body: "keep")
        let drop = try store.enqueue(body: "drop", at: Date().addingTimeInterval(1))
        store.remove(drop)
        #expect(store.pending() == [keep])
        // Removing twice is harmless.
        store.remove(drop)
        #expect(store.pending() == [keep])
        #expect(!store.isEmpty)
    }

    @Test func corruptFilesAreSkippedNotFatal() throws {
        let store = PendingCaptureStore(containerURL: try makeContainer())
        let valid = try store.enqueue(body: "valid")
        try Data("not json".utf8).write(to: store.folderURL.appendingPathComponent("000-garbage.json"))
        try Data("{}".utf8).write(to: store.folderURL.appendingPathComponent("001-empty.json"))
        try Data("x".utf8).write(to: store.folderURL.appendingPathComponent(".DS_Store"))
        #expect(store.pending() == [valid])
    }

    @Test func missingFolderIsEmptyNotError() throws {
        let store = PendingCaptureStore(containerURL: try makeContainer())
        #expect(store.pending().isEmpty)
        #expect(store.isEmpty)
    }
}
