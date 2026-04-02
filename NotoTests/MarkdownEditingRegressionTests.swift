/// # Test Index
///
/// ## Edit Regressions
/// - `testDeletingHeadingContentDoesNotRestyleFollowingParagraph`
/// - `testDeletingTodoContentDoesNotLeakCheckboxMetadataToFollowingParagraph`
/// - `testChangingActiveLineRecomputesVisibilityWithoutStaleState`

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
        #expect(font(in: storage, at: bodyOffset)?.pointSize == MarkdownTextStorage.bodyFont.pointSize)
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
        #expect(font(in: storage, at: paragraphOffset)?.pointSize == MarkdownTextStorage.bodyFont.pointSize)
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
}
