import Foundation
import NotoSearch

extension Notification.Name {
    static let notoSearchIndexDidChange = Notification.Name("notoSearchIndexDidChange")
}

actor SearchIndexController {
    static let shared = SearchIndexController()

    private let coordinator: NotoSearch.SearchIndexCoordinator

    init(coordinator: NotoSearch.SearchIndexCoordinator = .shared) {
        self.coordinator = coordinator
    }

    /// Whole-vault sweep. Use at app launch and from the file-watcher fallback
    /// when the changed URL isn't known.
    func refresh(vaultURL: URL) async throws -> SearchIndexRefreshResult {
        let result = try await coordinator.refresh(vaultURL: vaultURL)
        await postIndexDidChange(vaultURL: vaultURL)
        return result
    }

    /// Index (or re-index) a single file immediately. Crash-safe via the
    /// coordinator's pending-index queue.
    @discardableResult
    func refresh(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        let stats = try await coordinator.refresh(vaultURL: vaultURL, fileURL: fileURL)
        await postIndexDidChange(vaultURL: vaultURL)
        return stats
    }

    /// Remove a single file from the index immediately. Crash-safe.
    @discardableResult
    func remove(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        let stats = try await coordinator.remove(vaultURL: vaultURL, fileURL: fileURL)
        await postIndexDidChange(vaultURL: vaultURL)
        return stats
    }

    /// Enqueue a `.refresh` immediately and run it after the debounce window.
    /// A burst of edits in the editor collapses to one indexer run.
    func scheduleRefresh(vaultURL: URL, fileURL: URL) {
        Task { [coordinator] in
            await coordinator.scheduleRefresh(vaultURL: vaultURL, fileURL: fileURL) { changedVaultURL in
                await Self.postIndexDidChange(vaultURL: changedVaultURL)
            }
        }
    }

    /// Replay every pending entry persisted on disk for this vault. Run at
    /// app launch *before* the whole-vault sweep so files the sandbox
    /// enumerator can't see still get indexed via their direct path.
    func drainPendingQueue(vaultURL: URL) async {
        await coordinator.drainPendingQueue(vaultURL: vaultURL)
        await postIndexDidChange(vaultURL: vaultURL)
    }

    /// Nuke the on-disk SQLite store + pending queue, then re-scan the vault
    /// from scratch. Exposed via Settings as "Refresh search index" — use as
    /// a recovery hatch when something goes wrong with the incremental path.
    @discardableResult
    func rebuildIndex(vaultURL: URL) async throws -> SearchIndexRefreshResult {
        let result = try await coordinator.rebuildIndex(vaultURL: vaultURL)
        await postIndexDidChange(vaultURL: vaultURL)
        return result
    }

    // MARK: - Backwards-compatible shims for in-app call sites

    @discardableResult
    func refreshFile(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        try await refresh(vaultURL: vaultURL, fileURL: fileURL)
    }

    func scheduleRefreshFile(vaultURL: URL, fileURL: URL) {
        scheduleRefresh(vaultURL: vaultURL, fileURL: fileURL)
    }

    @discardableResult
    func removeFile(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        try await remove(vaultURL: vaultURL, fileURL: fileURL)
    }

    @discardableResult
    func replaceFile(vaultURL: URL, oldFileURL: URL, newFileURL: URL) async throws -> SearchIndexStats {
        _ = try await remove(vaultURL: vaultURL, fileURL: oldFileURL)
        return try await refresh(vaultURL: vaultURL, fileURL: newFileURL)
    }

    private func postIndexDidChange(vaultURL: URL) async {
        await Self.postIndexDidChange(vaultURL: vaultURL)
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
