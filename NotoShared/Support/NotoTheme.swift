import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Shared theme API. Noto 2 uses the C canvas palette; Noto keeps its existing palette.
/// Noto 2 reference: `.codex/design/noto2-20261018/boards.json`.
/// Self-contained (own RGB helper) so it doesn't depend on cross-file extensions.
enum NotoTheme {
    private static func rgb(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255.0,
              green: Double((hex >> 8) & 0xFF) / 255.0,
              blue: Double(hex & 0xFF) / 255.0,
              opacity: opacity)
    }

    private static let isNoto2 = Bundle.main.bundleIdentifier?.hasPrefix("com.eugenechan.Noto2") == true

    // MARK: Surfaces & text
    static let background = rgb(isNoto2 ? 0x0F0F10 : 0x0E1116)
    static let ink        = rgb(isNoto2 ? 0xF2F1EE : 0xECECEE)            // body text
    static let head       = (isNoto2 ? rgb(0xF2F1EE) : Color.white) // headings / row titles
    static let muted      = (isNoto2 ? rgb(0xA3A09A) : Color.white.opacity(0.62))
    static let faint      = (isNoto2 ? rgb(0x8C8983) : rgb(0xECECEE, 0.34))
    static let hairline   = Color.white.opacity(0.10)
    static let accent     = rgb(0xFF6A2E)

    // MARK: Grouped list (properties sheet)
    static let groupedBackground = rgb(isNoto2 ? 0x0F0F10 : 0x111419)     // systemGroupedBackground (dark)
    static let card              = rgb(isNoto2 ? 0x1C1C1E : 0x1C2027)     // secondarySystemGroupedBackground
    static let separator         = rgb(0x545458, 0.55)
    static let chipFill          = rgb(0x767680, 0.24)

    // MARK: Status / destructive
    static let statusAmber = rgb(0xE6B62A)
    static let destructive = rgb(isNoto2 ? 0xFF6B5E : 0xFF3B30)

    // MARK: Noto 2 content and Inbox actions
    static let peek = rgb(0x151517)
    static let sheet = rgb(0x161618)
    static let subdued = rgb(0x2A2A2D)
    static let secondaryFill = rgb(0x2C2C2F)
    static let accentText = rgb(0xFF8A5C)
    static let accentSoft = rgb(0x3A2418)
    static let onAccent = rgb(0x1D0D05)
    static let inboxAddTo = rgb(0x6EA8FF)
    static let inboxAddToSoft = rgb(0x16243A)
    static let inboxNewNote = rgb(0x5CC271)
    static let inboxNewNoteSoft = rgb(0x15301D)
    static let inboxLater = rgb(0xE6B62A)
    static let inboxLaterSoft = rgb(0x3A2F12)
    static let inboxDiscard = rgb(0xFF6B5E)
    static let inboxDiscardSoft = rgb(0x3A1B18)
    static let onAction = rgb(0x0B0B0C)

    /// Accent-tinted selection background for the active row.
    static let selectedRowBackground = rgb(0xFF6A2E, 0.12)

    /// iPad sidebar glass tint, painted over a blur — design `rgba(34,38,46,0.55)`.
    static let sidebarGlass = rgb(0x22262E, 0.55)

    // MARK: Type ramp (points)
    enum FontSize {
        static let largeTitle: CGFloat = 33   // file-view large title
        static let noteTitle: CGFloat = 25    // editor note title
        static let h2: CGFloat = 18
        static let body: CGFloat = 16
        static let rowTitle: CGFloat = 16     // list-item title
        static let subtitle: CGFloat = 13     // list-item metadata line
    }

    #if os(iOS)
    static let uiBackground = UIColor(background)
    static let uiInk        = UIColor(ink)
    static let uiAccent     = UIColor(red: 0xFF / 255.0, green: 0x6A / 255.0, blue: 0x2E / 255.0, alpha: 1)
    static let uiCard       = UIColor(card)
    #elseif os(macOS)
    static let nsBackground = NSColor(red: 0x0E / 255.0, green: 0x11 / 255.0, blue: 0x16 / 255.0, alpha: 1)
    static let nsInk        = NSColor(red: 0xEC / 255.0, green: 0xEC / 255.0, blue: 0xEE / 255.0, alpha: 1)
    static let nsAccent     = NSColor(red: 0xFF / 255.0, green: 0x6A / 255.0, blue: 0x2E / 255.0, alpha: 1)
    #endif
}
