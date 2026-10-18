#if os(macOS)
import AppKit

/// Window-local reading metrics. Source Markdown and hidden insertion boundaries
/// stay unchanged when entering or leaving Focus mode.
enum MacMarkdownFocusStyle {
    static func applyingTitleSize(_ size: CGFloat, to source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        source.enumerateAttribute(.font, in: NSRange(location: 0, length: source.length)) { value, run, _ in
            guard let font = value as? NSFont, font.pointSize > 2 else { return }
            result.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: size) ?? font, range: run)
        }
        applyTitleTracking(size, to: result)
        return result
    }

    private static func applyTitleTracking(_ size: CGFloat, to result: NSMutableAttributedString) {
        let source = NSAttributedString(attributedString: result)
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, run, _ in
            guard let font = attributes[.font] as? NSFont, font.pointSize > 2,
                  let color = attributes[.foregroundColor] as? NSColor, color.alphaComponent > 0 else { return }
            result.addAttribute(.kern, value: -0.015 * size, range: run)
        }
    }

    static func applying(to source: NSAttributedString, kind: MarkdownBlockKind, isActive: Bool) -> NSAttributedString {
        guard !kind.hidesBackingText else { return source }
        let result = NSMutableAttributedString(attributedString: source)
        let range = NSRange(location: 0, length: result.length)
        source.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let font = value as? NSFont, font.pointSize > 2 else { return }
            let size: CGFloat
            switch kind {
            case .heading(1): size = 32
            case .heading(2): size = 19
            default: size = font.pointSize + 2
            }
            result.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: size) ?? font, range: run)
        }
        if case .heading(1) = kind { applyTitleTracking(32, to: result) }
        source.enumerateAttribute(.paragraphStyle, in: range) { value, run, _ in
            guard let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
            style.lineSpacing = 9.75
            // Markdown's separator line already supplies the title's trailing
            // gap; avoid adding a second full margin in the focused column.
            if case .heading(1) = kind { style.paragraphSpacing = -6 }
            if case .paragraph = kind, source.string.trimmingCharacters(in: .newlines).isEmpty {
                style.maximumLineHeight = 22; style.lineSpacing = 0
            }
            result.addAttribute(.paragraphStyle, value: style, range: run)
        }
        if !isActive {
            source.enumerateAttribute(.foregroundColor, in: range) { value, run, _ in
                guard let color = value as? NSColor, color.alphaComponent > 0 else { return }
                result.addAttribute(.foregroundColor, value: color.withAlphaComponent(color.alphaComponent * 0.5), range: run)
            }
        }
        return result
    }
}
#endif
