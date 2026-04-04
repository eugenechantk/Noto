import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "VaultLocationManager")

/// Manages the vault folder location — stores/resolves a security-scoped bookmark
/// so the app can access a user-chosen folder across launches.
@MainActor
@Observable
final class VaultLocationManager {
    var vaultURL: URL?
    var isVaultConfigured: Bool = false

    private static let bookmarkKey = "vaultBookmarkData"
    private static let isLocalKey = "vaultIsLocal"
    private static let isDirectKey = "vaultIsDirect"
    private static let directPathKey = "vaultDirectPath"
    private static let forceLocalVaultArgument = "-notoUseLocalVault"
    private static let forceDirectVaultPathArgument = "-notoDirectVaultPath"
    private static let resetStateArgument = "-notoResetState"

    init() {
        if Self.shouldResetStateFromLaunchArguments {
            resetStateForUITesting()
        }
        if let forcedDirectVaultPath = Self.forcedDirectVaultPathFromLaunchArguments {
            setVaultForUITesting(toDirectPath: forcedDirectVaultPath)
            return
        }
        if Self.shouldForceLocalVaultFromLaunchArguments {
            setLocalVault()
            return
        }
        resolveVault()
    }

    // MARK: - Resolve saved vault

    private func resolveVault() {
        // Check for local vault first
        if UserDefaults.standard.bool(forKey: Self.isLocalKey) {
            let localURL = Self.localVaultURL()
            ensureDirectoryExists(localURL)
            vaultURL = localURL
            isVaultConfigured = true
            logger.info("Using local vault at \(localURL.path)")
            DebugTrace.record("vault resolve local \(localURL.path)")
            return
        }

        // For sandboxed macOS builds, the bookmark is the real access token.
        // Do not prefer a remembered raw path over the bookmark, or we reopen
        // the right folder without the write permission required to save.
        if let bookmarkData = UserDefaults.standard.data(forKey: Self.bookmarkKey) {
            do {
                var isStale = false
                #if os(macOS)
                let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
                #else
                let resolveOptions: URL.BookmarkResolutionOptions = []
                #endif
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: resolveOptions,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                let didStartAccessing = url.startAccessingSecurityScopedResource()
                logger.info("Started security-scoped access: \(didStartAccessing, privacy: .public) for \(url.path)")
                DebugTrace.record("vault bookmark path=\(url.path) startAccess=\(didStartAccessing) stale=\(isStale)")

                guard didStartAccessing else {
                    logger.error("Failed to start security-scoped access for \(url.path)")
                    DebugTrace.record("vault bookmark access denied \(url.path)")
                    clearSavedExternalVaultState()
                    isVaultConfigured = false
                    return
                }

                if isStale, didStartAccessing {
                    saveBookmark(for: url)
                    DebugTrace.record("vault bookmark refreshed \(url.path)")
                }

                let isDirect = UserDefaults.standard.bool(forKey: Self.isDirectKey)
                let resolvedURL = isDirect ? url : url.appendingPathComponent("Noto")
                ensureDirectoryExists(resolvedURL)

                guard validateWriteAccess(to: resolvedURL) else {
                    logger.error("Resolved vault is not writable at \(resolvedURL.path)")
                    DebugTrace.record("vault bookmark not writable \(resolvedURL.path)")
                    url.stopAccessingSecurityScopedResource()
                    clearSavedExternalVaultState()
                    isVaultConfigured = false
                    return
                }

                vaultURL = resolvedURL
                isVaultConfigured = true
                logger.info("Resolved vault bookmark at \(resolvedURL.path)")
                DebugTrace.record("vault resolved bookmark target=\(resolvedURL.path) isDirect=\(isDirect)")
                return
            } catch {
                logger.error("Failed to resolve vault bookmark: \(error)")
                DebugTrace.record("vault bookmark resolve failed \(String(describing: error))")
            }
        }

        // For external macOS vaults, a raw remembered path without an active
        // bookmark is not sufficient to regain write access. Force the user to
        // re-pick the folder instead of opening a read-only vault silently.
        if resolvedDirectVaultURL() != nil {
            logger.error("Saved direct vault path exists but no valid bookmark access is available")
            DebugTrace.record("vault direct path present without valid bookmark; forcing re-pick")
            clearSavedExternalVaultState()
        }

        isVaultConfigured = false
        DebugTrace.record("vault unresolved")
    }

    // MARK: - Set vault location

    /// Set vault to a user-picked parent folder (iCloud, external provider, etc.).
    /// Creates a `Noto/` directory inside the chosen folder.
    func setVault(toParent parentURL: URL) {
        _ = parentURL.startAccessingSecurityScopedResource()
        let notoURL = parentURL.appendingPathComponent("Noto")
        ensureDirectoryExists(notoURL)

        guard validateWriteAccess(to: notoURL) else {
            logger.error("Picked parent vault is not writable at \(notoURL.path)")
            DebugTrace.record("vault set parent denied \(notoURL.path)")
            clearSavedExternalVaultState()
            isVaultConfigured = false
            return
        }

        saveBookmark(for: parentURL)
        UserDefaults.standard.set(false, forKey: Self.isLocalKey)
        UserDefaults.standard.set(false, forKey: Self.isDirectKey)
        UserDefaults.standard.set(notoURL.path, forKey: Self.directPathKey)
        vaultURL = notoURL
        isVaultConfigured = true
        logger.info("Vault set to \(notoURL.path)")
        DebugTrace.record("vault set parent \(notoURL.path)")
    }

    /// Set vault directly to the chosen folder (no `/Noto` subfolder).
    /// Use this when pointing at an existing folder of markdown files.
    func setVault(directURL url: URL) {
        _ = url.startAccessingSecurityScopedResource()

        guard validateWriteAccess(to: url) else {
            logger.error("Picked direct vault is not writable at \(url.path)")
            DebugTrace.record("vault set direct denied \(url.path)")
            clearSavedExternalVaultState()
            isVaultConfigured = false
            return
        }

        saveBookmark(for: url)
        UserDefaults.standard.set(false, forKey: Self.isLocalKey)
        UserDefaults.standard.set(true, forKey: Self.isDirectKey)
        UserDefaults.standard.set(url.path, forKey: Self.directPathKey)
        vaultURL = url
        isVaultConfigured = true
        logger.info("Vault set directly to \(url.path)")
        DebugTrace.record("vault set direct \(url.path)")
    }

    /// Set vault to local app sandbox Documents/Noto.
    func setLocalVault() {
        let localURL = Self.localVaultURL()
        ensureDirectoryExists(localURL)
        UserDefaults.standard.set(true, forKey: Self.isLocalKey)
        UserDefaults.standard.set(false, forKey: Self.isDirectKey)
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Self.directPathKey)
        vaultURL = localURL
        isVaultConfigured = true
        logger.info("Vault set to local: \(localURL.path)")
        DebugTrace.record("vault set local \(localURL.path)")
    }

    /// Resets vault configuration, returning the user to the setup screen.
    func resetVault() {
        vaultURL = nil
        isVaultConfigured = false
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Self.isLocalKey)
        UserDefaults.standard.removeObject(forKey: Self.isDirectKey)
        UserDefaults.standard.removeObject(forKey: Self.directPathKey)
        logger.info("Vault configuration reset")
    }

    // MARK: - Helpers

    private func saveBookmark(for url: URL) {
        do {
            #if os(macOS)
            let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
            #else
            let bookmarkOptions: URL.BookmarkCreationOptions = []
            #endif
            let data = try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        } catch {
            logger.error("Failed to save vault bookmark: \(error)")
        }
    }

    private static var shouldForceLocalVaultFromLaunchArguments: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: forceLocalVaultArgument) else {
            return false
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return true }
        return (arguments[valueIndex] as NSString).boolValue
    }

    private static var shouldResetStateFromLaunchArguments: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: resetStateArgument) else {
            return false
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return true }
        return (arguments[valueIndex] as NSString).boolValue
    }

    private static var forcedDirectVaultPathFromLaunchArguments: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: forceDirectVaultPathArgument) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }

    static func localVaultURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Noto")
    }

    private func ensureDirectoryExists(_ url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func resolvedDirectVaultURL() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: Self.directPathKey), !path.isEmpty else {
            return nil
        }

        let directURL = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directURL.path) else {
            UserDefaults.standard.removeObject(forKey: Self.directPathKey)
            return nil
        }

        return directURL
    }

    private func clearSavedExternalVaultState() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Self.isDirectKey)
        UserDefaults.standard.removeObject(forKey: Self.directPathKey)
        vaultURL = nil
    }

    private func validateWriteAccess(to url: URL) -> Bool {
        let probeURL = url.appendingPathComponent(".noto-write-probe-\(UUID().uuidString)")

        do {
            try Data("probe".utf8).write(to: probeURL, options: .atomic)
            try? FileManager.default.removeItem(at: probeURL)
            DebugTrace.record("vault writable ok \(url.path)")
            return true
        } catch {
            DebugTrace.record("vault writable denied \(url.path) error=\(String(describing: error))")
            try? FileManager.default.removeItem(at: probeURL)
            return false
        }
    }

    private func resetStateForUITesting() {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }

        let localURL = Self.localVaultURL()
        if FileManager.default.fileExists(atPath: localURL.path) {
            try? FileManager.default.removeItem(at: localURL)
        }
    }

    private func setVaultForUITesting(toDirectPath path: String) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        ensureDirectoryExists(url)
        UserDefaults.standard.set(false, forKey: Self.isLocalKey)
        UserDefaults.standard.set(true, forKey: Self.isDirectKey)
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        UserDefaults.standard.set(url.path, forKey: Self.directPathKey)
        vaultURL = url
        isVaultConfigured = true
        logger.info("Using UI-test direct vault at \(url.path)")
    }
}
