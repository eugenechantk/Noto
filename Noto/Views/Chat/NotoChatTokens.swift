import SwiftUI

/// Design tokens for the AI Chat surface, matching the claude.ai/design
/// "Noto AI Chat" system (dark #0E1116 / ink #ECECEE / accent orange #FF6A2E).
/// See `.claude/notochat-ui/component-breakdown.md`.
enum NotoChatTokens {
    static let bg       = Color(hex: 0x0E1116)
    static let ink      = Color(hex: 0xECECEE)
    static let head     = Color.white
    static let faint    = Color(white: 0.93).opacity(0.34)
    static let hairline = Color(white: 0.93).opacity(0.10)
    static let accent   = Color(hex: 0xFF6A2E)
    static let pill     = Color(hex: 0x2C2C2E)
    static let userPill = Color.white.opacity(0.07)
    static let codeFg   = Color(hex: 0xFF6A2E).opacity(0.9)
    static let codeBg   = Color(hex: 0xFF6A2E).opacity(0.12)

    enum Font {
        static func body() -> SwiftUI.Font { .system(size: 16) }
        static func h2() -> SwiftUI.Font { .system(size: 18, weight: .bold) }
        static func secondary() -> SwiftUI.Font { .system(size: 13) }
        static func toolLabel() -> SwiftUI.Font { .system(size: 14) }
        static func eyebrow() -> SwiftUI.Font { .system(size: 11, weight: .semibold) }
    }
}
// Note: `Color(hex: UInt32)` is defined in `Noto/Support/AppTheme.swift`.
