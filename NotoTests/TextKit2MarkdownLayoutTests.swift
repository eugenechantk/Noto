#if os(iOS)
import Testing
import UIKit
@testable import Noto

@Suite("TextKit 2 Markdown Layout")
struct TextKit2MarkdownLayoutTests {

    @Test("List metrics come from a single declarative visual spec")
    func listMetricsUseSharedVisualSpec() {
        #expect(MarkdownVisualSpec.listBaseIndent == 12)
        #expect(MarkdownVisualSpec.listIndentStep == 4)
        #expect(MarkdownVisualSpec.listMarkerTextGap == 8)
        #expect(MarkdownVisualSpec.todoTextStartOffset == 28)
        #expect(MarkdownVisualSpec.todoControlSize == 28)
    }

    @Test("Bullet continuation lines align with first-line content")
    func bulletContinuationLinesUseContentIndent() {
        let text = "- A long bullet that wraps onto another visual line"
        let kind = MarkdownBlockKind.detect(from: text)
        let paragraphStyle = MarkdownParagraphStyler.paragraphStyle(for: kind, text: text)
        let expectedIndent = MarkdownParagraphStyler.listContentIndent(for: kind, text: text)

        #expect(paragraphStyle.firstLineHeadIndent == MarkdownVisualSpec.listBaseIndent)
        #expect(abs(paragraphStyle.headIndent - (MarkdownVisualSpec.listBaseIndent + expectedIndent)) < 0.5)
    }

    @Test("Nested bullet indentation uses the reduced visual step")
    func nestedBulletIndentationUsesReducedStep() {
        let text = "    - Nested"
        let kind = MarkdownBlockKind.detect(from: text)
        let paragraphStyle = MarkdownParagraphStyler.paragraphStyle(for: kind, text: text)

        #expect(paragraphStyle.firstLineHeadIndent == MarkdownVisualSpec.listLeadingOffset(for: 2))
        #expect(paragraphStyle.headIndent > paragraphStyle.firstLineHeadIndent)
    }

    @Test("Markdown hyphen bullets keep the muted dash marker")
    func hyphenBulletsKeepMutedDashMarker() {
        let text = "- Visible bullet"
        let kind = MarkdownBlockKind.detect(from: text)
        let attributed = MarkdownParagraphStyler.style(text: text, kind: kind)
        let markerColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)

        #expect(attributed.string.hasPrefix("- "))
        #expect(markerColor?.resolvedColor(with: lightTrait) == UIColor.secondaryLabel.resolvedColor(with: lightTrait))
    }

    @Test("Todo markdown prefix is hidden so the circle control is the visible marker")
    func todoPrefixIsHiddenForCircleControl() {
        let text = "- [ ] Visible todo"
        let kind = MarkdownBlockKind.detect(from: text)
        let attributed = MarkdownParagraphStyler.style(text: text, kind: kind)
        let prefixLength = kind.prefixLength(in: text)
        let prefixColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)

        #expect(prefixLength == 6)
        #expect(prefixColor?.resolvedColor(with: lightTrait) == UIColor.clear.resolvedColor(with: lightTrait))
    }

    @Test("Todo wrapped lines align with first-line text after the circle")
    func todoWrappedLinesAlignWithTextAfterCircle() {
        let text = "- [ ] A long todo that wraps onto another visual line"
        let kind = MarkdownBlockKind.detect(from: text)
        let paragraphStyle = MarkdownParagraphStyler.paragraphStyle(for: kind, text: text)
        let expectedHeadIndent = MarkdownVisualSpec.listBaseIndent + MarkdownVisualSpec.todoTextStartOffset

        #expect(paragraphStyle.headIndent > paragraphStyle.firstLineHeadIndent)
        #expect(abs((paragraphStyle.headIndent - paragraphStyle.firstLineHeadIndent) - 2) < 0.5)
        #expect(abs(paragraphStyle.headIndent - expectedHeadIndent) < 0.5)
    }
}
#endif
