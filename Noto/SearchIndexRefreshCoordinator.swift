import Foundation
import NotoSearch

actor SearchIndexRefreshCoordinator {
    static let shared = SearchIndexRefreshCoordinator()

    private var runningTasks: [String: Task<SearchIndexRefreshResult, Error>] = [:]

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
            return result
        } catch {
            runningTasks[key] = nil
            throw error
        }
    }
}
