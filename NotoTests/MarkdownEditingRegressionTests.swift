/// # Test Index
///
/// ## Edit Regressions
/// - `testDeletingHeadingContentDoesNotRestyleFollowingParagraph`
/// - `testDeletingTodoContentDoesNotLeakCheckboxMetadataToFollowingParagraph`
/// - `testChangingActiveLineRecomputesVisibilityWithoutStaleState`
/// - `testEmptyTodoBeforeHeadingKeepsHeadingVerticalOffsetStable`

import Testing
import UIKit
@testable import Noto

@Suite("Markdown Editing Regressions")
struct MarkdownEditingRegressionTests {

    @Test("Deleting heading content does not restyle the following paragraph")
    func testDeletingHeadingContentDoesNotRestyleFollowingParagraph() {
        let harness = makeHarness("# Heading\nBody paragraph")
        let storage = harness.storage

        let headingCharacter = offset(of: "g", in: storage)!
        storage.replaceCharacters(in: NSRange(location: headingCharacter, length: 1), with: "")
        storage.render(activeLine: lineRange(containing: "# Headin", in: storage))

        let bodyOffset = offset(of: "Body", in: storage)!
        #expect(font(in: storage, at: bodyOffset)?.pointSize == MarkdownEditorTheme.bodyFont.pointSize)
        #expect(paragraphStyle(in: storage, at: bodyOffset)?.paragraphSpacing == 6)
        #expect(foregroundColor(in: storage, at: bodyOffset) == UIColor.label)
    }

    @Test("Deleting todo content does not leak checkbox metadata to the following paragraph")
    func testDeletingTodoContentDoesNotLeakCheckboxMetadataToFollowingParagraph() {
        let harness = makeHarness("- [ ] Task item\nPlain paragraph")
        let storage = harness.storage

        let taskOffset = offset(of: "Task", in: storage)!
        storage.replaceCharacters(in: NSRange(location: taskOffset, length: 4), with: "")
        storage.render(activeLine: lineRange(containing: "- [ ]", in: storage))

        let paragraphOffset = offset(of: "Plain", in: storage)!
        #expect(todoCheckbox(in: storage, at: paragraphOffset) == nil)
        #expect(font(in: storage, at: paragraphOffset)?.pointSize == MarkdownEditorTheme.bodyFont.pointSize)
        #expect(foregroundColor(in: storage, at: paragraphOffset) == UIColor.label)
    }

    @Test("Changing active line recomputes heading and todo visibility without stale state")
    func testChangingActiveLineRecomputesVisibilityWithoutStaleState() {
        let harness = makeHarness("## Heading\n- [ ] Task\nBody")
        let storage = harness.storage

        let headingLine = lineRange(containing: "## Heading", in: storage)!
        storage.setActiveLine(headingLine, cursorPosition: headingLine.location + 1)
        #expect(foregroundColor(in: storage, at: headingLine.location) == UIColor.tertiaryLabel)

        let todoLine = lineRange(containing: "- [ ] Task", in: storage)!
        storage.setActiveLine(todoLine, cursorPosition: todoLine.location + 2)
        #expect(foregroundColor(in: storage, at: headingLine.location) == UIColor.clear)
        #expect(foregroundColor(in: storage, at: todoLine.location) == UIColor.tertiaryLabel)
    }

    @Test("Empty todo before heading keeps heading vertical offset stable")
    func testEmptyTodoBeforeHeadingKeepsHeadingVerticalOffsetStable() {
        let emptyHarness = makeHarness("- [ ] \n## Heading")
        let filledHarness = makeHarness("- [ ] Task\n## Heading")

        let emptyHeadingOffset = offset(of: "Heading", in: emptyHarness.storage)!
        let filledHeadingOffset = offset(of: "Heading", in: filledHarness.storage)!

        let emptyTodoOffset = offset(of: "- [ ]", in: emptyHarness.storage)!
        let emptyTodoRect = lineFragmentRect(in: emptyHarness, at: emptyTodoOffset)
        let emptyHeadingRect = lineFragmentRect(in: emptyHarness, at: emptyHeadingOffset)
        let filledHeadingRect = lineFragmentRect(in: filledHarness, at: filledHeadingOffset)

        #expect(emptyTodoRect != nil)
        #expect(emptyTodoRect?.height ?? 0 >= MarkdownEditorTheme.bodyFont.lineHeight)
        #expect(emptyHeadingRect != nil)
        #expect(filledHeadingRect != nil)
        #expect(abs((emptyHeadingRect?.minY ?? 0) - (filledHeadingRect?.minY ?? 0)) < 1.0)
    }
}
