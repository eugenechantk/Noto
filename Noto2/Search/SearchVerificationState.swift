import SwiftUI

/// Explicit, Debug-only presentation seams for independent visual checks. They
/// never alter index data, search results, model state, or network policy.
enum SearchVerificationState: String {
    case recentLoading = "recent-loading"
    case recentError = "recent-error"
    case partialIndex = "partial-index"

    static func requested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        #if DEBUG
        guard let value = arguments.first(where: { $0.hasPrefix("--search-preview-state=") })?.split(separator: "=", maxSplits: 1).last else { return nil }
        return Self(rawValue: String(value))
        #else
        return nil
        #endif
    }

    var hidesRecentRows: Bool { self == .recentLoading || self == .recentError }
}
