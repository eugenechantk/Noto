import Foundation

enum EditorChromeMode {
    case compactNavigation(showsInlineBackButton: Bool)
    case splitClean
    case macToolbar
    /// macOS: the editor's top bar is rendered IN-CONTENT (inside the detail view)
    /// instead of the native window toolbar, so its buttons follow the editor's
    /// right edge — required when a chat sidebar is docked to the right of the editor.
    case macInContent

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
