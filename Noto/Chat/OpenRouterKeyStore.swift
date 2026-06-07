import Foundation
import Security

/// Stores the user's BYO OpenRouter API key in the Keychain.
/// (Proxy-based key delivery may replace this later.)
enum OpenRouterKeyStore {
    private static let service = "com.noto.openrouter"
    private static let account = "api-key"

    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        delete()
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// Shared key-class attributes. `kSecUseDataProtectionKeychain` is required so
    /// macOS uses the modern (iOS-style) data-protection keychain instead of the
    /// legacy file-based keychain — the latter isn't reliably writable from a
    /// sandboxed macOS app, so the key silently failed to persist there.
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    static var hasKey: Bool { load()?.isEmpty == false }
}
