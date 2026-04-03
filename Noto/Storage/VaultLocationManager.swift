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
    private static let forceLocalVaultArgument = "-notoUseLocalVault"
    private static let resetStateArgument = "-notoResetState"

    init() {
        if Self.shouldResetStateFromLaunchArguments {
            resetStateForUITesting()
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
            return
        }

        // Try resolving a security-scoped bookmark
        guard let bookmarkData = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            isVaultConfigured = false
            return
        }

        do {
            var isStale = false
            #if os(macOS)
            let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #else
            let resolveOptions: URL.BookmarkResolutionOptions = []
            #endif
            let url = try URL(resolvingBookmarkData: bookmarkData, options: resolveOptions, relativeTo: nil, bookmarkDataIsStale: &isStale)

            if isStale {
                // Re-save the bookmark
                if url.startAccessingSecurityScopedResource() {
                    saveBookmark(for: url)
                    url.stopAccessingSecurityScopedResource()
                }
            }

            _ = url.startAccessingSecurityScopedResource()
            let isDirect = UserDefaults.standard.bool(forKey: Self.isDirectKey)
            let resolvedURL = isDirect ? url : url.appendingPathComponent("Noto")
            ensureDirectoryExists(resolvedURL)
            vaultURL = resolvedURL
            isVaultConfigured = true
            logger.info("Resolved vault bookmark at \(resolvedURL.path)")
        } catch {
            logger.error("Failed to resolve vault bookmark: \(error)")
            isVaultConfigured = false
        }
    }

    // MARK: - Set vault location

    /// Set vault to a user-picked parent folder (iCloud, external provider, etc.).
    /// Creates a `Noto/` directory inside the chosen folder.
    func setVault(toParent parentURL: URL) {
        _ = parentURL.startAccessingSecurityScopedResource()
        let notoURL = parentURL.appendingPathComponent("Noto")
        ensureDirectoryExists(notoURL)
        saveBookmark(for: parentURL)
        UserDefaults.standard.set(false, forKey: Self.isLocalKey)
        UserDefaults.standard.set(false, forKey: Self.isDirectKey)
        vaultURL = notoURL
        isVaultConfigured = true
        logger.info("Vault set to \(notoURL.path)")
    }

    /// Set vault directly to the chosen folder (no `/Noto` subfolder).
    /// Use this when pointing at an existing folder of markdown files.
    func setVault(directURL url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        saveBookmark(for: url)
        UserDefaults.standard.set(false, forKey: Self.isLocalKey)
        UserDefaults.standard.set(true, forKey: Self.isDirectKey)
        vaultURL = url
        isVaultConfigured = true
        logger.info("Vault set directly to \(url.path)")
    }

    /// Set vault to local app sandbox Documents/Noto.
    func setLocalVault() {
        let localURL = Self.localVaultURL()
        ensureDirectoryExists(localURL)
        UserDefaults.standard.set(true, forKey: Self.isLocalKey)
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        vaultURL = localURL
        isVaultConfigured = true
        logger.info("Vault set to local: \(localURL.path)")
    }

    /// Resets vault configuration, returning the user to the setup screen.
    func resetVault() {
        vaultURL = nil
        isVaultConfigured = false
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Self.isLocalKey)
        UserDefaults.standard.removeObject(forKey: Self.isDirectKey)
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

    private func resetStateForUITesting() {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }

        let localURL = Self.localVaultURL()
        if FileManager.default.fileExists(atPath: localURL.path) {
            try? FileManager.default.removeItem(at: localURL)
        }
    }
}
