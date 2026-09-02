import Combine
import Foundation
import NotoVault

typealias NotoDeepLink = NotoVault.NotoDeepLink

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
