import Foundation
import Observation

enum Noto2Tab: String, Hashable, Sendable {
    // Raw values are saved in routes and debug keys, so they keep the old
    // names: `digest` is the Inbox tab and `browse` is the Library tab.
    case capture, today, digest, search, browse

    /// The redesign's tab bar (icons only): four tabs, then Search as the
    /// search-role tab that iOS 26 draws as its own glass circle at the end.
    static let tabBarOrder: [Noto2Tab] = [.capture, .today, .digest, .browse, .search]

    var title: String {
        switch self {
        case .capture: "Capture"
        case .today: "Today"
        case .digest: "Inbox"
        case .browse: "Library"
        case .search: "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .capture: "square.and.pencil"
        case .today: "calendar"
        case .digest: "tray"
        case .browse: "books.vertical"
        case .search: "magnifyingglass"
        }
    }

    var isSearchRole: Bool { self == .search }

    /// Parses a saved raw value. `media` named the Media tab, removed in the
    /// redesign (2026-10-17); it now opens Library rather than failing.
    static func resolving(_ raw: String) -> Noto2Tab? {
        if raw == "media" { return .browse }
        return Noto2Tab(rawValue: raw)
    }
}

/// The URLs that open Noto 2 from outside the app. Compiled into the app, the
/// Lock Screen widget, and the share extension so the producers and the parser
/// cannot drift.
enum Noto2LaunchRoute: Equatable {
    /// Open the Capture tab (Lock Screen widget).
    case capture
    /// Open the note Noto 2 files for a share-sheet capture with this staged id.
    case openSharedCapture(id: UUID)
    /// File this text as a new capture note and open it (Shortcuts / Action button).
    case captureText(String)
    /// Open the note at this vault-relative path (tapping a "Save Quick Capture" notification).
    case openNote(path: String)

    static let quickCaptureURL = URL(string: "noto2://capture")!
    private static let sharedCaptureQueryName = "shared"
    private static let captureTextQueryName = "text"

    /// `noto2://capture?shared=<UUID>`
    static func openSharedCaptureURL(id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = "noto2"
        components.host = "capture"
        components.queryItems = [URLQueryItem(name: sharedCaptureQueryName, value: id.uuidString)]
        return components.url!
    }

    /// `noto2://capture?text=<percent-encoded>`, or nil for blank text. Encodes
    /// everything outside RFC 3986's unreserved set, so `&`, `=`, `+` and `#`
    /// survive inside the value.
    static func captureTextURL(_ text: String) -> URL? {
        guard isCapturable(text),
              let encoded = text.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) else {
            return nil
        }
        return URL(string: "noto2://capture?\(captureTextQueryName)=\(encoded)")
    }

    private static let unreservedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func isCapturable(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `noto2://note?path=<vault-relative path>`, or nil for a path that could escape the vault.
    static func openNoteURL(relativePath: String) -> URL? {
        guard isSafeVaultPath(relativePath),
              let encoded = relativePath.addingPercentEncoding(withAllowedCharacters: unreservedCharacters.union(CharacterSet(charactersIn: "/"))) else {
            return nil
        }
        return URL(string: "noto2://note?path=\(encoded)")
    }

    /// Relative, non-empty, no `..`/`.` segments, and a markdown file — a link can only ever
    /// point at a note inside the vault.
    static func isSafeVaultPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), path.hasSuffix(".md") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// Deliberately strict: `noto2://capture`, optionally with exactly one
    /// `shared=<UUID>` or non-blank `text=<percent-encoded>` query item.
    /// Anything else is not a route. `+` in `text` is a literal plus.
    static func route(for url: URL) -> Noto2LaunchRoute? {
        if let note = noteRoute(for: url) { return note }
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
        guard queryItems.count == 1, let raw = queryItems[0].value else {
            return nil
        }
        switch queryItems[0].name {
        case sharedCaptureQueryName:
            return UUID(uuidString: raw).map { .openSharedCapture(id: $0) }
        case captureTextQueryName:
            return isCapturable(raw) ? .captureText(raw) : nil
        default:
            return nil
        }
    }

    /// `noto2://note?path=…` — exactly one safe `path` item, nothing else.
    private static func noteRoute(for url: URL) -> Noto2LaunchRoute? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == "noto2", c.host == "note", c.path.isEmpty, c.fragment == nil,
              c.user == nil, c.password == nil, c.port == nil,
              let items = c.queryItems, items.count == 1, items[0].name == "path",
              let path = items[0].value, isSafeVaultPath(path) else { return nil }
        return .openNote(path: path)
    }

    static func tab(for url: URL) -> Noto2Tab? {
        switch route(for: url) {
        case .capture, .openSharedCapture, .captureText:
            return .capture
        case .openNote:
            return .browse
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
    /// Set by a `noto2://note?path=` link (a "Save Quick Capture" notification tap).
    private(set) var requestedNotePath: String?
    private(set) var requestRevision = 0

    func request(_ tab: Noto2Tab) {
        requestedSharedCaptureID = nil
        requestedNotePath = nil
        requestedTab = tab
        requestRevision &+= 1
    }

    func requestNote(path: String) {
        requestedSharedCaptureID = nil
        requestedNotePath = path
        requestedTab = .browse
        requestRevision &+= 1
    }

    func clearNoteRequest() {
        requestedNotePath = nil
    }

    func requestSharedCapture(id: UUID) {
        requestedNotePath = nil
        requestedSharedCaptureID = id
        requestedTab = .capture
        requestRevision &+= 1
    }

    /// The app has acted on (or given up on) the shared-capture request.
    func clearSharedCaptureRequest() {
        requestedSharedCaptureID = nil
    }

    /// `stageText` stages a `captureText` link's text for the shared-capture
    /// drain and returns its id, or nil when it could not. It is supplied by
    /// the app (`CaptureTextStager`); the widget and share extension compile
    /// this file without the staging package, so the default stages nothing.
    @discardableResult
    func handle(_ url: URL, stageText: (String) -> UUID? = { _ in nil }) -> Bool {
        switch Noto2LaunchRoute.route(for: url) {
        case .capture:
            request(.capture)
            return true
        case .openSharedCapture(let id):
            requestSharedCapture(id: id)
            return true
        case .captureText(let text):
            // Filed and opened exactly like a share-sheet capture. If it could
            // not be staged, at least land on Capture rather than ignore the link.
            if let id = stageText(text) {
                requestSharedCapture(id: id)
            } else {
                request(.capture)
            }
            return true
        case .openNote(let path):
            requestNote(path: path)
            return true
        case nil:
            return false
        }
    }
}
