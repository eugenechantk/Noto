#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Custom NSLayoutManager that draws visual checkbox circles over todo prefix characters.
final class MarkdownLayoutManager: NSLayoutManager {
    func todoCheckboxRect(
        forCharacterRange range: NSRange,
        in textContainer: NSTextContainer,
        origin: CGPoint = .zero
    ) -> CGRect? {
        let glyphRange = glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return nil }

        let lineRect = lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        guard !lineRect.isNull, !lineRect.isEmpty else { return nil }

        let paragraphStyle = textStorage?.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let contentIndent = paragraphStyle?.firstLineHeadIndent ?? 0

        let size = MarkdownTodoCheckboxStyle.size
        return CGRect(
            x: origin.x + contentIndent - size - MarkdownTodoCheckboxStyle.spacing,
            y: origin.y + lineRect.origin.y + (editorBodyLineHeight - size) / 2,
            width: size,
            height: size
        )
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage,
              let textContainer = textContainers.first else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage.enumerateAttribute(MarkdownTodoCheckboxStyle.attributeKey, in: charRange, options: []) { value, attrRange, _ in
            guard let isChecked = value as? Bool else { return }
            guard let drawRect = self.todoCheckboxRect(
                forCharacterRange: attrRange,
                in: textContainer,
                origin: origin
            ) else { return }

            let image = isChecked ? MarkdownTodoCheckboxStyle.checkedImage : MarkdownTodoCheckboxStyle.uncheckedImage
            #if os(iOS)
            image.draw(in: drawRect)
            #elseif os(macOS)
            image.draw(in: drawRect)
            #endif
        }
    }
}

private var editorBodyLineHeight: CGFloat {
    #if os(iOS)
    MarkdownEditorTheme.bodyFont.lineHeight
    #elseif os(macOS)
    MarkdownEditorTheme.bodyFont.ascender - MarkdownEditorTheme.bodyFont.descender + MarkdownEditorTheme.bodyFont.leading
    #endif
}
