import Foundation
import Testing
import NotoReadwiseSyncCore
@testable import Noto

@Suite("Readwise Sync Controller")
struct ReadwiseSyncControllerTests {
    @Test("Save token writes to secure storage")
    @MainActor
    func saveTokenWritesToSecureStorage() async throws {
        let tokenStore = MockReadwiseTokenStore()
        let runner = MockReadwiseSyncRunner()
        let controller = ReadwiseSyncController(
            tokenStore: tokenStore,
            bundledTokenProvider: MockBundledTokenProvider(),
            runner: runner
        )

        controller.tokenInput = "  readwise-token  "
        controller.saveToken()

        let savedToken = try tokenStore.loadToken()
        #expect(savedToken == "readwise-token")
        #expect(controller.hasSavedToken)
        #expect(controller.tokenInput.isEmpty)
        #expect(controller.tokenStatusMessage == "Token saved in secure storage.")
    }

    @Test("Sync now uses the package runner in background")
    @MainActor
    func syncNowUsesPackageRunner() async throws {
        let tokenStore = MockReadwiseTokenStore(token: "readwise-token")
        let runner = MockReadwiseSyncRunner()
        let controller = ReadwiseSyncController(
            tokenStore: tokenStore,
            bundledTokenProvider: MockBundledTokenProvider(),
            runner: runner
        )
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadwiseSyncControllerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        controller.syncNow(vaultURL: vaultURL)

        await runner.waitForSync()
        await waitForSyncCompletion(controller)

        let syncCalls = await runner.syncCalls
        #expect(syncCalls.count == 1)
        #expect(syncCalls.first?.token == "readwise-token")
        #expect(syncCalls.first?.vaultURL == vaultURL)
        #expect(controller.isSyncing == false)
        #expect(controller.lastSyncedAt != nil)
        #expect(controller.formattedLastSyncedAt != nil)
        #expect(controller.syncStatusMessage == "Last sync: 1 Reader save and 1 Readwise save.")
    }

    @Test("Automatic sync skips when no token exists")
    @MainActor
    func automaticSyncSkipsWithoutToken() async throws {
        let tokenStore = MockReadwiseTokenStore()
        let runner = MockReadwiseSyncRunner()
        let controller = ReadwiseSyncController(
            tokenStore: tokenStore,
            bundledTokenProvider: MockBundledTokenProvider(),
            runner: runner
        )
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadwiseSyncControllerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        controller.startAutomaticSync(vaultURL: vaultURL)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let syncCalls = await runner.syncCalls
        #expect(syncCalls.isEmpty)
        #expect(controller.tokenStatusMessage == "No Readwise token saved.")
        #expect(controller.syncStatusMessage == "Not synced yet.")
    }

    @Test("Bundled token seeds secure storage when Keychain is empty")
    @MainActor
    func bundledTokenSeedsSecureStorageWhenKeychainIsEmpty() throws {
        let tokenStore = MockReadwiseTokenStore()
        let runner = MockReadwiseSyncRunner()
        let controller = ReadwiseSyncController(
            tokenStore: tokenStore,
            bundledTokenProvider: MockBundledTokenProvider(token: "bundled-token"),
            runner: runner
        )

        #expect(try tokenStore.loadToken() == "bundled-token")
        #expect(controller.hasSavedToken)
        #expect(controller.tokenStatusMessage == "Token saved in secure storage.")
    }

    @Test("Bundled token does not overwrite existing secure storage token")
    @MainActor
    func bundledTokenDoesNotOverwriteExistingSecureStorageToken() throws {
        let tokenStore = MockReadwiseTokenStore(token: "existing-token")
        let runner = MockReadwiseSyncRunner()
        _ = ReadwiseSyncController(
            tokenStore: tokenStore,
            bundledTokenProvider: MockBundledTokenProvider(token: "bundled-token"),
            runner: runner
        )

        #expect(try tokenStore.loadToken() == "existing-token")
    }

    @Test("Last sync time formats in the requested timezone")
    func lastSyncTimeFormatsInRequestedTimezone() throws {
        let date = try #require(ISO8601DateFormatter.noto.date(from: "2026-04-24T15:00:00Z"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 8 * 60 * 60))
        let formatted = ReadwiseSyncController.formattedSyncTime(
            date,
            timeZone: timeZone,
            locale: Locale(identifier: "en_US_POSIX")
        )

        #expect(formatted.contains("Apr 24, 2026"))
        #expect(formatted.contains("11:00"))
        #expect(formatted.contains("PM"))
    }

    @Test("Last sync message uses changed saves instead of fetched history")
    func lastSyncMessageUsesChangedSavesInsteadOfFetchedHistory() throws {
        let result = SourceLibrarySyncResult(
            reader: SourceNoteSyncResult(
                created: 1,
                updated: 2,
                skippedDeleted: 0,
                skippedChildDocuments: 0,
                dryRun: false,
                sourceDirectoryURL: URL(fileURLWithPath: "/tmp/Captures", isDirectory: true)
            ),
            readwise: SourceNoteSyncResult(
                created: 0,
                updated: 1,
                skippedDeleted: 0,
                skippedChildDocuments: 0,
                dryRun: false,
                sourceDirectoryURL: URL(fileURLWithPath: "/tmp/Captures", isDirectory: true)
            ),
            fetchedReaderDocuments: 100,
            fetchedReadwiseBooks: 200,
            fetchedJoinedReadwiseBooks: 0,
            readerUpdatedAfter: nil,
            readwiseUpdatedAfter: nil
        )

        let message = ReadwiseSyncController.lastSyncChangeMessage(for: result)

        #expect(message == "Last sync: 3 Reader saves and 1 Readwise save.")
    }

    @MainActor
    private func waitForSyncCompletion(_ controller: ReadwiseSyncController) async {
        for _ in 0..<40 {
            if !controller.isSyncing, controller.lastSyncedAt != nil {
                return
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }
}

private final class MockReadwiseTokenStore: @unchecked Sendable, ReadwiseTokenStore {
    private let lock = NSLock()
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func loadToken() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    func saveToken(_ token: String) throws {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
    }

    func deleteToken() throws {
        lock.lock()
        defer { lock.unlock() }
        token = nil
    }
}

private struct MockBundledTokenProvider: ReadwiseBundledTokenProviding {
    var token: String?

    func bundledToken() -> String? {
        token
    }
}

private actor MockReadwiseSyncRunner: ReadwiseSyncRunning {
    struct SyncCall: Equatable {
        let token: String
        let vaultURL: URL
    }

    private(set) var syncCalls: [SyncCall] = []

    func validate(token: String) async throws {}

    func syncIncrementally(
        token: String,
        vaultURL: URL,
        syncedAt: Date
    ) async throws -> SourceLibrarySyncResult {
        syncCalls.append(SyncCall(token: token, vaultURL: vaultURL))
        return SourceLibrarySyncResult(
            reader: SourceNoteSyncResult(
                created: 0,
                updated: 1,
                skippedDeleted: 0,
                skippedChildDocuments: 0,
                dryRun: false,
                sourceDirectoryURL: vaultURL.appendingPathComponent("Captures", isDirectory: true)
            ),
            readwise: SourceNoteSyncResult(
                created: 1,
                updated: 0,
                skippedDeleted: 0,
                skippedChildDocuments: 0,
                dryRun: false,
                sourceDirectoryURL: vaultURL.appendingPathComponent("Captures", isDirectory: true)
            ),
            fetchedReaderDocuments: 1,
            fetchedReadwiseBooks: 2,
            fetchedJoinedReadwiseBooks: 1,
            readerUpdatedAfter: nil,
            readwiseUpdatedAfter: nil
        )
    }

    func waitForSync() async {
        for _ in 0..<40 {
            if !syncCalls.isEmpty {
                return
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }
}
