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

    func refresh(vaultURL: URL) async throws -> SearchIndexRefreshResult {
        let result = try await coordinator.refresh(vaultURL: vaultURL)
        await postIndexDidChange(vaultURL: vaultURL)
        return result
    }

    @discardableResult
    func refreshFile(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        let stats = try await coordinator.refreshFile(vaultURL: vaultURL, fileURL: fileURL)
        await postIndexDidChange(vaultURL: vaultURL)
        return stats
    }

    func scheduleRefreshFile(vaultURL: URL, fileURL: URL) {
        Task { [coordinator] in
            await coordinator.scheduleRefreshFile(vaultURL: vaultURL, fileURL: fileURL) { changedVaultURL in
                await Self.postIndexDidChange(vaultURL: changedVaultURL)
            }
        }
    }

    @discardableResult
    func removeFile(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats {
        let stats = try await coordinator.removeFile(vaultURL: vaultURL, fileURL: fileURL)
        await postIndexDidChange(vaultURL: vaultURL)
        return stats
    }

    @discardableResult
    func replaceFile(vaultURL: URL, oldFileURL: URL, newFileURL: URL) async throws -> SearchIndexStats {
        let stats = try await coordinator.replaceFile(vaultURL: vaultURL, oldFileURL: oldFileURL, newFileURL: newFileURL)
        await postIndexDidChange(vaultURL: vaultURL)
        return stats
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
