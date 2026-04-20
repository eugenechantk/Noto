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
