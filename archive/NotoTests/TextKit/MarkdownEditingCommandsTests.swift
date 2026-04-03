/// # Test Index
///
/// ## Editing Commands
/// - `testLineBreakActionContinuesTodoBulletAndOrderedLists`
/// - `testLineBreakActionExitsEmptyTodoBulletAndOrderedLists`
/// - `testIndentAndOutdentPreserveContentAndLineEndings`
/// - `testToolbarToggleConvertsPlainBulletAndOrderedLinesIntoTodos`
/// - `testCheckboxToggleSwitchesTodoStateAndLeavesNonTodosUnchanged`

import Testing
@testable import Noto

@Suite("Markdown Editing Commands")
struct MarkdownEditingCommandsTests {

    @Test("Line break action continues todo, bullet, and ordered lists")
    func testLineBreakActionContinuesTodoBulletAndOrderedLists() {
        #expect(MarkdownEditingCommands.lineBreakAction(for: "- [ ] Task\n") == .insert("\n- [ ] "))
        #expect(MarkdownEditingCommands.lineBreakAction(for: "  - Bullet\n") == .insert("\n  - "))
        #expect(MarkdownEditingCommands.lineBreakAction(for: "  3. Ordered\n") == .insert("\n  4. "))
        #expect(MarkdownEditingCommands.lineBreakAction(for: "Plain text\n") == .none)
    }

    @Test("Line break action exits empty todo, bullet, and ordered lists")
    func testLineBreakActionExitsEmptyTodoBulletAndOrderedLists() {
        #expect(MarkdownEditingCommands.lineBreakAction(for: "- [ ] \n") == .removeCurrentLinePrefix(prefixLength: 6))
        #expect(MarkdownEditingCommands.lineBreakAction(for: "  - \n") == .removeCurrentLinePrefix(prefixLength: 4))
        #expect(MarkdownEditingCommands.lineBreakAction(for: "  9. \n") == .removeCurrentLinePrefix(prefixLength: 5))
    }

    @Test("Indent and outdent preserve content and line endings")
    func testIndentAndOutdentPreserveContentAndLineEndings() {
        #expect(MarkdownEditingCommands.indentedLine("Task\n") == "  Task\n")
        #expect(MarkdownEditingCommands.outdentedLine("  Task\n") == "Task\n")
        #expect(MarkdownEditingCommands.outdentedLine("\tTask") == "Task")
        #expect(MarkdownEditingCommands.outdentedLine("Task") == "Task")
    }

    @Test("Toolbar toggle converts plain, bullet, and ordered lines into todos")
    func testToolbarToggleConvertsPlainBulletAndOrderedLinesIntoTodos() {
        #expect(TodoMarkdown.toolbarToggledLine("Plain task") == "- [ ] Plain task")
        #expect(TodoMarkdown.toolbarToggledLine("  - Bullet task") == "  - [ ] Bullet task")
        #expect(TodoMarkdown.toolbarToggledLine("2. Ordered task") == "- [ ] Ordered task")
        #expect(TodoMarkdown.toolbarToggledLine("- [x] Existing todo") == "Existing todo")
    }

    @Test("Checkbox toggle switches todo state and leaves non-todos unchanged")
    func testCheckboxToggleSwitchesTodoStateAndLeavesNonTodosUnchanged() {
        #expect(TodoMarkdown.checkboxToggledLine("- [ ] Task") == "- [x] Task")
        #expect(TodoMarkdown.checkboxToggledLine("  - [x] Task") == "  - [ ] Task")
        #expect(TodoMarkdown.checkboxToggledLine("Plain task") == "Plain task")
    }
}
