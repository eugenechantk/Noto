import Foundation
import os.log

private let coordinatorLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.noto.NotoSearch",
    category: "SearchIndexCoordinator"
)

public struct SearchIndexCoordinatorClient: Sendable {
    public var refreshChangedFiles: @Sendable (URL) throws -> SearchIndexRefreshResult
    public var refreshFile: @Sendable (URL, URL) throws -> SearchIndexStats
    public var removeFile: @Sendable (URL, URL) throws -> SearchIndexStats
    /// Deletes the on-disk SQLite store, then rebuilds it from a fresh scan
    /// of the vault. Used by the user-facing "Refresh search index" action
    /// when the incremental path appears stuck or corrupt.
    public var rebuildIndex: @Sendable (URL) throws -> SearchIndexRefreshResult

    public init(
        refreshChangedFiles: @escaping @Sendable (URL) throws -> SearchIndexRefreshResult,
        refreshFile: @escaping @Sendable (URL, URL) throws -> SearchIndexStats,
        removeFile: @escaping @Sendable (URL, URL) throws -> SearchIndexStats,
        rebuildIndex: @escaping @Sendable (URL) throws -> SearchIndexRefreshResult
    ) {
        self.refreshChangedFiles = refreshChangedFiles
        self.refreshFile = refreshFile
        self.removeFile = removeFile
        self.rebuildIndex = rebuildIndex
    }

    public static let live = SearchIndexCoordinatorClient(
        refreshChangedFiles: { vaultURL in
            try MarkdownSearchIndexer(vaultURL: vaultURL).refreshChangedFiles()
        },
        refreshFile: { vaultURL, fileURL in
            try MarkdownSearchIndexer(vaultURL: vaultURL).refreshFile(at: fileURL)
        },
        removeFile: { vaultURL, fileURL in
            try MarkdownSearchIndexer(vaultURL: vaultURL).removeFile(at: fileURL)
        },
        rebuildIndex: { vaultURL in
            let indexer = MarkdownSearchIndexer(vaultURL: vaultURL)
            try indexer.openStore().destroy()
            return try indexer.rebuild()
        }
    )
}

public actor SearchIndexCoordinator {
    public static let shared = SearchIndexCoordinator()

    private let client: SearchIndexCoordinatorClient
    private let scheduledRefreshDelay: Duration
    private let queueDirectoryProvider: @Sendable (URL) -> URL

    private var runningTasks: [String: Task<SearchIndexRefreshResult, Error>] = [:]
    private var scheduledFileTasks: [String: Task<Void, Never>] = [:]
    private var queues: [String: PendingIndexQueue] = [:]

    public init(
        client: SearchIndexCoordinatorClient = .live,
        scheduledRefreshDelay: Duration = .milliseconds(900),
        queueDirectoryProvider: @escaping @Sendable (URL) -> URL = { vaultURL in
            MarkdownSearchIndexer.defaultIndexDirectory(for: vaultURL)
        }
    ) {
        self.client = client
        self.scheduledRefreshDelay = scheduledRefreshDelay
        self.queueDirectoryProvider = queueDirectoryProvider
    }

    // MARK: - Whole-vault sweep

    public func refresh(vaultURL: URL) async throws -> SearchIndexRefreshResult {
        let key = vaultKey(for: vaultURL)
        if let task = runningTasks[key] {
            return try await task.value
        }

        let client = client
        let task = Task.detached(priority: .utility) {
            try client.refreshChangedFiles(vaultURL)
        }
        runningTasks[key] = task

        do {
            let result = try await task.value
            runningTasks[key] = nil
            return result
        } catch {
            runningTasks[key] = nil
            throw error
        }
    }

    // MARK: - Unified per-URL API (queue-backed)

    /// Index (or re-index) one file immediately. Crash-safe: the URL is queued
    /// before the SQLite call and consumed only after commit.
    @discardableResult
    public func refresh(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        try await runQueued(vaultURL: vaultURL, fileURL: fileURL, action: .refresh)
    }

    /// Remove one file from the index immediately. Crash-safe.
    @discardableResult
    public func remove(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        try await runQueued(vaultURL: vaultURL, fileURL: fileURL, action: .delete)
    }

    /// Enqueue an immediate `.refresh` and run it after the debounce window.
    /// The URL is in the queue from the first call, even if the run is delayed
    /// or never happens (cancellation, crash). A burst of calls collapses into
    /// a single run after the last one settles.
    public func scheduleRefresh(
        vaultURL: URL,
        fileURL: URL,
        onRefreshComplete: (@Sendable (URL) async -> Void)? = nil
    ) async {
        do {
            let queue = try queue(for: vaultURL)
            _ = try await queue.enqueue(fileURL, action: .refresh)
        } catch {
            coordinatorLogger.error(
                "scheduleRefresh enqueue failed for \(fileURL.lastPathComponent, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            return
        }

        let key = fileTaskKey(vaultURL: vaultURL, fileURL: fileURL)
        scheduledFileTasks[key]?.cancel()
        let scheduledRefreshDelay = scheduledRefreshDelay
        scheduledFileTasks[key] = Task { [weak self] in
            do {
                try await Task.sleep(for: scheduledRefreshDelay)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                _ = try await self.refresh(vaultURL: vaultURL, fileURL: fileURL)
                if let onRefreshComplete {
                    await onRefreshComplete(vaultURL)
                }
            } catch {
                await self?.clearScheduledFileTask(for: key)
                return
            }
            await self?.clearScheduledFileTask(for: key)
        }
    }

    /// Replay every queued entry for this vault. Run at app launch before any
    /// whole-vault sweep so files the sandbox enumerator can't see still get
    /// indexed via their direct path.
    public func drainPendingQueue(vaultURL: URL) async {
        guard let queue = try? queue(for: vaultURL) else { return }
        let client = client
        await queue.drain { entry in
            switch entry.action {
            case .refresh:
                _ = try client.refreshFile(vaultURL, entry.url)
            case .delete:
                _ = try client.removeFile(vaultURL, entry.url)
            }
        }
    }

    /// Nuke the SQLite index and the pending queue, then re-scan the vault
    /// and rebuild from scratch. Cancels in-flight work for this vault so
    /// the rebuild starts from a clean slate.
    @discardableResult
    public func rebuildIndex(vaultURL: URL) async throws -> SearchIndexRefreshResult {
        let key = vaultKey(for: vaultURL)
        // Cancel anything already running so the rebuild has uncontested
        // access to the index file.
        runningTasks[key]?.cancel()
        runningTasks[key] = nil
        for (taskKey, task) in scheduledFileTasks where taskKey.hasPrefix("\(key)|") {
            task.cancel()
            scheduledFileTasks[taskKey] = nil
        }
        if let queue = try? queue(for: vaultURL) {
            try? await queue.clear()
        }
        // Drop the cached queue so subsequent ops re-init against the fresh
        // (re-created) index directory.
        queues[key] = nil

        let client = client
        let task = Task.detached(priority: .userInitiated) {
            try client.rebuildIndex(vaultURL)
        }
        runningTasks[key] = task
        do {
            let result = try await task.value
            runningTasks[key] = nil
            return result
        } catch {
            runningTasks[key] = nil
            throw error
        }
    }

    // MARK: - Backwards-compatible shims

    @discardableResult
    public func refreshFile(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        try await refresh(vaultURL: vaultURL, fileURL: fileURL)
    }

    public func scheduleRefreshFile(
        vaultURL: URL,
        fileURL: URL,
        onRefreshComplete: (@Sendable (URL) async -> Void)? = nil
    ) async {
        await scheduleRefresh(vaultURL: vaultURL, fileURL: fileURL, onRefreshComplete: onRefreshComplete)
    }

    @discardableResult
    public func removeFile(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        try await remove(vaultURL: vaultURL, fileURL: fileURL)
    }

    @discardableResult
    public func replaceFile(vaultURL: URL, oldFileURL: URL, newFileURL: URL) async throws -> SearchIndexStats {
        _ = try await remove(vaultURL: vaultURL, fileURL: oldFileURL)
        return try await refresh(vaultURL: vaultURL, fileURL: newFileURL)
    }

    // MARK: - Internals

    private func runQueued(
        vaultURL: URL,
        fileURL: URL,
        action: PendingIndexEntry.Action
    ) async throws -> SearchIndexStats {
        let queue = try queue(for: vaultURL)
        let entry = try await queue.enqueue(fileURL, action: action)
        let stats: SearchIndexStats
        switch action {
        case .refresh:
            stats = try client.refreshFile(vaultURL, fileURL)
        case .delete:
            stats = try client.removeFile(vaultURL, fileURL)
        }
        try await queue.consume(entry.id)
        return stats
    }

    private func queue(for vaultURL: URL) throws -> PendingIndexQueue {
        let key = vaultKey(for: vaultURL)
        if let cached = queues[key] { return cached }
        let directory = queueDirectoryProvider(vaultURL)
        let queue = try PendingIndexQueue(indexDirectory: directory)
        queues[key] = queue
        return queue
    }

    private func clearScheduledFileTask(for key: String) {
        scheduledFileTasks[key] = nil
    }

    private func vaultKey(for vaultURL: URL) -> String {
        vaultURL.standardizedFileURL.path
    }

    private func fileTaskKey(vaultURL: URL, fileURL: URL) -> String {
        "\(vaultURL.standardizedFileURL.path)|\(fileURL.standardizedFileURL.path)"
    }
}
