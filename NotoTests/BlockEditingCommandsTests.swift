import Foundation
import Testing
@testable import Noto

@Suite("Block Editing Commands")
struct BlockEditingCommandsTests {

    @Test("Text edit diff returns the minimal replacement for inserted indentation")
    func textEditDiffFindsInsertedIndentation() {
        let replacement = TextEditDiff.singleReplacement(
            from: "- Item",
            to: "  - Item"
        )

        #expect(replacement == TextReplacement(
            range: NSRange(location: 0, length: 0),
            replacement: "  "
        ))
    }

    @Test("Text edit diff returns the minimal replacement for removed indentation")
    func textEditDiffFindsRemovedIndentation() {
        let replacement = TextEditDiff.singleReplacement(
            from: "  - Item",
            to: "- Item"
        )

        #expect(replacement == TextReplacement(
            range: NSRange(location: 0, length: 2),
            replacement: ""
        ))
    }

    @Test("Indent adds two leading spaces and preserves newline")
    func indentPreservesTrailingNewline() {
        #expect(BlockEditingCommands.indentedLine("Task\n") == "  Task\n")
    }

    @Test("Outdent removes two leading spaces when present")
    func outdentRemovesLeadingSpaces() {
        #expect(BlockEditingCommands.outdentedLine("  Task") == "Task")
    }

    @Test("Outdent removes one leading tab when present")
    func outdentRemovesLeadingTab() {
        #expect(BlockEditingCommands.outdentedLine("\tTask") == "Task")
    }

    @Test("Outdent leaves already flush lines unchanged")
    func outdentLeavesFlushLineUntouched() {
        #expect(BlockEditingCommands.outdentedLine("Task") == "Task")
    }

    @Test("Indent adds markdown indentation to the current line and keeps the cursor with the content")
    func indentCurrentLineAtCursor() {
        let result = BlockEditingCommands.indentedLines(
            in: "Alpha\nBeta",
            selection: NSRange(location: 7, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "Alpha\n  Beta",
            selection: NSRange(location: 9, length: 0)
        ))
    }

    @Test("Indent transforms every selected line and selects the transformed line range")
    func indentSelectedLines() {
        let result = BlockEditingCommands.indentedLines(
            in: "Alpha\nBeta\nGamma",
            selection: NSRange(location: 2, length: 7)
        )

        #expect(result == TextSelectionTransform(
            text: "  Alpha\n  Beta\nGamma",
            selection: NSRange(location: 0, length: 15)
        ))
    }

    @Test("Indenting an ordered item renumbers it as the next child item")
    func indentOrderedItemRenumbersAtChildLevel() {
        let result = BlockEditingCommands.indentedLines(
            in: "1. Parent\n  1. Existing child\n2. New child\n3. Next parent",
            selection: NSRange(location: 31, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "1. Parent\n  1. Existing child\n  2. New child\n2. Next parent",
            selection: NSRange(location: 33, length: 0)
        ))
    }

    @Test("Indenting the first ordered child starts that child level at one")
    func indentFirstOrderedChildStartsAtOne() {
        let result = BlockEditingCommands.indentedLines(
            in: "1. Parent\n2. Child\n3. Next parent",
            selection: NSRange(location: 12, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "1. Parent\n  1. Child\n2. Next parent",
            selection: NSRange(location: 14, length: 0)
        ))
    }

    @Test("Outdent removes markdown indentation from the current line and repositions the cursor")
    func outdentCurrentLineAtCursor() {
        let result = BlockEditingCommands.outdentedLines(
            in: "Alpha\n  Beta",
            selection: NSRange(location: 9, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "Alpha\nBeta",
            selection: NSRange(location: 7, length: 0)
        ))
    }

    @Test("Outdent removes markdown indentation across every selected line")
    func outdentSelectedLines() {
        let result = BlockEditingCommands.outdentedLines(
            in: "  Alpha\n\tBeta\nGamma",
            selection: NSRange(location: 2, length: 10)
        )

        #expect(result == TextSelectionTransform(
            text: "Alpha\nBeta\nGamma",
            selection: NSRange(location: 0, length: 11)
        ))
    }

    @Test("Outdenting an ordered child renumbers it at the parent level")
    func outdentOrderedChildRenumbersAtParentLevel() {
        let result = BlockEditingCommands.outdentedLines(
            in: "1. Parent\n  1. Child\n2. Next parent",
            selection: NSRange(location: 14, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "1. Parent\n2. Child\n3. Next parent",
            selection: NSRange(location: 12, length: 0)
        ))
    }

    @Test("Todo toggle adds markdown todo syntax to the current line and preserves content-relative cursor position")
    func todoToggleAddsTodoPrefix() {
        let result = BlockEditingCommands.toggledTodoLines(
            in: "hello",
            selection: NSRange(location: 5, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "- [ ] hello",
            selection: NSRange(location: 11, length: 0)
        ))
    }

    @Test("Todo toggle on an empty line moves the caret after the inserted prefix")
    func todoToggleOnEmptyLinePlacesCaretAfterPrefix() {
        let result = BlockEditingCommands.toggledTodoLines(
            in: "",
            selection: NSRange(location: 0, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "- [ ] ",
            selection: NSRange(location: 6, length: 0)
        ))
    }

    @Test("Todo toggle removes markdown todo syntax from the current line and preserves content-relative cursor position")
    func todoToggleRemovesTodoPrefix() {
        let result = BlockEditingCommands.toggledTodoLines(
            in: "- [ ] hello",
            selection: NSRange(location: 11, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "hello",
            selection: NSRange(location: 5, length: 0)
        ))
    }

    @Test("Checkbox toggle switches unchecked todo markdown to checked")
    func checkboxToggleChecksTodoLine() {
        #expect(TodoMarkdown.checkboxToggledLine("- [ ] hello") == "- [x] hello")
    }

    @Test("Checkbox toggle switches checked todo markdown to unchecked")
    func checkboxToggleUnchecksTodoLine() {
        #expect(TodoMarkdown.checkboxToggledLine("- [x] hello") == "- [ ] hello")
    }

    @Test("Todo toggle transforms every selected line using markdown todo syntax")
    func todoToggleSelectedLines() {
        let result = BlockEditingCommands.toggledTodoLines(
            in: "Alpha\n- Beta\nGamma",
            selection: NSRange(location: 1, length: 9)
        )

        #expect(result == TextSelectionTransform(
            text: "- [ ] Alpha\n- [ ] Beta\nGamma",
            selection: NSRange(location: 0, length: 23)
        ))
    }

    @Test("Strikethrough wraps selected text in markdown markers")
    func strikethroughWrapsSelection() {
        let result = BlockEditingCommands.toggledStrikethrough(
            in: "hello world",
            selection: NSRange(location: 6, length: 5)
        )

        #expect(result == TextSelectionTransform(
            text: "hello ~~world~~",
            selection: NSRange(location: 8, length: 5)
        ))
    }

    @Test("Strikethrough removes markdown markers when selection is already wrapped")
    func strikethroughUnwrapsWrappedSelection() {
        let result = BlockEditingCommands.toggledStrikethrough(
            in: "hello ~~world~~",
            selection: NSRange(location: 8, length: 5)
        )

        #expect(result == TextSelectionTransform(
            text: "hello world",
            selection: NSRange(location: 6, length: 5)
        ))
    }

    @Test("Strikethrough wraps the word at the cursor when no text is selected")
    func strikethroughWrapsWordAtCursor() {
        let result = BlockEditingCommands.toggledStrikethrough(
            in: "hello world",
            selection: NSRange(location: 8, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "hello ~~world~~",
            selection: NSRange(location: 8, length: 5)
        ))
    }

    @Test("Strikethrough does nothing when cursor is not on or next to a word")
    func strikethroughIgnoresStandaloneWhitespaceCursor() {
        let result = BlockEditingCommands.toggledStrikethrough(
            in: "hello  world",
            selection: NSRange(location: 6, length: 0)
        )

        #expect(result == nil)
    }

    @Test("Bold wraps selected text in markdown markers")
    func boldWrapsSelection() {
        let result = BlockEditingCommands.toggledBold(
            in: "hello world",
            selection: NSRange(location: 6, length: 5)
        )

        #expect(result == TextSelectionTransform(
            text: "hello **world**",
            selection: NSRange(location: 8, length: 5)
        ))
    }

    @Test("Bold removes markdown markers when selection is already wrapped")
    func boldUnwrapsWrappedSelection() {
        let result = BlockEditingCommands.toggledBold(
            in: "hello **world**",
            selection: NSRange(location: 8, length: 5)
        )

        #expect(result == TextSelectionTransform(
            text: "hello world",
            selection: NSRange(location: 6, length: 5)
        ))
    }

    @Test("Italic wraps the word at the cursor")
    func italicWrapsWordAtCursor() {
        let result = BlockEditingCommands.toggledItalic(
            in: "hello world",
            selection: NSRange(location: 8, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "hello *world*",
            selection: NSRange(location: 7, length: 5)
        ))
    }

    @Test("Italic removes markdown markers without unwrapping bold markers")
    func italicUnwrapsOnlyStandaloneItalicMarkers() {
        let italicResult = BlockEditingCommands.toggledItalic(
            in: "hello *world*",
            selection: NSRange(location: 7, length: 5)
        )
        let boldResult = BlockEditingCommands.toggledItalic(
            in: "hello **world**",
            selection: NSRange(location: 8, length: 5)
        )

        #expect(italicResult == TextSelectionTransform(
            text: "hello world",
            selection: NSRange(location: 6, length: 5)
        ))
        #expect(boldResult == TextSelectionTransform(
            text: "hello ***world***",
            selection: NSRange(location: 9, length: 5)
        ))
    }

    @Test("Hyperlink toggle wraps a selected URL in markdown link syntax")
    func hyperlinkToggleWrapsSelectedURL() {
        let result = BlockEditingCommands.toggledHyperlink(
            in: "visit https://example.com",
            selection: NSRange(location: 6, length: 19)
        )

        #expect(result == TextSelectionTransform(
            text: "visit [https://example.com](https://example.com)",
            selection: NSRange(location: 7, length: 19)
        ))
    }

    @Test("Hyperlink toggle wraps the URL at the cursor")
    func hyperlinkToggleWrapsURLAtCursor() {
        let result = BlockEditingCommands.toggledHyperlink(
            in: "visit https://example.com now",
            selection: NSRange(location: 12, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "visit [https://example.com](https://example.com) now",
            selection: NSRange(location: 7, length: 19)
        ))
    }

    @Test("Hyperlink toggle unwraps an existing markdown link to its title")
    func hyperlinkToggleUnwrapsExistingLink() {
        let result = BlockEditingCommands.toggledHyperlink(
            in: "visit [Example](https://example.com)",
            selection: NSRange(location: 7, length: 7)
        )

        #expect(result == TextSelectionTransform(
            text: "visit Example",
            selection: NSRange(location: 6, length: 7)
        ))
    }

    @Test("Hyperlink toggle ignores selected text that is not a URL")
    func hyperlinkToggleIgnoresNonURLSelection() {
        let result = BlockEditingCommands.toggledHyperlink(
            in: "visit Example",
            selection: NSRange(location: 6, length: 7)
        )

        #expect(result == nil)
    }

    @Test("Markdown hyperlinks accept vault-relative note paths")
    func markdownHyperlinksAcceptVaultRelativeNotePaths() {
        let target = HyperlinkMarkdown.target(at: 1, in: "[Project Brief](Folder/Project Brief.md)")

        #expect(target == .vaultDocument(relativePath: "Folder/Project Brief.md"))
    }

    @Test("Page mention detects active query after at-prefix")
    func pageMentionDetectsActiveQuery() {
        let result = PageMentionMarkdown.activeQuery(
            in: "See @Project Br",
            selection: NSRange(location: 15, length: 0)
        )

        #expect(result == PageMentionQuery(
            range: NSRange(location: 4, length: 11),
            query: "Project Br"
        ))
    }

    @Test("Page mention detects empty query after at-prefix")
    func pageMentionDetectsEmptyQuery() {
        let result = PageMentionMarkdown.activeQuery(
            in: "See @",
            selection: NSRange(location: 5, length: 0)
        )

        #expect(result == PageMentionQuery(
            range: NSRange(location: 4, length: 1),
            query: ""
        ))
    }

    @Test("Page mention inserts markdown link with relative path")
    func pageMentionMarkdownUsesRelativePath() {
        let document = PageMentionDocument(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Project Brief",
            relativePath: "Folder/Project Brief.md",
            fileURL: URL(fileURLWithPath: "/tmp/Folder/Project Brief.md")
        )

        #expect(PageMentionMarkdown.markdownLink(for: document) == "[Project Brief](Folder/Project Brief.md)")
    }

    @Test("Return at end of a bullet continues a bullet at the same level")
    func lineBreakContinuesBulletAtSameLevel() {
        let result = BlockEditingCommands.continuedListLineBreak(
            in: "- Parent",
            selection: NSRange(location: 8, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "- Parent\n- ",
            selection: NSRange(location: 11, length: 0)
        ))
    }

    @Test("Return at end of a nested bullet keeps the nested level")
    func lineBreakContinuesNestedBulletAtSameLevel() {
        let result = BlockEditingCommands.continuedListLineBreak(
            in: "  - Child",
            selection: NSRange(location: 9, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "  - Child\n  - ",
            selection: NSRange(location: 14, length: 0)
        ))
    }

    @Test("Return on an empty bullet exits the list")
    func lineBreakOnEmptyBulletExitsList() {
        let result = BlockEditingCommands.continuedListLineBreak(
            in: "- ",
            selection: NSRange(location: 2, length: 0)
        )

        #expect(result == TextSelectionTransform(
            text: "",
            selection: NSRange(location: 0, length: 0)
        ))
    }

    @Test("Return in a paragraph uses default text insertion")
    func lineBreakInParagraphFallsBackToDefaultInsertion() {
        let result = BlockEditingCommands.continuedListLineBreak(
            in: "Paragraph",
            selection: NSRange(location: 9, length: 0)
        )

        #expect(result == nil)
    }
}
