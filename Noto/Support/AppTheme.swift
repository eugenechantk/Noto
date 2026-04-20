import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum AppTheme {
    static let background = Color(hex: 0x0A0A0A)
    static let primaryText = Color(hex: 0xE5E5E5)
    static let secondaryText = Color(hex: 0xD4D4D4)
    static let mutedText = Color(hex: 0x525252)
    static let separator = Color(hex: 0x27272A)

    static let selectedRowBackground = primaryText.opacity(0.12)
    static let pressedBackground = primaryText.opacity(0.08)

    #if os(iOS)
    static let uiBackground = UIColor(hex: 0x0A0A0A)
    static let uiPrimaryText = UIColor(hex: 0xE5E5E5)
    static let uiSecondaryText = UIColor(hex: 0xD4D4D4)
    static let uiMutedText = UIColor(hex: 0x525252)
    static let uiSeparator = UIColor(hex: 0x27272A)
    static let uiCodeBackground = UIColor(hex: 0x27272A).withAlphaComponent(0.55)
    #elseif os(macOS)
    static let nsBackground = NSColor(hex: 0x0A0A0A)
    static let nsPrimaryText = NSColor(hex: 0xE5E5E5)
    static let nsSecondaryText = NSColor(hex: 0xD4D4D4)
    static let nsMutedText = NSColor(hex: 0x525252)
    static let nsSeparator = NSColor(hex: 0x27272A)
    static let nsCodeBackground = NSColor(hex: 0x27272A).withAlphaComponent(0.55)
    #endif
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

#if os(iOS)
extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#elseif os(macOS)
extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif
