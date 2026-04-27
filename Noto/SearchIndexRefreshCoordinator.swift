import Foundation
import NotoSearch

extension Notification.Name {
    static let notoSearchIndexDidChange = Notification.Name("notoSearchIndexDidChange")
}

actor SearchIndexRefreshCoordinator {
    static let shared = SearchIndexRefreshCoordinator()

    private var runningTasks: [String: Task<SearchIndexRefreshResult, Error>] = [:]
    private var scheduledFileTasks: [String: Task<Void, Never>] = [:]

    func refresh(vaultURL: URL) async throws -> SearchIndexRefreshResult {
        let key = vaultURL.standardizedFileURL.path
        if let task = runningTasks[key] {
            return try await task.value
        }

        let task = Task.detached(priority: .utility) {
            let indexer = MarkdownSearchIndexer(vaultURL: vaultURL)
            return try indexer.refreshChangedFiles()
        }
        runningTasks[key] = task

        do {
            let result = try await task.value
            runningTasks[key] = nil
            await postIndexDidChange(vaultURL: vaultURL)
            return result
        } catch {
            runningTasks[key] = nil
            throw error
        }
    }

    @discardableResult
    func refreshFile(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        let followUpRefresh = runningTasks[vaultURL.standardizedFileURL.path]
        let indexer = MarkdownSearchIndexer(vaultURL: vaultURL)
        let stats = try indexer.refreshFile(at: fileURL)
        await postIndexDidChange(vaultURL: vaultURL)
        scheduleFollowUpFileRefreshIfNeeded(followUpRefresh, vaultURL: vaultURL, fileURL: fileURL)
        return stats
    }

    func scheduleRefreshFile(vaultURL: URL, fileURL: URL) {
        let key = fileTaskKey(vaultURL: vaultURL, fileURL: fileURL)
        scheduledFileTasks[key]?.cancel()
        scheduledFileTasks[key] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                _ = try await SearchIndexRefreshCoordinator.shared.refreshFile(vaultURL: vaultURL, fileURL: fileURL)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            await self?.clearScheduledFileTask(for: key)
        }
    }

    @discardableResult
    func removeFile(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        let followUpRefresh = runningTasks[vaultURL.standardizedFileURL.path]
        let indexer = MarkdownSearchIndexer(vaultURL: vaultURL)
        let stats = try indexer.removeFile(at: fileURL)
        await postIndexDidChange(vaultURL: vaultURL)
        scheduleFollowUpFileRemovalIfNeeded(followUpRefresh, vaultURL: vaultURL, fileURL: fileURL)
        return stats
    }

    @discardableResult
    func replaceFile(vaultURL: URL, oldFileURL: URL, newFileURL: URL) async throws -> SearchIndexStats {
        let followUpRefresh = runningTasks[vaultURL.standardizedFileURL.path]
        let indexer = MarkdownSearchIndexer(vaultURL: vaultURL)
        _ = try indexer.removeFile(at: oldFileURL)
        let stats = try indexer.refreshFile(at: newFileURL)
        await postIndexDidChange(vaultURL: vaultURL)
        scheduleFollowUpFileRefreshIfNeeded(followUpRefresh, vaultURL: vaultURL, fileURL: newFileURL)
        return stats
    }

    private func scheduleFollowUpFileRefreshIfNeeded(
        _ refreshTask: Task<SearchIndexRefreshResult, Error>?,
        vaultURL: URL,
        fileURL: URL
    ) {
        guard let refreshTask else { return }
        Task.detached(priority: .utility) {
            _ = try? await refreshTask.value
            _ = try? MarkdownSearchIndexer(vaultURL: vaultURL).refreshFile(at: fileURL)
            await SearchIndexRefreshCoordinator.postIndexDidChange(vaultURL: vaultURL)
        }
    }

    private func scheduleFollowUpFileRemovalIfNeeded(
        _ refreshTask: Task<SearchIndexRefreshResult, Error>?,
        vaultURL: URL,
        fileURL: URL
    ) {
        guard let refreshTask else { return }
        Task.detached(priority: .utility) {
            _ = try? await refreshTask.value
            _ = try? MarkdownSearchIndexer(vaultURL: vaultURL).removeFile(at: fileURL)
            await SearchIndexRefreshCoordinator.postIndexDidChange(vaultURL: vaultURL)
        }
    }

    private func postIndexDidChange(vaultURL: URL) async {
        await Self.postIndexDidChange(vaultURL: vaultURL)
    }

    private func clearScheduledFileTask(for key: String) {
        scheduledFileTasks[key] = nil
    }

    private func fileTaskKey(vaultURL: URL, fileURL: URL) -> String {
        "\(vaultURL.standardizedFileURL.path)|\(fileURL.standardizedFileURL.path)"
    }

    private static func postIndexDidChange(vaultURL: URL) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .notoSearchIndexDidChange,
                object: nil,
                userInfo: ["vaultPath": vaultURL.standardizedFileURL.path]
            )
        }
    }
}
