import Foundation
import Security

protocol ReadwiseTokenStore: Sendable {
    func loadToken() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

protocol ReadwiseBundledTokenProviding: Sendable {
    func bundledToken() -> String?
}

enum ReadwiseSecretStoreError: Error {
    case unexpectedData
    case unhandledStatus(OSStatus)
}

struct BundleReadwiseBundledTokenProvider: ReadwiseBundledTokenProviding {
    private let key = "NotoReadwiseDefaultToken"

    func bundledToken() -> String? {
        if let url = Bundle.main.url(forResource: "ReadwiseDefaultToken", withExtension: "txt"),
           let value = try? String(contentsOf: url, encoding: .utf8),
           let token = normalized(value) {
            return token
        }

        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        return normalized(value)
    }

    private func normalized(_ value: String) -> String? {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains("$(") else {
            return nil
        }
        return token
    }
}

struct KeychainReadwiseTokenStore: ReadwiseTokenStore {
    private let service = "com.noto.readwise"
    private let account = "readwise-token"

    func loadToken() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                throw ReadwiseSecretStoreError.unexpectedData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw ReadwiseSecretStoreError.unhandledStatus(status)
        }
    }

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query
            insert[kSecValueData] = data
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw ReadwiseSecretStoreError.unhandledStatus(insertStatus)
            }
        default:
            throw ReadwiseSecretStoreError.unhandledStatus(updateStatus)
        }
    }

    func deleteToken() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ReadwiseSecretStoreError.unhandledStatus(status)
        }
    }
}
