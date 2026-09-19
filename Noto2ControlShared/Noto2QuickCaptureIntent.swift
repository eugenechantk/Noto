import Foundation
import Observation

enum Noto2Tab: String, Hashable, Sendable {
    case capture, digest, search, browse
}

/// The URLs that open Noto 2 from outside the app. Compiled into the app, the
/// Lock Screen widget, and the share extension so the producers and the parser
/// cannot drift.
enum Noto2LaunchRoute: Equatable {
    /// Open the Capture tab (Lock Screen widget).
    case capture
    /// Open the note Noto 2 files for a share-sheet capture with this staged id.
    case openSharedCapture(id: UUID)

    static let quickCaptureURL = URL(string: "noto2://capture")!
    private static let sharedCaptureQueryName = "shared"

    /// `noto2://capture?shared=<UUID>`
    static func openSharedCaptureURL(id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = "noto2"
        components.host = "capture"
        components.queryItems = [URLQueryItem(name: sharedCaptureQueryName, value: id.uuidString)]
        return components.url!
    }

    /// Deliberately strict: `noto2://capture`, optionally with exactly one
    /// `shared=<UUID>` query item. Anything else is not a route.
    static func route(for url: URL) -> Noto2LaunchRoute? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "noto2",
              components.host == "capture",
              components.path.isEmpty,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil else {
            return nil
        }
        guard let queryItems = components.queryItems, !queryItems.isEmpty else {
            return components.query == nil ? .capture : nil
        }
        guard queryItems.count == 1,
              queryItems[0].name == sharedCaptureQueryName,
              let raw = queryItems[0].value,
              let id = UUID(uuidString: raw) else {
            return nil
        }
        return .openSharedCapture(id: id)
    }

    static func tab(for url: URL) -> Noto2Tab? {
        switch route(for: url) {
        case .capture, .openSharedCapture:
            return .capture
        case nil:
            return nil
        }
    }
}

@MainActor
@Observable
final class Noto2LaunchRouter {
    static let shared = Noto2LaunchRouter()

    private(set) var requestedTab: Noto2Tab?
    /// Set when the latest request came from the share extension's "Add notes"
    /// button; the app drains the staged capture and opens the note it wrote.
    private(set) var requestedSharedCaptureID: UUID?
    private(set) var requestRevision = 0

    func request(_ tab: Noto2Tab) {
        requestedSharedCaptureID = nil
        requestedTab = tab
        requestRevision &+= 1
    }

    func requestSharedCapture(id: UUID) {
        requestedSharedCaptureID = id
        requestedTab = .capture
        requestRevision &+= 1
    }

    /// The app has acted on (or given up on) the shared-capture request.
    func clearSharedCaptureRequest() {
        requestedSharedCaptureID = nil
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        switch Noto2LaunchRoute.route(for: url) {
        case .capture:
            request(.capture)
            return true
        case .openSharedCapture(let id):
            requestSharedCapture(id: id)
            return true
        case nil:
            return false
        }
    }
}
