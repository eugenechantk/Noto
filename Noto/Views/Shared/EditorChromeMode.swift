import Foundation

enum EditorChromeMode {
    case compactNavigation(showsInlineBackButton: Bool)
    case splitClean
    case macToolbar

    static var platformDefault: EditorChromeMode {
        #if os(macOS)
        .macToolbar
        #else
        .compactNavigation(showsInlineBackButton: true)
        #endif
    }
}

struct EditorLeadingChromeControls {
    var sidebarSystemImage: String?
    var sidebarAccessibilityLabel: String?
    var onToggleSidebar: (() -> Void)?
    var showsBackButton = false
    var onBack: (() -> Void)?

    static let none = EditorLeadingChromeControls()

    var isEmpty: Bool {
        onToggleSidebar == nil && (!showsBackButton || onBack == nil)
    }
}
