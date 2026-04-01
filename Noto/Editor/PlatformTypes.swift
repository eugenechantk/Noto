/// Cross-platform typealiases for UIKit / AppKit types used in the editor.
/// NSTextStorage, NSMutableAttributedString, NSLayoutManager, NSTextContainer
/// are shared across both platforms and need no aliasing.

#if os(iOS)
import UIKit

typealias PlatformFont = UIFont
typealias PlatformColor = UIColor

#elseif os(macOS)
import AppKit

typealias PlatformFont = NSFont
typealias PlatformColor = NSColor

extension NSColor {
    /// Bridges UIColor.label → NSColor.labelColor
    static var label: NSColor { .labelColor }

    /// Bridges UIColor.secondaryLabel → NSColor.secondaryLabelColor
    static var secondaryLabel: NSColor { .secondaryLabelColor }

    /// Bridges UIColor.tertiaryLabel → NSColor.tertiaryLabelColor
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }

    /// Bridges UIColor.systemGray3
    static var systemGray3: NSColor { .systemGray }

    /// Bridges UIColor.secondarySystemFill
    static var secondarySystemFill: NSColor {
        NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.3)
    }

    /// Bridges UIColor.systemBackground
    static var systemBackground: NSColor { .textBackgroundColor }
}
#endif
