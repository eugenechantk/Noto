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

    init() {
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
            let url = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)

            if isStale {
                // Re-save the bookmark
                if url.startAccessingSecurityScopedResource() {
                    saveBookmark(for: url)
                    url.stopAccessingSecurityScopedResource()
                }
            }

            _ = url.startAccessingSecurityScopedResource()
            let notoURL = url.appendingPathComponent("Noto")
            ensureDirectoryExists(notoURL)
            vaultURL = notoURL
            isVaultConfigured = true
            logger.info("Resolved vault bookmark at \(notoURL.path)")
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
        vaultURL = notoURL
        isVaultConfigured = true
        logger.info("Vault set to \(notoURL.path)")
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

    // MARK: - Helpers

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        } catch {
            logger.error("Failed to save vault bookmark: \(error)")
        }
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
}
