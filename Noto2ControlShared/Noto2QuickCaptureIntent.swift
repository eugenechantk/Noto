import Foundation
import Observation

enum Noto2Tab: String, Hashable, Sendable {
    case capture, digest, search, browse
}

enum Noto2LaunchRoute {
    static let quickCaptureURL = URL(string: "noto2://capture")!

    static func tab(for url: URL) -> Noto2Tab? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "noto2",
              components.host == "capture",
              components.path.isEmpty,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }
        return .capture
    }
}

@MainActor
@Observable
final class Noto2LaunchRouter {
    static let shared = Noto2LaunchRouter()

    private(set) var requestedTab: Noto2Tab?
    private(set) var requestRevision = 0

    func request(_ tab: Noto2Tab) {
        requestedTab = tab
        requestRevision &+= 1
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let tab = Noto2LaunchRoute.tab(for: url) else { return false }
        request(tab)
        return true
    }
}
