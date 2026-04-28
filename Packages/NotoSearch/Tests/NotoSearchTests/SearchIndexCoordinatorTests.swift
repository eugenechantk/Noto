import Foundation
import Testing
import NotoSearch

@Suite("SearchIndexCoordinator")
struct SearchIndexCoordinatorTests {
    @Test("Refresh uses a single in-flight task per vault")
    func refreshUsesSingleInFlightTaskPerVault() async throws {
        let probe = SearchIndexCoordinatorProbe(refreshDelay: 0.08)
        let coordinator = SearchIndexCoordinator(client: probe.client)
        let vault = try makeTempDirectory("SearchIndexCoordinatorVault")
        defer { removeDirectory(vault) }

        async let first = coordinator.refresh(vaultURL: vault)
        async let second = coordinator.refresh(vaultURL: vault)
        _ = try await (first, second)

        #expect(probe.refreshCallCount == 1)
    }

    @Test("Scheduled file refresh debounces repeated requests")
    func scheduledFileRefreshDebouncesRepeatedRequests() async throws {
        let probe = SearchIndexCoordinatorProbe()
        let coordinator = SearchIndexCoordinator(client: probe.client, scheduledRefreshDelay: .milliseconds(20))
        let vault = try makeTempDirectory("SearchIndexCoordinatorVault")
        defer { removeDirectory(vault) }
        let file = vault.appendingPathComponent("Scratch.md")

        await coordinator.scheduleRefreshFile(vaultURL: vault, fileURL: file)
        await coordinator.scheduleRefreshFile(vaultURL: vault, fileURL: file)
        try await Task.sleep(for: .milliseconds(80))

        #expect(probe.refreshFileCalls == [file.standardizedFileURL.path])
    }

    @Test("Replace removes old file then refreshes new file")
    func replaceRemovesOldFileThenRefreshesNewFile() async throws {
        let probe = SearchIndexCoordinatorProbe()
        let coordinator = SearchIndexCoordinator(client: probe.client)
        let vault = try makeTempDirectory("SearchIndexCoordinatorVault")
        defer { removeDirectory(vault) }
        let oldFile = vault.appendingPathComponent("Old.md")
        let newFile = vault.appendingPathComponent("New.md")

        _ = try await coordinator.replaceFile(vaultURL: vault, oldFileURL: oldFile, newFileURL: newFile)

        #expect(probe.events == [
            "remove:Old.md",
            "refreshFile:New.md",
        ])
    }

    @Test("File operations schedule follow-up work when a full refresh is running")
    func fileOperationsScheduleFollowUpAfterRunningFullRefresh() async throws {
        let probe = SearchIndexCoordinatorProbe(refreshDelay: 0.08)
        let coordinator = SearchIndexCoordinator(client: probe.client)
        let vault = try makeTempDirectory("SearchIndexCoordinatorVault")
        defer { removeDirectory(vault) }
        let file = vault.appendingPathComponent("Edited.md")

        async let refresh = coordinator.refresh(vaultURL: vault)
        try await Task.sleep(for: .milliseconds(15))
        _ = try await coordinator.refreshFile(vaultURL: vault, fileURL: file)
        _ = try await refresh
        try await Task.sleep(for: .milliseconds(80))

        #expect(probe.events.filter { $0 == "refreshFile:Edited.md" }.count == 2)
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
