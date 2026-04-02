/// # Test Index
///
/// ## Rendering Contracts
/// - `testHeadingRenderingAppliesTypographySpacingAndVisibilityByLevel`
/// - `testListRenderingAppliesExpectedIndentationSpacingAndMarkerStyling`
/// - `testFrontmatterIsHiddenFromRendering`
/// - `testInactiveTodoRenderingHidesPrefixAndProvidesCheckboxMetadata`
/// - `testCheckedTodoRenderingDimsAndStrikesThroughContent`
/// - `testTodoPrefixOnlyShowsWhenCursorIsInsidePrefix`
/// - `testInlineMarkdownRenderingAppliesBoldItalicAndCodeStyles`

import Testing
import UIKit
@testable import Noto

@Suite("Markdown Rendering")
struct MarkdownRenderingTests {

    @Test("Heading rendering applies typography, spacing, and active-line visibility by level")
    func testHeadingRenderingAppliesTypographySpacingAndVisibilityByLevel() {
        let inactive = makeHarness("# Title\n## Section\n### Detail").storage

        let titleOffset = offset(of: "Title", in: inactive)!
        let sectionOffset = offset(of: "Section", in: inactive)!
        let detailOffset = offset(of: "Detail", in: inactive)!

        #expect(font(in: inactive, at: titleOffset)?.pointSize == 28)
        #expect(font(in: inactive, at: sectionOffset)?.pointSize == 22)
        #expect(font(in: inactive, at: detailOffset)?.pointSize == 18)
        #expect(paragraphStyle(in: inactive, at: 0)?.paragraphSpacingBefore == 0)
        #expect(paragraphStyle(in: inactive, at: sectionOffset)?.paragraphSpacingBefore == 20)
        #expect(paragraphStyle(in: inactive, at: detailOffset)?.paragraphSpacing == 6)
        #expect(foregroundColor(in: inactive, at: 0) == UIColor.clear)

        let activeLine = lineRange(containing: "## Section", in: inactive)!
        inactive.setActiveLine(activeLine)
        #expect(foregroundColor(in: inactive, at: activeLine.location) == UIColor.tertiaryLabel)
    }

    @Test("List rendering applies expected indentation, spacing, and marker styling")
    func testListRenderingAppliesExpectedIndentationSpacingAndMarkerStyling() {
        let storage = makeHarness("- Top\n  - Nested\n1. Ordered").storage

        let topOffset = offset(of: "- Top", in: storage)!
        let nestedOffset = offset(of: "- Nested", in: storage)!
        let orderedOffset = offset(of: "1. Ordered", in: storage)!

        let bulletWidth = ("- " as NSString).size(withAttributes: [.font: MarkdownTextStorage.bodyFont]).width
        let orderedWidth = ("1. " as NSString).size(withAttributes: [.font: MarkdownTextStorage.bodyFont]).width

        #expect(paragraphStyle(in: storage, at: topOffset)?.firstLineHeadIndent == 12)
        #expect(paragraphStyle(in: storage, at: topOffset)?.headIndent == 12 + bulletWidth)
        #expect(paragraphStyle(in: storage, at: nestedOffset)?.firstLineHeadIndent == 24)
        #expect(foregroundColor(in: storage, at: topOffset) == UIColor.tertiaryLabel)
        #expect(paragraphStyle(in: storage, at: orderedOffset)?.firstLineHeadIndent == 12)
        #expect(paragraphStyle(in: storage, at: orderedOffset)?.headIndent == 12 + orderedWidth)
        #expect(paragraphStyle(in: storage, at: orderedOffset)?.paragraphSpacing == 4)
    }

    @Test("Frontmatter is hidden from rendering")
    func testFrontmatterIsHiddenFromRendering() {
        let storage = makeHarness("---\nid: abc\n---\n# Title").storage
        #expect(foregroundColor(in: storage, at: 0) == UIColor.clear)
        #expect(font(in: storage, at: 0)?.pointSize == CGFloat(0.1))
    }

    @Test("Inactive todo rendering hides prefix and provides checkbox metadata")
    func testInactiveTodoRenderingHidesPrefixAndProvidesCheckboxMetadata() {
        let harness = makeHarness("- [ ] Buy milk\nNext line")
        let storage = harness.storage
        let prefixOffset = 0

        #expect(foregroundColor(in: storage, at: prefixOffset) == UIColor.clear)
        #expect(font(in: storage, at: prefixOffset)?.pointSize == CGFloat(0.1))
        #expect(todoCheckbox(in: storage, at: prefixOffset) == false)

        let rect = todoCheckboxRect(in: harness, at: prefixOffset)
        #expect(rect != nil)
        #expect(rect?.width == MarkdownTextStorage.checkboxSize)
        #expect(rect?.height == MarkdownTextStorage.checkboxSize)
    }

    @Test("Todo prefix only shows when cursor is inside prefix")
    func testTodoPrefixOnlyShowsWhenCursorIsInsidePrefix() {
        let markdown = "- [ ] Buy milk"
        let line = NSRange(location: 0, length: (markdown as NSString).length)

        let contentCursorStorage = makeHarness(markdown, activeLine: line, cursorPosition: 6).storage
        #expect(foregroundColor(in: contentCursorStorage, at: 0) == UIColor.clear)
        #expect(todoCheckbox(in: contentCursorStorage, at: 0) == false)

        let prefixCursorStorage = makeHarness(markdown, activeLine: line, cursorPosition: 2).storage
        #expect(foregroundColor(in: prefixCursorStorage, at: 0) == UIColor.tertiaryLabel)
        #expect(todoCheckbox(in: prefixCursorStorage, at: 0) == nil)
    }

    @Test("Checked todo rendering dims and strikes through content")
    func testCheckedTodoRenderingDimsAndStrikesThroughContent() {
        let storage = makeHarness("- [x] Done task").storage
        let contentOffset = offset(of: "Done", in: storage)!
        let contentColor = foregroundColor(in: storage, at: contentOffset)

        #expect(strikethroughStyle(in: storage, at: contentOffset) == NSUnderlineStyle.single.rawValue)
        #expect(contentColor == UIColor.secondaryLabel || contentColor == UIColor.tertiaryLabel)
    }

    @Test("Inline markdown rendering applies bold, italic, and code styles")
    func testInlineMarkdownRenderingAppliesBoldItalicAndCodeStyles() {
        let storage = makeHarness("Some **bold** *italic* `code` text").storage

        let boldOffset = offset(of: "bold", in: storage)!
        let italicOffset = offset(of: "italic", in: storage)!
        let codeOffset = offset(of: "code", in: storage)!

        #expect(font(in: storage, at: boldOffset)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect(font(in: storage, at: italicOffset)?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        #expect(font(in: storage, at: codeOffset)?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true)
        #expect(foregroundColor(in: storage, at: codeOffset) == UIColor.secondaryLabel)
    }
}
