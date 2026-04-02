/// # Test Index
///
/// ## Caret Rendering
/// - `testEffectiveCaretFontFallsBackToBodyFontForHiddenTodoPrefix`
/// - `testEffectiveCaretFontKeepsVisibleFontForRegularText`
/// - `testEffectiveCaretFontUsesBodyFontAtEndOfFormattedEmptyTodo`

import Testing
import UIKit
@testable import Noto

@Suite("Markdown Editor View")
struct MarkdownEditorViewTests {

    @Test("Effective caret font falls back to body font for hidden todo prefix")
    func testEffectiveCaretFontFallsBackToBodyFontForHiddenTodoPrefix() {
        let hiddenFont = UIFont.systemFont(ofSize: 0.1)
        let resolved = effectiveCaretFont(from: [.font: hiddenFont])

        #expect(resolved?.pointSize == MarkdownTextStorage.bodyFont.pointSize)
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

        #expect(trailingPrefixFont?.pointSize == 0.1)
        #expect(resolved?.pointSize == MarkdownTextStorage.bodyFont.pointSize)
    }
}
