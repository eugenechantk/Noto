/// # Test Index
///
/// ## Caret Rendering
/// - `testEffectiveCaretFontUsesBodyFontForInactiveTodoPrefix`
/// - `testEffectiveCaretFontKeepsVisibleFontForRegularText`
/// - `testEffectiveCaretFontUsesBodyFontAtEndOfFormattedEmptyTodo`

import Testing
import UIKit
@testable import Noto

@Suite("Markdown Editor View")
struct MarkdownEditorViewTests {

    @Test("Effective caret font uses body font for inactive todo prefix")
    func testEffectiveCaretFontUsesBodyFontForInactiveTodoPrefix() {
        let storage = MarkdownTextStorage()
        storage.load(markdown: "- [ ] Task")

        let resolved = effectiveCaretFont(at: 0, in: storage)

        #expect(resolved?.pointSize == MarkdownEditorTheme.bodyFont.pointSize)
    }

    @Test("Effective caret font keeps visible font for regular text")
    func testEffectiveCaretFontKeepsVisibleFontForRegularText() {
        let regularFont = UIFont.systemFont(ofSize: 17)
        let resolved = effectiveCaretFont(from: [.font: regularFont])

        #expect(resolved?.pointSize == regularFont.pointSize)
    }

    @Test("Effective caret font uses body font at end of formatted empty todo")
    func testEffectiveCaretFontUsesBodyFontAtEndOfFormattedEmptyTodo() {
        let storage = MarkdownTextStorage()
        storage.load(markdown: "# Title\n- [ ] ")

        let trailingPrefixFont = storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? UIFont
        let resolved = effectiveCaretFont(at: storage.length, in: storage)

        #expect(trailingPrefixFont?.pointSize == MarkdownEditorTheme.bodyFont.pointSize)
        #expect(resolved?.pointSize == MarkdownEditorTheme.bodyFont.pointSize)
    }
}
