import Foundation
import Testing
@testable import NotoSearch

@Suite("PendingIndexQueue")
struct PendingIndexQueueTests {
    @Test("Enqueue persists and load round-trips")
    func enqueuePersistsAndLoadRoundTrips() async throws {
        let dir = try makeTempDirectory("PendingIndexQueueTests")
        defer { removeDirectory(dir) }
        let url = dir.appendingPathComponent("Note.md")

        let queue = try PendingIndexQueue(indexDirectory: dir)
        let entry = try await queue.enqueue(url, action: .refresh)
        let pending = await queue.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.id == entry.id)
        #expect(pending.first?.action == .refresh)
        #expect(pending.first?.url == url.standardizedFileURL)

        // Re-init should rehydrate from disk.
        let revived = try PendingIndexQueue(indexDirectory: dir)
        let revivedPending = await revived.pending()
        #expect(revivedPending.map(\.id) == [entry.id])
    }

    @Test("Consume removes entry and persists empty state by removing file")
    func consumeRemovesEntryAndPersistsEmptyState() async throws {
        let dir = try makeTempDirectory("PendingIndexQueueTests")
        defer { removeDirectory(dir) }
        let url = dir.appendingPathComponent("Note.md")

        let queue = try PendingIndexQueue(indexDirectory: dir)
        let entry = try await queue.enqueue(url, action: .delete)
        let queueFile = dir.appendingPathComponent("pending-index.json")
        #expect(FileManager.default.fileExists(atPath: queueFile.path))

        try await queue.consume(entry.id)
        #expect(await queue.pending().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: queueFile.path))

        // Idempotent.
        try await queue.consume(entry.id)
        #expect(await queue.pending().isEmpty)
    }

    @Test("Drain runs handler for each entry and consumes successes")
    func drainRunsHandlerForEachEntryAndConsumesSuccesses() async throws {
        let dir = try makeTempDirectory("PendingIndexQueueTests")
        defer { removeDirectory(dir) }
        let alpha = dir.appendingPathComponent("Alpha.md")
        let beta = dir.appendingPathComponent("Beta.md")

        let queue = try PendingIndexQueue(indexDirectory: dir)
        _ = try await queue.enqueue(alpha, action: .refresh)
        _ = try await queue.enqueue(beta, action: .delete)

        let collector = Collector()
        await queue.drain { entry in
            await collector.append("\(entry.action.rawValue):\(entry.url.lastPathComponent)")
        }

        #expect(await collector.items == [
            "refresh:Alpha.md",
            "delete:Beta.md",
        ])
        #expect(await queue.pending().isEmpty)
    }

    @Test("Drain leaves failed entries in the queue and continues")
    func drainLeavesFailedEntriesInQueueAndContinues() async throws {
        let dir = try makeTempDirectory("PendingIndexQueueTests")
        defer { removeDirectory(dir) }
        let alpha = dir.appendingPathComponent("Alpha.md")
        let beta = dir.appendingPathComponent("Beta.md")
        let gamma = dir.appendingPathComponent("Gamma.md")

        let queue = try PendingIndexQueue(indexDirectory: dir)
        _ = try await queue.enqueue(alpha, action: .refresh)
        let failingEntry = try await queue.enqueue(beta, action: .refresh)
        _ = try await queue.enqueue(gamma, action: .refresh)

        await queue.drain { entry in
            if entry.id == failingEntry.id {
                throw NSError(domain: "Test", code: 1)
            }
        }

        let remaining = await queue.pending()
        #expect(remaining.map(\.id) == [failingEntry.id])
    }

    @Test("Concurrent enqueue keeps every entry on disk")
    func concurrentEnqueueKeepsEveryEntryOnDisk() async throws {
        let dir = try makeTempDirectory("PendingIndexQueueTests")
        defer { removeDirectory(dir) }
        let queue = try PendingIndexQueue(indexDirectory: dir)

        let count = 25
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                let url = dir.appendingPathComponent("Note-\(index).md")
                group.addTask {
                    _ = try? await queue.enqueue(url, action: .refresh)
                }
            }
        }

        let pending = await queue.pending()
        #expect(pending.count == count)

        // Reload from disk and confirm survival.
        let reloaded = try PendingIndexQueue(indexDirectory: dir)
        let reloadedPending = await reloaded.pending()
        #expect(reloadedPending.count == count)
    }

    @Test("Crash simulation: enqueue, skip drain, re-init, drain replays")
    func crashSimulationDrainReplaysQueuedAction() async throws {
        let dir = try makeTempDirectory("PendingIndexQueueTests")
        defer { removeDirectory(dir) }
        let url = dir.appendingPathComponent("Lost.md")

        do {
            let queue = try PendingIndexQueue(indexDirectory: dir)
            _ = try await queue.enqueue(url, action: .refresh)
            // Simulate crash: tear down without consuming.
        }

        let revived = try PendingIndexQueue(indexDirectory: dir)
        let collector = Collector()
        await revived.drain { entry in
            await collector.append(entry.url.lastPathComponent)
        }

        #expect(await collector.items == ["Lost.md"])
        #expect(await revived.pending().isEmpty)
    }
}

private actor Collector {
    private(set) var items: [String] = []

    func append(_ value: String) {
        items.append(value)
    }
}
