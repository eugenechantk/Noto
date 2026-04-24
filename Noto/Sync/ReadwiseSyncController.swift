import Foundation
import NotoReadwiseSyncCore

protocol ReadwiseSyncRunning: Sendable {
    func validate(token: String) async throws
    func syncIncrementally(
        token: String,
        vaultURL: URL,
        syncedAt: Date
    ) async throws -> SourceLibrarySyncResult
}

struct PackageReadwiseSyncRunner: ReadwiseSyncRunning {
    func validate(token: String) async throws {
        try await ReadwiseClient(token: token).validateToken()
    }

    func syncIncrementally(
        token: String,
        vaultURL: URL,
        syncedAt: Date
    ) async throws -> SourceLibrarySyncResult {
        try await SourceLibrarySyncEngine(client: ReadwiseClient(token: token))
            .syncIncrementally(vaultURL: vaultURL, syncedAt: syncedAt)
    }
}

@MainActor
final class ReadwiseSyncController: ObservableObject {
    @Published var tokenInput = ""
    @Published private(set) var hasSavedToken = false
    @Published private(set) var isSyncing = false
    @Published private(set) var tokenStatusMessage = "No Readwise token saved."
    @Published private(set) var syncStatusMessage = "Not synced yet."
    @Published private(set) var lastSyncedAt: Date?

    private let tokenStore: any ReadwiseTokenStore
    private let bundledTokenProvider: any ReadwiseBundledTokenProviding
    private let runner: any ReadwiseSyncRunning
    private var currentSyncTask: Task<Void, Never>?

    init(
        tokenStore: any ReadwiseTokenStore = KeychainReadwiseTokenStore(),
        bundledTokenProvider: any ReadwiseBundledTokenProviding = BundleReadwiseBundledTokenProvider(),
        runner: any ReadwiseSyncRunning = PackageReadwiseSyncRunner()
    ) {
        self.tokenStore = tokenStore
        self.bundledTokenProvider = bundledTokenProvider
        self.runner = runner
        refreshSavedTokenState()
    }

    var canSaveToken: Bool {
        tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var canRunActions: Bool {
        activeToken != nil
    }

    var formattedLastSyncedAt: String? {
        guard let lastSyncedAt else { return nil }
        return Self.formattedSyncTime(lastSyncedAt)
    }

    nonisolated static func formattedSyncTime(
        _ date: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        formatter.locale = locale
        return formatter.string(from: date)
    }

    nonisolated static func lastSyncChangeMessage(for result: SourceLibrarySyncResult) -> String {
        let readerChanges = result.reader.created + result.reader.updated
        let readwiseChanges = result.readwise.created + result.readwise.updated
        return "Last sync: \(readerChanges) Reader \(readerChanges == 1 ? "save" : "saves") and \(readwiseChanges) Readwise \(readwiseChanges == 1 ? "save" : "saves")."
    }

    func refreshSavedTokenState() {
        do {
            let token = try loadOrSeedToken()
            hasSavedToken = token != nil
            if hasSavedToken, tokenStatusMessage == "No Readwise token saved." {
                tokenStatusMessage = "Token saved in secure storage."
            }
        } catch {
            hasSavedToken = false
            tokenStatusMessage = "Could not read the saved token."
        }
    }

    @discardableResult
    func saveToken() -> Bool {
        guard let token = normalizedToken(tokenInput) else {
            tokenStatusMessage = "Enter a Readwise token first."
            return false
        }

        do {
            try tokenStore.saveToken(token)
            tokenInput = ""
            hasSavedToken = true
            tokenStatusMessage = "Token saved in secure storage."
            return true
        } catch {
            tokenStatusMessage = "Could not save the token."
            return false
        }
    }

    func testConnection() {
        guard let token = activeToken else {
            syncStatusMessage = "Set a Readwise token first."
            return
        }
        guard currentSyncTask == nil else { return }

        syncStatusMessage = "Testing Readwise connection..."
        currentSyncTask = Task(priority: .utility) { [runner] in
            do {
                try await runner.validate(token: token)
                await MainActor.run {
                    self.syncStatusMessage = "Readwise connection looks good."
                    self.currentSyncTask = nil
                }
            } catch {
                await MainActor.run {
                    self.syncStatusMessage = "Readwise connection failed."
                    self.currentSyncTask = nil
                }
            }
        }
    }

    func syncNow(vaultURL: URL?) {
        startSync(vaultURL: vaultURL, automatic: false)
    }

    func startAutomaticSync(vaultURL: URL?) {
        startSync(vaultURL: vaultURL, automatic: true)
    }

    private func startSync(vaultURL: URL?, automatic: Bool) {
        guard let vaultURL else {
            if !automatic {
                syncStatusMessage = "Open a vault before syncing."
            }
            return
        }
        guard let token = activeToken else {
            if !automatic {
                syncStatusMessage = "Set a Readwise token first."
            }
            return
        }
        guard currentSyncTask == nil else { return }

        isSyncing = true
        syncStatusMessage = automatic ? "Syncing in background..." : "Syncing..."
        let syncedAt = Date()
        currentSyncTask = Task(priority: .utility) { [runner] in
            do {
                let result = try await runner.syncIncrementally(
                    token: token,
                    vaultURL: vaultURL,
                    syncedAt: syncedAt
                )
                await MainActor.run {
                    self.isSyncing = false
                    self.lastSyncedAt = syncedAt
                    self.syncStatusMessage = Self.lastSyncChangeMessage(for: result)
                    self.currentSyncTask = nil
                }
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                    self.syncStatusMessage = "Sync failed."
                    self.currentSyncTask = nil
                }
            }
        }
    }

    private var activeToken: String? {
        if let token = normalizedToken(tokenInput) {
            return token
        }
        return try? loadOrSeedToken()
    }

    private func loadOrSeedToken() throws -> String? {
        if let storedToken = normalizedToken(try tokenStore.loadToken()) {
            return storedToken
        }
        guard let bundledToken = normalizedToken(bundledTokenProvider.bundledToken()) else {
            return nil
        }
        try tokenStore.saveToken(bundledToken)
        return bundledToken
    }

    private func normalizedToken(_ token: String?) -> String? {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return nil
        }
        return token
    }
}
