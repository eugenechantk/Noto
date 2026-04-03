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
}
