import Foundation
import Testing
import NotoSearch

@Suite("SearchIndexCoordinator")
struct SearchIndexCoordinatorTests {
    @Test("Refresh uses a single in-flight task per vault")
    func refreshUsesSingleInFlightTaskPerVault() async throws {
        let probe = SearchIndexCoordinatorProbe(refreshDelay: 0.08)
        let vault = try makeTempDirectory("SearchIndexCoordinatorVault")
        defer { removeDirectory(vault) }
        let coordinator = makeCoordinator(client: probe.client, vault: vault)

        async let first = coordinator.refresh(vaultURL: vault)
        async let second = coordinator.refresh(vaultURL: vault)
        _ = try await (first, second)

        #expect(probe.refreshCallCount == 1)
    }

    @Test("Scheduled file refresh debounces repeated requests")
    func scheduledFileRefreshDebouncesRepeatedRequests() async throws {
        let probe = SearchIndexCoordinatorProbe()
        let vault = try makeTempDirectory("SearchIndexCoordinatorVault")
        defer { removeDirectory(vault) }
        let coordinator = makeCoordinator(
            client: probe.client,
            vault: vault,
            scheduledRefreshDelay: .milliseconds(20)
        )
        let file = vault.appendingPathComponent("Scratch.md")

        await coordinator.scheduleRefreshFile(vaultURL: vault, fileURL: file)
        await coordinator.scheduleRefreshFile(vaultURL: vault, fileURL: file)
        try await Task.sleep(for: .milliseconds(120))

        #expect(probe.refreshFileCalls == [file.standardizedFileURL.path])
    }

    @Test("Scheduled refresh enqueues immediately even before the debounced run fires")
    func scheduledRefreshQueuesImmediately() async throws {
        let probe = SearchIndexCoordinatorProbe()
        let vault = try makeTempDirectory("SearchIndexCoordinatorVault")
        defer { removeDirectory(vault) }
        let queueDir = vault
        let coordinator = makeCoordinator(
            client: probe.client,
            vault: vault,
            queueDir: queueDir,
            scheduledRefreshDelay: .seconds(5)
        )
        let file = vault.appendingPathComponent("Pending.md")

        await coordinator.scheduleRefresh(vaultURL: vault, fileURL: file)
        let queue = try PendingIndexQueue(indexDirectory: queueDir)
        let pending = await queue.pending()
        #expect(pending.map(\.url) == [file.standardizedFileURL])
        #expect(pending.first?.action == .refresh)
    }

    @Test("Replace removes old file then refreshes new file")
    func replaceRemovesOldFileThenRefreshesNewFile() async throws {
        let probe = SearchIndexCoordinatorProbe()
        let vault = try makeTempDirectory("SearchIndexCoordinatorVault")
        defer { removeDirectory(vault) }
        let coordinator = makeCoordinator(client: probe.client, vault: vault)
        let oldFile = vault.appendingPathComponent("Old.md")
        let newFile = vault.appendingPathComponent("New.md")

        _ = try await coordinator.replaceFile(vaultURL: vault, oldFileURL: oldFile, newFileURL: newFile)

        #expect(probe.events == [
            "remove:Old.md",
            "refreshFile:New.md",
        ])
    }

    @Test("Per-URL refresh runs once even when a full vault refresh is in flight")
    func perURLRefreshRunsOnceConcurrentWithFullSweep() async throws {
        let probe = SearchIndexCoordinatorProbe(refreshDelay: 0.08)
        let vault = try makeTempDirectory("SearchIndexCoordinatorVault")
        defer { removeDirectory(vault) }
        let coordinator = makeCoordinator(client: probe.client, vault: vault)
        let file = vault.appendingPathComponent("Edited.md")

        async let refresh = coordinator.refresh(vaultURL: vault)
        try await Task.sleep(for: .milliseconds(15))
        _ = try await coordinator.refreshFile(vaultURL: vault, fileURL: file)
        _ = try await refresh
        try await Task.sleep(for: .milliseconds(80))

        // Queue-backed: one immediate per-URL run is sufficient — the file is
        // queued before the SQLite call and consumed only after commit, so we
        // no longer need a follow-up after the full sweep finishes.
        #expect(probe.events.filter { $0 == "refreshFile:Edited.md" }.count == 1)
    }

    @Test("Rebuild clears the queue and runs the rebuild client")
    func rebuildClearsQueueAndRunsRebuildClient() async throws {
        let probe = SearchIndexCoordinatorProbe()
        let vault = try makeTempDirectory("SearchIndexCoordinatorVault")
        defer { removeDirectory(vault) }
        let queueDir = vault
        let coordinator = makeCoordinator(client: probe.client, vault: vault, queueDir: queueDir)

        // Pre-populate the queue with stale work that should NOT run after a rebuild.
        let stale = vault.appendingPathComponent("Stale.md")
        do {
            let queue = try PendingIndexQueue(indexDirectory: queueDir)
            _ = try await queue.enqueue(stale, action: .refresh)
        }

        let result = try await coordinator.rebuildIndex(vaultURL: vault)

        #expect(probe.events == ["rebuild"])
        #expect(result.scanned == 7)
        let queue = try PendingIndexQueue(indexDirectory: queueDir)
        #expect(await queue.pending().isEmpty)
    }

    @Test("Drain replays queued entries from disk after a simulated crash")
    func drainReplaysQueuedEntriesFromDiskAfterCrash() async throws {
        let probe = SearchIndexCoordinatorProbe()
        let vault = try makeTempDirectory("SearchIndexCoordinatorVault")
        defer { removeDirectory(vault) }
        let queueDir = vault
        let leftBehind = vault.appendingPathComponent("Left.md")

        // Simulate a crash: enqueue without consuming, then re-init the
        // coordinator (which sees the queue file on disk).
        do {
            let queue = try PendingIndexQueue(indexDirectory: queueDir)
            _ = try await queue.enqueue(leftBehind, action: .refresh)
        }

        let coordinator = makeCoordinator(client: probe.client, vault: vault, queueDir: queueDir)
        await coordinator.drainPendingQueue(vaultURL: vault)

        #expect(probe.refreshFileCalls == [leftBehind.standardizedFileURL.path])
        let queue = try PendingIndexQueue(indexDirectory: queueDir)
        #expect(await queue.pending().isEmpty)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        client: SearchIndexCoordinatorClient,
        vault: URL,
        queueDir: URL? = nil,
        scheduledRefreshDelay: Duration = .milliseconds(900)
    ) -> SearchIndexCoordinator {
        let resolvedDir = queueDir ?? vault
        return SearchIndexCoordinator(
            client: client,
            scheduledRefreshDelay: scheduledRefreshDelay,
            queueDirectoryProvider: { _ in resolvedDir }
        )
    }
}

private final class SearchIndexCoordinatorProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let refreshDelay: TimeInterval
    private var refreshCalls = 0
    private var refreshFilePaths: [String] = []
    private var recordedEvents: [String] = []

    init(refreshDelay: TimeInterval = 0) {
        self.refreshDelay = refreshDelay
    }

    var client: SearchIndexCoordinatorClient {
        SearchIndexCoordinatorClient(
            refreshChangedFiles: { [self] _ in
                record("refresh")
                if refreshDelay > 0 {
                    Thread.sleep(forTimeInterval: refreshDelay)
                }
                return SearchIndexRefreshResult(
                    scanned: 1,
                    upserted: 1,
                    deleted: 0,
                    stats: SearchIndexStats(noteCount: 1, sectionCount: 1)
                )
            },
            refreshFile: { [self] _, fileURL in
                record("refreshFile:\(fileURL.lastPathComponent)", filePath: fileURL.standardizedFileURL.path)
                return SearchIndexStats(noteCount: 1, sectionCount: 1)
            },
            removeFile: { [self] _, fileURL in
                record("remove:\(fileURL.lastPathComponent)")
                return SearchIndexStats(noteCount: 0, sectionCount: 0)
            },
            rebuildIndex: { [self] _ in
                record("rebuild")
                return SearchIndexRefreshResult(
                    scanned: 7,
                    upserted: 7,
                    deleted: 0,
                    stats: SearchIndexStats(noteCount: 7, sectionCount: 7)
                )
            }
        )
    }

    var refreshCallCount: Int {
        lock.withLock { refreshCalls }
    }

    var refreshFileCalls: [String] {
        lock.withLock { refreshFilePaths }
    }

    var events: [String] {
        lock.withLock { recordedEvents }
    }

    private func record(_ event: String, filePath: String? = nil) {
        lock.withLock {
            if event == "refresh" {
                refreshCalls += 1
            }
            if let filePath {
                refreshFilePaths.append(filePath)
            }
            recordedEvents.append(event)
        }
    }
}
