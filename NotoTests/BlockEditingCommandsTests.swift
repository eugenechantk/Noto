import Foundation
import Testing
@testable import Noto

@Suite("Block Editing Commands")
struct BlockEditingCommandsTests {

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
}
