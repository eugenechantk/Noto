#if os(macOS)
import AppKit
import Testing
@testable import Noto

@Suite("Desktop Markdown rendering") @MainActor
struct MacDesktopRenderingTests {
    @Test func inboxParagraphWrapsNaturallyWithoutChangingMarkdown() throws {
        let text = "Group the home by day, not by folder. One quiet accent, nothing else coloured."
        #expect(MacDesktopInboxWrappingText.plainText(from: text) == text)
        #expect(MacDesktopInboxWrappingText.plainText(from: "**Bold**") == nil)
        #expect(MacDesktopInboxWrappingText.plainText(from: "[Link](https://example.com)") == nil)
        let storage = NSTextStorage(attributedString: MacDesktopInboxWrappingText.attributedText(text))
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 554, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        var lines: [String] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, range, _ in
            let characters = layout.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            lines.append((text as NSString).substring(with: characters).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        #expect(lines == ["Group the home by day, not by folder. One quiet accent, nothing else", "coloured."])
        #expect(storage.string == text)
    }

    @Test func titleMarkupPreservesBackingTextAndEmptyCaretMetrics() throws {
        for text in ["# Title", "# "] {
            let styled = MarkdownParagraphStyler.style(text: text, kind: .heading(level: 1))
            #expect(styled.string == text)
            #expect((styled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == .clear)
            let boundary = try #require(styled.attribute(.font, at: text.utf16.count - 1, effectiveRange: nil) as? NSFont)
            #expect(boundary.pointSize == 30)
            let narrow = MacMarkdownFocusStyle.applyingTitleSize(28, to: styled)
            #expect(narrow.string == text)
            #expect((narrow.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == .clear)
            #expect((narrow.attribute(.font, at: text.utf16.count - 1, effectiveRange: nil) as? NSFont)?.pointSize == 28)
            let normal = MacMarkdownFocusStyle.applyingTitleSize(30, to: styled)
            if text == "# Title" {
                #expect(abs((normal.attribute(.kern, at: 2, effectiveRange: nil) as? Double ?? 0) + 0.45) < 0.0001)
                #expect(abs((narrow.attribute(.kern, at: 2, effectiveRange: nil) as? Double ?? 0) + 0.42) < 0.0001)
            } else {
                #expect(normal.attribute(.kern, at: 1, effectiveRange: nil) == nil)
                #expect(narrow.attribute(.kern, at: 1, effectiveRange: nil) == nil)
            }
            #expect(normal.attribute(.kern, at: 0, effectiveRange: nil) == nil)
        }
    }

    @Test func emptyTodoBoundaryMatchesFilledTodo() throws {
        for text in ["- [ ] ", "- [ ] Work"] {
            let kind = MarkdownBlockKind.detect(from: text)
            let styled = MarkdownParagraphStyler.style(text: text, kind: kind)
            let boundary = try #require(styled.attribute(.font, at: text.utf16.count - 1, effectiveRange: nil) as? NSFont)
            #expect(boundary.pointSize == 15)
            let paragraph = MarkdownParagraphStyler.paragraphStyle(for: kind, text: text)
            let contentX = paragraph.firstLineHeadIndent + MarkdownParagraphStyler.todoHiddenPrefixWidth(for: kind, text: text) + MarkdownParagraphStyler.todoTrailingSpaceWidthCompensation(for: kind, text: text)
            #expect(abs(contentX - MarkdownVisualSpec.todoTextStartOffset) < 0.5)
        }
    }

    @Test func frontmatterSeparatorDoesNotDisplaceDocumentTitle() throws {
        let markdown = "---\nid: 550e8400-e29b-41d4-a716-446655440000\n---\n\n# Title\n"
        let storage = NSTextContentStorage()
        storage.textStorage = NSTextStorage(string: markdown)
        let delegate = MarkdownTextDelegate()
        delegate.frontmatterRange = MarkdownFrontmatter.range(in: markdown)
        let range = (markdown as NSString).range(of: "\n\n")
        let separator = try #require(delegate.textContentStorage(storage, textParagraphWith: NSRange(location: range.location + 1, length: 1)) as? MarkdownParagraph)
        #expect(separator.blockKind == .frontmatter)
        #expect(separator.attributedString.string == "\n")
    }

    @Test func focusRenderingKeepsSourceAndEmptyTitleCaretMetrics() throws {
        for text in ["# Title", "# "] {
            let regular = MarkdownParagraphStyler.style(text: text, kind: .heading(level: 1))
            let focused = MacMarkdownFocusStyle.applying(to: regular, kind: .heading(level: 1), isActive: false)
            #expect(focused.string == text)
            #expect((focused.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == .clear)
            let boundary = try #require(focused.attribute(.font, at: text.utf16.count - 1, effectiveRange: nil) as? NSFont)
            #expect(boundary.pointSize == 32)
            #expect((regular.attribute(.font, at: text.utf16.count - 1, effectiveRange: nil) as? NSFont)?.pointSize == 30)
            if text == "# Title" {
                #expect(abs((focused.attribute(.kern, at: 2, effectiveRange: nil) as? Double ?? 0) + 0.48) < 0.0001)
            } else {
                #expect(focused.attribute(.kern, at: 1, effectiveRange: nil) == nil)
            }
        }
    }
}
#endif
