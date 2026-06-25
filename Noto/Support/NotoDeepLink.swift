import Combine
import Foundation

enum NotoDeepLink {
    private static let scheme = "noto"
    private static let openHost = "open"

    private static let queryValueAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/?%")
        return allowed
    }()

    static func openURL(vaultRelativePath: String) -> URL? {
        guard let path = validatedVaultRelativePath(vaultRelativePath),
              let encodedPath = path.addingPercentEncoding(withAllowedCharacters: queryValueAllowedCharacters) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = openHost
        components.percentEncodedQuery = "path=\(encodedPath)"
        return components.url
    }

    static func vaultRelativePath(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == openHost else {
            return nil
        }

        let pathItems = (components.queryItems ?? []).filter { $0.name == "path" }
        guard pathItems.count == 1 else { return nil }
        return validatedVaultRelativePath(pathItems[0].value)
    }

    private static func validatedVaultRelativePath(_ path: String?) -> String? {
        guard let path, !path.isEmpty, !path.contains("\0") else { return nil }

        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }

        guard (path as NSString).pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame else {
            return nil
        }

        return path
    }
}

@MainActor
final class NotoDeepLinkRouter: ObservableObject {
    @Published private(set) var pendingDocumentPath: String?

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let path = NotoDeepLink.vaultRelativePath(from: url) else { return false }
        pendingDocumentPath = path
        return true
    }

    func consumePendingDocumentPath() -> String? {
        guard let path = pendingDocumentPath else { return nil }
        pendingDocumentPath = nil
        return path
    }
}
