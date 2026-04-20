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
