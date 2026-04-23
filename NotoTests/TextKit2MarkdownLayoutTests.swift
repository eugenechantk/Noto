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
        #expect(markerColor?.resolvedColor(with: lightTrait) == AppTheme.uiMutedText.resolvedColor(with: lightTrait))
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

    @Test("Markdown hyperlinks style the title as an actionable link")
    func markdownHyperlinksStyleTitleAsLink() throws {
        let text = "[Example](https://example.com)"
        let attributed = MarkdownParagraphStyler.style(text: text, kind: .paragraph)
        let url = try #require(attributed.attribute(.link, at: 1, effectiveRange: nil) as? URL)
        let underline = try #require(attributed.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int)
        let titleColor = try #require(attributed.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? UIColor)
        let syntaxColor = try #require(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        let syntaxFont = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)

        #expect(url.absoluteString == "https://example.com")
        #expect(underline == NSUnderlineStyle.single.rawValue)
        #expect(titleColor.resolvedColor(with: lightTrait) == UIColor.systemBlue.resolvedColor(with: lightTrait))
        #expect(syntaxColor.resolvedColor(with: lightTrait) == UIColor.clear.resolvedColor(with: lightTrait))
        #expect(abs(syntaxFont.pointSize - MarkdownVisualSpec.hyperlinkSyntaxVisualWidth) < 0.5)
    }

    @Test("Markdown document links style the title as an actionable link")
    func markdownDocumentLinksStyleTitleAsLink() throws {
        let text = "[Project Brief](Folder/Project Brief.md)"
        let attributed = MarkdownParagraphStyler.style(text: text, kind: .paragraph)
        let url = try #require(attributed.attribute(.link, at: 1, effectiveRange: nil) as? URL)

        #expect(url.scheme == "noto-document")
        #expect(url.query?.contains("Folder/Project%20Brief.md") == true)
    }

    @Test("Deleting a rendered hyperlink can reveal the full markdown syntax")
    func deletingRenderedHyperlinkCanRevealFullMarkdownSyntax() throws {
        let text = "[Example](https://example.com)"
        let attributed = MarkdownParagraphStyler.style(
            text: text,
            kind: .paragraph,
            revealedHyperlinkRanges: [NSRange(location: 0, length: (text as NSString).length)]
        )
        let syntaxColor = try #require(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        let titleColor = try #require(attributed.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? UIColor)
        let titleLink = attributed.attribute(.link, at: 1, effectiveRange: nil)
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)

        #expect(syntaxColor.resolvedColor(with: lightTrait) == AppTheme.uiMutedText.resolvedColor(with: lightTrait))
        #expect(titleColor.resolvedColor(with: lightTrait) == AppTheme.uiPrimaryText.resolvedColor(with: lightTrait))
        #expect(titleLink == nil)
    }

    @Test("Hidden hyperlink syntax adds no visible caret gap after the title")
    func hiddenHyperlinkSyntaxAddsNoVisibleCaretGapAfterTitle() {
        let text = "[Open in Reader](https://readwise.io/reader/document/long-identifier-1234567890)"
        let attributed = MarkdownParagraphStyler.style(text: text, kind: .paragraph)
        let title = "Open in Reader"
        let titleWidth = ceil((title as NSString).size(
            withAttributes: [.font: UIFont.systemFont(ofSize: MarkdownVisualSpec.bodyFont.pointSize, weight: .regular)]
        ).width)
        let renderedWidth = ceil(attributed.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).width)

        #expect(renderedWidth - titleWidth < 2)
    }

    @Test("Empty image links are detected as image placeholders")
    func emptyImageLinksAreDetectedAsImagePlaceholders() {
        let text = "[](https://substackcdn.com/image/fetch/example/https%3A%2F%2Fexample.com%2Fchart.png)"
        let kind = MarkdownBlockKind.detect(from: text)

        guard case .imageLink(let imageLink) = kind else {
            Issue.record("Expected image-link block kind")
            return
        }

        #expect(imageLink.urlString.contains("substackcdn.com/image/fetch"))
    }

    @Test("Non-image empty links stay regular paragraphs")
    func nonImageEmptyLinksStayRegularParagraphs() {
        let text = "[](https://example.com/article)"
        let kind = MarkdownBlockKind.detect(from: text)

        #expect(kind == .paragraph)
    }

    @Test("Image links reserve vertical preview space")
    func imageLinksReserveVerticalPreviewSpace() {
        let text = "![](https://example.com/chart.png)"
        let kind = MarkdownBlockKind.detect(from: text)
        let paragraphStyle = MarkdownParagraphStyler.paragraphStyle(for: kind, text: text)

        #expect(paragraphStyle.minimumLineHeight == MarkdownVisualSpec.imagePreviewReservedHeight)
        #expect(paragraphStyle.maximumLineHeight == MarkdownVisualSpec.imagePreviewReservedHeight)
    }

    @Test("Image links hide backing markdown text")
    func imageLinksHideBackingMarkdownText() throws {
        let text = "![](https://example.com/chart.png)"
        let kind = MarkdownBlockKind.detect(from: text)
        let attributed = MarkdownParagraphStyler.style(text: text, kind: kind)
        let color = try #require(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        let font = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)

        #expect(color.resolvedColor(with: lightTrait) == UIColor.clear.resolvedColor(with: lightTrait))
        #expect(abs(font.pointSize - MarkdownVisualSpec.imagePreviewBackingFontSize) < 0.5)
    }

    @Test("XML-like tag lines use muted code styling")
    func xmlLikeTagLinesUseMutedCodeStyling() throws {
        let text = "<insight>"
        let kind = MarkdownBlockKind.detect(from: text)
        let attributed = MarkdownParagraphStyler.style(text: text, kind: kind)
        let color = try #require(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        let font = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)

        #expect(kind == .xmlTag)
        #expect(color.resolvedColor(with: lightTrait) == AppTheme.uiMutedText.resolvedColor(with: lightTrait))
        #expect(abs(font.pointSize - MarkdownVisualSpec.codeFont.pointSize) < 0.5)
    }

    @Test("Noto capture comment tags use muted code styling")
    func notoCaptureCommentTagsUseMutedCodeStyling() throws {
        let text = "<!-- noto:highlights:start -->"
        let kind = MarkdownBlockKind.detect(from: text)
        let attributed = MarkdownParagraphStyler.style(text: text, kind: kind)
        let color = try #require(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        let font = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)

        #expect(kind == .xmlTag)
        #expect(color.resolvedColor(with: lightTrait) == AppTheme.uiMutedText.resolvedColor(with: lightTrait))
        #expect(abs(font.pointSize - MarkdownVisualSpec.codeFont.pointSize) < 0.5)
    }

    @Test("XML-like paired tags expose a collapsible content range")
    func xmlLikePairedTagsExposeCollapsibleContentRange() throws {
        let text = "<insight>\nHidden line\n</insight>\nVisible"
        let block = try #require(XMLLikeTagParser.blocks(in: text).first)

        #expect(block.tagName == "insight")
        #expect((text as NSString).substring(with: block.collapsedContentRange) == "Hidden line\n</insight>\n")
    }

    @Test("Noto capture comment tags expose a collapsible content range")
    func notoCaptureCommentTagsExposeCollapsibleContentRange() throws {
        let text = "<!-- noto:highlights:start -->\nHidden line\n<!-- noto:highlights:end -->\nVisible"
        let block = try #require(XMLLikeTagParser.blocks(in: text).first)

        #expect(block.tagName == "noto:highlights")
        #expect((text as NSString).substring(with: block.collapsedContentRange) == "Hidden line\n<!-- noto:highlights:end -->\n")
    }
}
#endif

#if os(macOS)
import AppKit
import Testing
@testable import Noto

@Suite("TextKit 2 Markdown Layout macOS")
struct TextKit2MarkdownLayoutMacTests {

    @Test("Empty todo prefix keeps trailing space at body size for insertion point height")
    func emptyTodoPrefixKeepsTrailingSpaceAtBodySizeForInsertionPointHeight() throws {
        let text = "- [ ] "
        let kind = MarkdownBlockKind.detect(from: text)
        let attributed = MarkdownParagraphStyler.style(text: text, kind: kind)
        let prefixLength = kind.prefixLength(in: text)
        let hiddenFont = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let insertionPointFont = try #require(attributed.attribute(.font, at: prefixLength - 1, effectiveRange: nil) as? NSFont)
        let insertionPointColor = try #require(attributed.attribute(.foregroundColor, at: prefixLength - 1, effectiveRange: nil) as? NSColor)

        #expect(prefixLength == 6)
        #expect(abs(hiddenFont.pointSize - MarkdownVisualSpec.todoPrefixVisualWidth) < 0.5)
        #expect(abs(insertionPointFont.pointSize - MarkdownVisualSpec.bodyFont.pointSize) < 0.5)
        #expect(insertionPointColor == NSColor.clear)
    }

    @Test("Markdown hyperlinks style the title as an actionable link")
    func markdownHyperlinksStyleTitleAsLink() throws {
        let text = "[Example](https://example.com)"
        let attributed = MarkdownParagraphStyler.style(text: text, kind: .paragraph)
        let url = try #require(attributed.attribute(.link, at: 1, effectiveRange: nil) as? URL)
        let underline = try #require(attributed.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int)
        let titleColor = try #require(attributed.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor)
        let syntaxColor = try #require(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let syntaxFont = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        #expect(url.absoluteString == "https://example.com")
        #expect(underline == NSUnderlineStyle.single.rawValue)
        #expect(titleColor == NSColor.linkColor)
        #expect(syntaxColor == NSColor.clear)
        #expect(abs(syntaxFont.pointSize - MarkdownVisualSpec.hyperlinkSyntaxVisualWidth) < 0.5)
    }

    @Test("Markdown document links style the title as an actionable link")
    func markdownDocumentLinksStyleTitleAsLink() throws {
        let text = "[Project Brief](Folder/Project Brief.md)"
        let attributed = MarkdownParagraphStyler.style(text: text, kind: .paragraph)
        let url = try #require(attributed.attribute(.link, at: 1, effectiveRange: nil) as? URL)

        #expect(url.scheme == "noto-document")
        #expect(url.query?.contains("Folder/Project%20Brief.md") == true)
    }

    @Test("Deleting a rendered hyperlink can reveal the full markdown syntax")
    func deletingRenderedHyperlinkCanRevealFullMarkdownSyntax() throws {
        let text = "[Example](https://example.com)"
        let attributed = MarkdownParagraphStyler.style(
            text: text,
            kind: .paragraph,
            revealedHyperlinkRanges: [NSRange(location: 0, length: (text as NSString).length)]
        )
        let syntaxColor = try #require(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let titleColor = try #require(attributed.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor)
        let titleLink = attributed.attribute(.link, at: 1, effectiveRange: nil)

        #expect(syntaxColor == AppTheme.nsMutedText)
        #expect(titleColor == AppTheme.nsPrimaryText)
        #expect(titleLink == nil)
    }

    @Test("Hidden hyperlink syntax adds no visible caret gap after the title")
    func hiddenHyperlinkSyntaxAddsNoVisibleCaretGapAfterTitle() {
        let text = "[Open in Reader](https://readwise.io/reader/document/long-identifier-1234567890)"
        let attributed = MarkdownParagraphStyler.style(text: text, kind: .paragraph)
        let title = "Open in Reader"
        let titleWidth = ceil((title as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: MarkdownVisualSpec.bodyFont.pointSize, weight: .regular)]
        ).width)
        let renderedWidth = ceil(attributed.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).width)

        #expect(renderedWidth - titleWidth < 2)
    }

    @Test("Image links reserve vertical preview space")
    func imageLinksReserveVerticalPreviewSpace() {
        let text = "![](https://example.com/chart.png)"
        let kind = MarkdownBlockKind.detect(from: text)
        let paragraphStyle = MarkdownParagraphStyler.paragraphStyle(for: kind, text: text)

        #expect(paragraphStyle.minimumLineHeight == MarkdownVisualSpec.imagePreviewReservedHeight)
        #expect(paragraphStyle.maximumLineHeight == MarkdownVisualSpec.imagePreviewReservedHeight)
    }

    @Test("Image links hide backing markdown text")
    func imageLinksHideBackingMarkdownText() throws {
        let text = "![](https://example.com/chart.png)"
        let kind = MarkdownBlockKind.detect(from: text)
        let attributed = MarkdownParagraphStyler.style(text: text, kind: kind)
        let color = try #require(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let font = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        #expect(color == NSColor.clear)
        #expect(abs(font.pointSize - MarkdownVisualSpec.imagePreviewBackingFontSize) < 0.5)
    }

    @Test("XML-like tag lines use muted code styling")
    func xmlLikeTagLinesUseMutedCodeStyling() throws {
        let text = "</insight>"
        let kind = MarkdownBlockKind.detect(from: text)
        let attributed = MarkdownParagraphStyler.style(text: text, kind: kind)
        let color = try #require(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let font = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        #expect(kind == .xmlTag)
        #expect(color == AppTheme.nsMutedText)
        #expect(abs(font.pointSize - MarkdownVisualSpec.codeFont.pointSize) < 0.5)
    }

    @Test("Noto capture comment tags use muted code styling")
    func notoCaptureCommentTagsUseMutedCodeStyling() throws {
        let text = "<!-- noto:content:start -->"
        let kind = MarkdownBlockKind.detect(from: text)
        let attributed = MarkdownParagraphStyler.style(text: text, kind: kind)
        let color = try #require(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let font = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        #expect(kind == .xmlTag)
        #expect(color == AppTheme.nsMutedText)
        #expect(abs(font.pointSize - MarkdownVisualSpec.codeFont.pointSize) < 0.5)
    }

    @Test("XML-like paired tags expose a collapsible content range")
    func xmlLikePairedTagsExposeCollapsibleContentRange() throws {
        let text = "<insight>\nHidden line\n</insight>\nVisible"
        let block = try #require(XMLLikeTagParser.blocks(in: text).first)

        #expect(block.tagName == "insight")
        #expect((text as NSString).substring(with: block.collapsedContentRange) == "Hidden line\n</insight>\n")
    }

    @Test("Noto capture comment tags expose a collapsible content range")
    func notoCaptureCommentTagsExposeCollapsibleContentRange() throws {
        let text = "<!-- noto:content:start -->\nHidden line\n<!-- noto:content:end -->\nVisible"
        let block = try #require(XMLLikeTagParser.blocks(in: text).first)

        #expect(block.tagName == "noto:content")
        #expect((text as NSString).substring(with: block.collapsedContentRange) == "Hidden line\n<!-- noto:content:end -->\n")
    }
}
#endif
