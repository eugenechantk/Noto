import Foundation

public struct SearchIndexCoordinatorClient: Sendable {
    public var refreshChangedFiles: @Sendable (URL) throws -> SearchIndexRefreshResult
    public var refreshFile: @Sendable (URL, URL) throws -> SearchIndexStats
    public var removeFile: @Sendable (URL, URL) throws -> SearchIndexStats

    public init(
        refreshChangedFiles: @escaping @Sendable (URL) throws -> SearchIndexRefreshResult,
        refreshFile: @escaping @Sendable (URL, URL) throws -> SearchIndexStats,
        removeFile: @escaping @Sendable (URL, URL) throws -> SearchIndexStats
    ) {
        self.refreshChangedFiles = refreshChangedFiles
        self.refreshFile = refreshFile
        self.removeFile = removeFile
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
        }
    )
}

public actor SearchIndexCoordinator {
    public static let shared = SearchIndexCoordinator()

    private let client: SearchIndexCoordinatorClient
    private let scheduledRefreshDelay: Duration

    private var runningTasks: [String: Task<SearchIndexRefreshResult, Error>] = [:]
    private var scheduledFileTasks: [String: Task<Void, Never>] = [:]

    public init(
        client: SearchIndexCoordinatorClient = .live,
        scheduledRefreshDelay: Duration = .milliseconds(900)
    ) {
        self.client = client
        self.scheduledRefreshDelay = scheduledRefreshDelay
    }

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

    @discardableResult
    public func refreshFile(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        let followUpRefresh = runningTasks[vaultKey(for: vaultURL)]
        let stats = try client.refreshFile(vaultURL, fileURL)
        scheduleFollowUpFileRefreshIfNeeded(followUpRefresh, vaultURL: vaultURL, fileURL: fileURL)
        return stats
    }

    public func scheduleRefreshFile(
        vaultURL: URL,
        fileURL: URL,
        onRefreshComplete: (@Sendable (URL) async -> Void)? = nil
    ) {
        let key = fileTaskKey(vaultURL: vaultURL, fileURL: fileURL)
        let scheduledRefreshDelay = scheduledRefreshDelay
        scheduledFileTasks[key]?.cancel()
        scheduledFileTasks[key] = Task { [weak self] in
            do {
                guard let self else { return }
                try await Task.sleep(for: scheduledRefreshDelay)
                guard !Task.isCancelled else { return }
                _ = try await self.refreshFile(vaultURL: vaultURL, fileURL: fileURL)
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

    @discardableResult
    public func removeFile(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        let followUpRefresh = runningTasks[vaultKey(for: vaultURL)]
        let stats = try client.removeFile(vaultURL, fileURL)
        scheduleFollowUpFileRemovalIfNeeded(followUpRefresh, vaultURL: vaultURL, fileURL: fileURL)
        return stats
    }

    @discardableResult
    public func replaceFile(vaultURL: URL, oldFileURL: URL, newFileURL: URL) async throws -> SearchIndexStats {
        let followUpRefresh = runningTasks[vaultKey(for: vaultURL)]
        _ = try client.removeFile(vaultURL, oldFileURL)
        let stats = try client.refreshFile(vaultURL, newFileURL)
        scheduleFollowUpFileRefreshIfNeeded(followUpRefresh, vaultURL: vaultURL, fileURL: newFileURL)
        return stats
    }

    private func scheduleFollowUpFileRefreshIfNeeded(
        _ refreshTask: Task<SearchIndexRefreshResult, Error>?,
        vaultURL: URL,
        fileURL: URL
    ) {
        guard let refreshTask else { return }
        let client = client
        Task.detached(priority: .utility) {
            _ = try? await refreshTask.value
            _ = try? client.refreshFile(vaultURL, fileURL)
        }
    }

    private func scheduleFollowUpFileRemovalIfNeeded(
        _ refreshTask: Task<SearchIndexRefreshResult, Error>?,
        vaultURL: URL,
        fileURL: URL
    ) {
        guard let refreshTask else { return }
        let client = client
        Task.detached(priority: .utility) {
            _ = try? await refreshTask.value
            _ = try? client.removeFile(vaultURL, fileURL)
        }
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
