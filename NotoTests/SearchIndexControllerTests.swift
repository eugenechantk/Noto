import Foundation
import Testing
import NotoSearch
@testable import Noto

@Suite("SearchIndexController")
@MainActor
struct SearchIndexControllerTests {
    @Test("Refresh publishes app notification for the changed vault")
    func refreshPublishesNotification() async throws {
        let probe = AppSearchIndexProbe()
        let packageCoordinator = NotoSearch.SearchIndexCoordinator(client: probe.client)
        let controller = SearchIndexController(coordinator: packageCoordinator)
        let vault = try SearchIndexControllerTestFixture.makeTempDirectory()
        defer { SearchIndexControllerTestFixture.removeDirectory(vault) }

        let recorder = SearchIndexNotificationRecorder()
        defer { recorder.stop() }

        _ = try await controller.refresh(vaultURL: vault)
        try await Task.sleep(for: .milliseconds(40))

        #expect(recorder.vaultPaths == [vault.standardizedFileURL.path])
    }

    @Test("Scheduled file refresh publishes after package debounce completes")
    func scheduledRefreshPublishesAfterDebounce() async throws {
        let probe = AppSearchIndexProbe()
        let packageCoordinator = NotoSearch.SearchIndexCoordinator(
            client: probe.client,
            scheduledRefreshDelay: .milliseconds(20)
        )
        let controller = SearchIndexController(coordinator: packageCoordinator)
        let vault = try SearchIndexControllerTestFixture.makeTempDirectory()
        defer { SearchIndexControllerTestFixture.removeDirectory(vault) }
        let file = vault.appendingPathComponent("Delayed.md")

        let recorder = SearchIndexNotificationRecorder()
        defer { recorder.stop() }

        await controller.scheduleRefreshFile(vaultURL: vault, fileURL: file)
        #expect(recorder.vaultPaths.isEmpty)
        try await Task.sleep(for: .milliseconds(80))

        #expect(probe.events == ["refreshFile:Delayed.md"])
        #expect(recorder.vaultPaths == [vault.standardizedFileURL.path])
    }

    @Test("Replace and remove operations publish app notifications")
    func replaceAndRemovePublishNotifications() async throws {
        let probe = AppSearchIndexProbe()
        let packageCoordinator = NotoSearch.SearchIndexCoordinator(client: probe.client)
        let controller = SearchIndexController(coordinator: packageCoordinator)
        let vault = try SearchIndexControllerTestFixture.makeTempDirectory()
        defer { SearchIndexControllerTestFixture.removeDirectory(vault) }
        let oldFile = vault.appendingPathComponent("Old.md")
        let newFile = vault.appendingPathComponent("New.md")

        let recorder = SearchIndexNotificationRecorder()
        defer { recorder.stop() }

        _ = try await controller.replaceFile(vaultURL: vault, oldFileURL: oldFile, newFileURL: newFile)
        _ = try await controller.removeFile(vaultURL: vault, fileURL: newFile)
        try await Task.sleep(for: .milliseconds(40))

        #expect(probe.events == [
            "remove:Old.md",
            "refreshFile:New.md",
            "remove:New.md",
        ])
        #expect(recorder.vaultPaths == [
            vault.standardizedFileURL.path,
            vault.standardizedFileURL.path,
        ])
    }
}

private final class AppSearchIndexProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [String] = []

    var client: SearchIndexCoordinatorClient {
        SearchIndexCoordinatorClient(
            refreshChangedFiles: { [self] _ in
                record("refresh")
                return SearchIndexRefreshResult(
                    scanned: 1,
                    upserted: 1,
                    deleted: 0,
                    stats: SearchIndexStats(noteCount: 1, sectionCount: 1)
                )
            },
            refreshFile: { [self] _, fileURL in
                record("refreshFile:\(fileURL.lastPathComponent)")
                return SearchIndexStats(noteCount: 1, sectionCount: 1)
            },
            removeFile: { [self] _, fileURL in
                record("remove:\(fileURL.lastPathComponent)")
                return SearchIndexStats(noteCount: 0, sectionCount: 0)
            }
        )
    }

    var events: [String] {
        lock.withLock { recordedEvents }
    }

    private func record(_ event: String) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }
}

@MainActor
private final class SearchIndexNotificationRecorder {
    private var observer: NSObjectProtocol?
    private(set) var vaultPaths: [String] = []

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .notoSearchIndexDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let vaultPath = notification.userInfo?["vaultPath"] as? String else { return }
            self?.vaultPaths.append(vaultPath)
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
}

private enum SearchIndexControllerTestFixture {
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoSearchController-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func removeDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
