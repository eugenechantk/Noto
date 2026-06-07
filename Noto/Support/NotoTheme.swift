import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Design tokens for the Noto v2 redesign (claude.ai/design "Noto System").
/// Dark-only. Source of truth: `.claude/ios-redesign/component-breakdown.md` §1.
/// Self-contained (own RGB helper) so it doesn't depend on cross-file extensions.
enum NotoTheme {
    private static func rgb(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255.0,
              green: Double((hex >> 8) & 0xFF) / 255.0,
              blue: Double(hex & 0xFF) / 255.0,
              opacity: opacity)
    }

    // MARK: Surfaces & text
    static let background = rgb(0x0E1116)
    static let ink        = rgb(0xECECEE)            // body text
    static let head       = Color.white             // headings / row titles
    static let muted      = Color.white.opacity(0.62)
    static let faint      = rgb(0xECECEE, 0.34)
    static let hairline   = Color.white.opacity(0.10)
    static let accent     = rgb(0xFF6A2E)

    // MARK: Grouped list (properties sheet)
    static let groupedBackground = rgb(0x111419)     // systemGroupedBackground (dark)
    static let card              = rgb(0x1C2027)     // secondarySystemGroupedBackground
    static let separator         = rgb(0x545458, 0.55)
    static let chipFill          = rgb(0x767680, 0.24)

    // MARK: Status / destructive
    static let statusAmber = rgb(0xE6B62A)
    static let destructive = rgb(0xFF3B30)

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
    static let uiBackground = UIColor(red: 0x0E / 255.0, green: 0x11 / 255.0, blue: 0x16 / 255.0, alpha: 1)
    static let uiInk        = UIColor(red: 0xEC / 255.0, green: 0xEC / 255.0, blue: 0xEE / 255.0, alpha: 1)
    static let uiAccent     = UIColor(red: 0xFF / 255.0, green: 0x6A / 255.0, blue: 0x2E / 255.0, alpha: 1)
    #elseif os(macOS)
    static let nsBackground = NSColor(red: 0x0E / 255.0, green: 0x11 / 255.0, blue: 0x16 / 255.0, alpha: 1)
    static let nsInk        = NSColor(red: 0xEC / 255.0, green: 0xEC / 255.0, blue: 0xEE / 255.0, alpha: 1)
    static let nsAccent     = NSColor(red: 0xFF / 255.0, green: 0x6A / 255.0, blue: 0x2E / 255.0, alpha: 1)
    #endif
}
