import Foundation
import Security

/// Stores the user's BYO OpenRouter API key in the Keychain.
/// (Proxy-based key delivery may replace this later.)
///
/// Mirrors `KeychainReadwiseTokenStore` exactly — the legacy keychain with
/// update-then-add and NO `kSecAttrAccessible` / `kSecUseDataProtectionKeychain`.
/// That's the pattern that already works in this app on macOS; setting
/// `kSecAttrAccessible` (data-protection-only) made `SecItemAdd` fail under the
/// sandbox, so the key silently failed to persist on macOS (worked on iOS).
enum OpenRouterKeyStore {
    private static let service = "com.noto.openrouter"
    private static let account = "api-key"

    private static var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { delete(); return }
        let data = Data(trimmed.utf8)

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var insert = baseQuery
            insert[kSecValueData] = data
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static var hasKey: Bool { load()?.isEmpty == false }
}
