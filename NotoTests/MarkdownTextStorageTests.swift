/// # Test Index
///
/// ## Headings
/// - `testHeading1FontSize` — H1 uses 28pt bold
/// - `testHeading2FontSize` — H2 uses 22pt bold
/// - `testHeading3FontSize` — H3 uses 18pt semibold
/// - `testHeadingSpacingBefore` — Progressive spacing: H1=24, H2=20, H3=16
/// - `testHeadingSpacingAfter` — Progressive spacing: H1=12, H2=8, H3=6
/// - `testTitleHeadingNoSpacingBefore` — First H1 (title) has paragraphSpacingBefore=0
/// - `testHeadingPrefixHiddenWhenInactive` — ## prefix is invisible (0.1pt, clear) when cursor elsewhere
/// - `testHeadingPrefixShownWhenActive` — ## prefix is dimmed (tertiaryLabel) when cursor on that line
///
/// ## Body
/// - `testBodyParagraphSpacing` — Body text has paragraphSpacing=6
///
/// ## Bullet Lists
/// - `testBulletIndentLevel1` — Level 1 bullet indented 12px
/// - `testBulletIndentLevel2` — Level 2 bullet indented 24px
/// - `testBulletIndentLevel3` — Level 3 bullet indented 36px
/// - `testBulletWrapAlignment` — Wrapped lines align with text after bullet
/// - `testBulletParagraphSpacing` — Bullet paragraph spacing = 4
/// - `testBulletMarkerDimmed` — `-` and `*` markers dimmed with tertiaryLabel color
///
/// ## Ordered Lists
/// - `testOrderedListIndent` — Ordered list indented 12px per level
/// - `testOrderedListWrapAlignment` — Wrapped lines align with text after prefix
/// - `testOrderedListParagraphSpacing` — Ordered list paragraph spacing = 4
///
/// ## Frontmatter
/// - `testFrontmatterHidden` — YAML frontmatter is invisible (0.1pt, clear)
///
/// ## Inline Formatting
/// - `testBoldFormatting` — **text** uses bold weight
/// - `testItalicFormatting` — *text* uses italic trait
/// - `testInlineCodeFormatting` — `code` uses monospaced font

import Testing
import UIKit
@testable import Noto

// MARK: - Helpers

/// Creates a MarkdownTextStorage with a layout manager attached (required for processEditing).
private func makeStorage(_ markdown: String, activeLine: NSRange? = nil) -> MarkdownTextStorage {
    let storage = MarkdownTextStorage()
    let layoutManager = NSLayoutManager()
    storage.addLayoutManager(layoutManager)
    let container = NSTextContainer()
    container.widthTracksTextView = true
    layoutManager.addTextContainer(container)
    storage.activeLine = activeLine
    storage.load(markdown: markdown)
    return storage
}

/// Returns the NSParagraphStyle at a given character offset.
private func paragraphStyle(in storage: MarkdownTextStorage, at offset: Int) -> NSParagraphStyle? {
    guard offset < storage.length else { return nil }
    return storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
}

/// Returns the UIFont at a given character offset.
private func font(in storage: MarkdownTextStorage, at offset: Int) -> UIFont? {
    guard offset < storage.length else { return nil }
    return storage.attribute(.font, at: offset, effectiveRange: nil) as? UIFont
}

/// Returns the foreground color at a given character offset.
private func foregroundColor(in storage: MarkdownTextStorage, at offset: Int) -> UIColor? {
    guard offset < storage.length else { return nil }
    return storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor
}

/// Returns the character offset of the first occurrence of a substring.
private func offset(of substring: String, in storage: MarkdownTextStorage) -> Int? {
    (storage.string as NSString).range(of: substring).location == NSNotFound
        ? nil
        : (storage.string as NSString).range(of: substring).location
}

// MARK: - Heading Tests

@Suite("Heading Formatting")
struct HeadingFormattingTests {

    @Test("H1 uses 28pt bold font")
    func testHeading1FontSize() {
        let storage = makeStorage("# Hello")
        // Font on the text portion (after "# ")
        let f = font(in: storage, at: storage.string.count - 1)
        #expect(f?.pointSize == 28)
        #expect(f?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    @Test("H2 uses 22pt bold font")
    func testHeading2FontSize() {
        let storage = makeStorage("## Hello")
        let f = font(in: storage, at: storage.string.count - 1)
        #expect(f?.pointSize == 22)
        #expect(f?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    @Test("H3 uses 18pt semibold font")
    func testHeading3FontSize() {
        let storage = makeStorage("### Hello")
        let f = font(in: storage, at: storage.string.count - 1)
        #expect(f?.pointSize == 18)
    }

    @Test("Heading spacing before is progressive: H1=24, H2=20, H3=16")
    func testHeadingSpacingBefore() {
        // First H1 is treated as title (no spacing before), so add a second H1 to test
        let storage = makeStorage("# Title\nBody\n# Second H1\n## H2\n### H3")

        let h1Offset = offset(of: "# Second H1", in: storage)!
        let h2Offset = offset(of: "## H2", in: storage)!
        let h3Offset = offset(of: "### H3", in: storage)!

        let h1Style = paragraphStyle(in: storage, at: h1Offset)
        #expect(h1Style?.paragraphSpacingBefore == 24)

        let h2Style = paragraphStyle(in: storage, at: h2Offset)
        #expect(h2Style?.paragraphSpacingBefore == 20)

        let h3Style = paragraphStyle(in: storage, at: h3Offset)
        #expect(h3Style?.paragraphSpacingBefore == 16)
    }

    @Test("Heading spacing after is progressive: H1=12, H2=8, H3=6")
    func testHeadingSpacingAfter() {
        let storage = makeStorage("# H1\n## H2\n### H3")

        let h1Offset = offset(of: "# H1", in: storage)!
        let h2Offset = offset(of: "## H2", in: storage)!
        let h3Offset = offset(of: "### H3", in: storage)!

        #expect(paragraphStyle(in: storage, at: h1Offset)?.paragraphSpacing == 12)
        #expect(paragraphStyle(in: storage, at: h2Offset)?.paragraphSpacing == 8)
        #expect(paragraphStyle(in: storage, at: h3Offset)?.paragraphSpacing == 6)
    }

    @Test("Title heading (first H1) has no spacing before")
    func testTitleHeadingNoSpacingBefore() {
        let storage = makeStorage("# Title\n## Subtitle")
        let titleStyle = paragraphStyle(in: storage, at: 0)
        #expect(titleStyle?.paragraphSpacingBefore == 0)
    }

    @Test("Heading prefix hidden when cursor is not on that line")
    func testHeadingPrefixHiddenWhenInactive() {
        let storage = makeStorage("## Hello\nBody text")
        // "## " prefix at offset 0
        let prefixFont = font(in: storage, at: 0)
        let prefixColor = foregroundColor(in: storage, at: 0)
        #expect(prefixFont?.pointSize == CGFloat(0.1))
        #expect(prefixColor == UIColor.clear)
    }

    @Test("Heading prefix shown dimmed when cursor is on that line")
    func testHeadingPrefixShownWhenActive() {
        // Set active line to the heading line range
        let text = "## Hello\nBody text"
        let lineRange = NSRange(location: 0, length: 8) // "## Hello"
        let storage = makeStorage(text, activeLine: lineRange)
        let prefixColor = foregroundColor(in: storage, at: 0)
        #expect(prefixColor == UIColor.tertiaryLabel)
    }
}

// MARK: - Body Tests

@Suite("Body Formatting")
struct BodyFormattingTests {

    @Test("Body paragraph spacing is 6")
    func testBodyParagraphSpacing() {
        let storage = makeStorage("Some body text")
        let style = paragraphStyle(in: storage, at: 0)
        #expect(style?.paragraphSpacing == 6)
    }
}

// MARK: - Bullet List Tests

@Suite("Bullet List Formatting")
struct BulletListFormattingTests {

    @Test("Level 1 bullet indented 12px")
    func testBulletIndentLevel1() {
        let storage = makeStorage("- Item one")
        let style = paragraphStyle(in: storage, at: 0)
        #expect(style?.firstLineHeadIndent == 12)
    }

    @Test("Level 2 bullet indented 24px")
    func testBulletIndentLevel2() {
        let storage = makeStorage("- L1\n  - L2")
        // Find "- L2" (leading spaces hidden but still in string)
        let l2Offset = offset(of: "- L2", in: storage)!
        let style = paragraphStyle(in: storage, at: l2Offset)
        #expect(style?.firstLineHeadIndent == 24)
    }

    @Test("Level 3 bullet indented 36px")
    func testBulletIndentLevel3() {
        let storage = makeStorage("- L1\n  - L2\n    - L3")
        // Find "- L3"
        // Use lastRange to get the last occurrence (L3, not L1 or L2)
        let nsString = storage.string as NSString
        var searchRange = NSRange(location: 0, length: nsString.length)
        var lastOffset: Int?
        while searchRange.location < nsString.length {
            let found = nsString.range(of: "- L3", range: searchRange)
            if found.location == NSNotFound { break }
            lastOffset = found.location
            searchRange = NSRange(location: found.location + found.length, length: nsString.length - found.location - found.length)
        }
        let l3Offset = lastOffset!
        let style = paragraphStyle(in: storage, at: l3Offset)
        #expect(style?.firstLineHeadIndent == 36)
    }

    @Test("Wrapped lines align with text after bullet character")
    func testBulletWrapAlignment() {
        let storage = makeStorage("- Item one")
        let style = paragraphStyle(in: storage, at: 0)
        let bulletTextWidth = ("- " as NSString).size(withAttributes: [.font: MarkdownTextStorage.bodyFont]).width
        #expect(style?.headIndent == 12 + bulletTextWidth)
    }

    @Test("Bullet paragraph spacing is 4")
    func testBulletParagraphSpacing() {
        let storage = makeStorage("- Item")
        let style = paragraphStyle(in: storage, at: 0)
        #expect(style?.paragraphSpacing == 4)
    }

    @Test("Bullet marker character is dimmed (tertiaryLabel)")
    func testBulletMarkerDimmed() {
        let storage = makeStorage("- Item")
        // The `-` character at offset 0 should be dimmed
        let color = foregroundColor(in: storage, at: 0)
        #expect(color == UIColor.tertiaryLabel)
    }
}

// MARK: - Ordered List Tests

@Suite("Ordered List Formatting")
struct OrderedListFormattingTests {

    @Test("Ordered list indented 12px per level")
    func testOrderedListIndent() {
        let storage = makeStorage("1. First item")
        let style = paragraphStyle(in: storage, at: 0)
        #expect(style?.firstLineHeadIndent == 12)
    }

    @Test("Ordered list wrapped lines align with text after prefix")
    func testOrderedListWrapAlignment() {
        let storage = makeStorage("1. First item")
        let style = paragraphStyle(in: storage, at: 0)
        let prefixWidth = ("1. " as NSString).size(withAttributes: [.font: MarkdownTextStorage.bodyFont]).width
        #expect(style?.headIndent == 12 + prefixWidth)
    }

    @Test("Ordered list paragraph spacing is 4")
    func testOrderedListParagraphSpacing() {
        let storage = makeStorage("1. Item")
        let style = paragraphStyle(in: storage, at: 0)
        #expect(style?.paragraphSpacing == 4)
    }
}

// MARK: - Frontmatter Tests

@Suite("Frontmatter Formatting")
struct FrontmatterFormattingTests {

    @Test("YAML frontmatter is hidden with tiny clear font")
    func testFrontmatterHidden() {
        let storage = makeStorage("---\nid: abc\n---\n# Title")
        // Check the frontmatter area (offset 0)
        let f = font(in: storage, at: 0)
        let color = foregroundColor(in: storage, at: 0)
        #expect(f?.pointSize == CGFloat(0.1))
        #expect(color == UIColor.clear)
    }
}

// MARK: - Inline Formatting Tests

@Suite("Inline Formatting")
struct InlineFormattingTests {

    @Test("Bold text uses bold weight")
    func testBoldFormatting() {
        let storage = makeStorage("Some **bold** text")
        let boldOffset = offset(of: "bold", in: storage)!
        let f = font(in: storage, at: boldOffset)
        #expect(f?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    @Test("Italic text uses italic trait")
    func testItalicFormatting() {
        let storage = makeStorage("Some *italic* text")
        let italicOffset = offset(of: "italic", in: storage)!
        let f = font(in: storage, at: italicOffset)
        #expect(f?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
    }

    @Test("Inline code uses monospaced font")
    func testInlineCodeFormatting() {
        let storage = makeStorage("Some `code` text")
        let codeOffset = offset(of: "code", in: storage)!
        let f = font(in: storage, at: codeOffset)
        #expect(f?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true)
    }
}
