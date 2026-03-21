import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "MarkdownTextStorage")

/// Custom NSTextStorage that applies rich formatting for markdown syntax.
/// Supports: # headings, **bold**, *italic*, - / * / 1. lists, [x] checkmarks, `code`.
final class MarkdownTextStorage: NSTextStorage {

    private let backing = NSMutableAttributedString()

    // MARK: - NSTextStorage required overrides

    override var string: String { backing.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        applyMarkdownFormatting()
        super.processEditing()
    }

    // MARK: - Body style

    static let bodyFont = UIFont.systemFont(ofSize: 17, weight: .regular)
    static let bodyColor = UIColor.label

    private var bodyParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        return style
    }

    // MARK: - Formatting

    private func applyMarkdownFormatting() {
        let fullRange = NSRange(location: 0, length: backing.length)
        guard fullRange.length > 0 else { return }

        // Reset to body style
        backing.setAttributes([
            .font: Self.bodyFont,
            .foregroundColor: Self.bodyColor,
            .paragraphStyle: bodyParagraphStyle
        ], range: fullRange)

        let text = backing.string

        // Process line by line
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byLines, .substringNotRequired]) { [weak self] _, substringRange, _, _ in
            guard let self else { return }
            let nsRange = NSRange(substringRange, in: text)
            let line = String(text[substringRange])
            self.formatLine(line, range: nsRange)
        }

        // Inline formatting across entire text
        applyInlineFormatting(in: fullRange, text: text)
    }

    private func formatLine(_ line: String, range: NSRange) {
        // Headings
        if line.hasPrefix("# ") {
            applyHeading(level: 1, range: range)
        } else if line.hasPrefix("## ") {
            applyHeading(level: 2, range: range)
        } else if line.hasPrefix("### ") {
            applyHeading(level: 3, range: range)
        }
        // List items
        else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            applyListIndent(range: range)
        }
        // Ordered list
        else if line.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
            applyListIndent(range: range)
        }
        // Checkmarks
        else if line.hasPrefix("- [x] ") || line.hasPrefix("- [ ] ") ||
                    line.hasPrefix("* [x] ") || line.hasPrefix("* [ ] ") {
            applyListIndent(range: range)
        }
    }

    private func applyHeading(level: Int, range: NSRange) {
        let sizes: [Int: CGFloat] = [1: 28, 2: 22, 3: 18]
        let weights: [Int: UIFont.Weight] = [1: .bold, 2: .bold, 3: .semibold]
        let font = UIFont.systemFont(ofSize: sizes[level] ?? 17, weight: weights[level] ?? .regular)

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacingBefore = level == 1 ? 8 : 4

        backing.addAttributes([
            .font: font,
            .paragraphStyle: style
        ], range: range)

        // Dim the markdown prefix (e.g., "# ")
        let prefixLen = level + 1 // "# " = 2, "## " = 3, "### " = 4
        if range.length > prefixLen {
            let prefixRange = NSRange(location: range.location, length: prefixLen)
            backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: prefixRange)
        }
    }

    private func applyListIndent(range: NSRange) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.headIndent = 20
        style.firstLineHeadIndent = 0
        backing.addAttribute(.paragraphStyle, value: style, range: range)
    }

    private func applyInlineFormatting(in range: NSRange, text: String) {
        let nsText = text as NSString

        // Bold: **text**
        applyPattern(#"\*\*(.+?)\*\*"#, in: range, nsText: nsText) { matchRange, _ in
            let currentFont = self.backing.attribute(.font, at: matchRange.location, effectiveRange: nil) as? UIFont ?? Self.bodyFont
            let boldFont = UIFont.systemFont(ofSize: currentFont.pointSize, weight: .bold)
            self.backing.addAttribute(.font, value: boldFont, range: matchRange)
            // Dim delimiters
            self.dimDelimiters(matchRange: matchRange, delimiterLength: 2)
        }

        // Italic: *text* (but not **)
        applyPattern(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, in: range, nsText: nsText) { matchRange, _ in
            let currentFont = self.backing.attribute(.font, at: matchRange.location, effectiveRange: nil) as? UIFont ?? Self.bodyFont
            let descriptor = currentFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? currentFont.fontDescriptor
            let italicFont = UIFont(descriptor: descriptor, size: currentFont.pointSize)
            self.backing.addAttribute(.font, value: italicFont, range: matchRange)
            self.dimDelimiters(matchRange: matchRange, delimiterLength: 1)
        }

        // Inline code: `text`
        applyPattern(#"`([^`]+)`"#, in: range, nsText: nsText) { matchRange, _ in
            let monoFont = UIFont.monospacedSystemFont(ofSize: Self.bodyFont.pointSize - 1, weight: .regular)
            self.backing.addAttributes([
                .font: monoFont,
                .foregroundColor: UIColor.secondaryLabel,
                .backgroundColor: UIColor.secondarySystemFill
            ], range: matchRange)
        }
    }

    private func dimDelimiters(matchRange: NSRange, delimiterLength: Int) {
        let startDelim = NSRange(location: matchRange.location, length: delimiterLength)
        let endDelim = NSRange(location: matchRange.location + matchRange.length - delimiterLength, length: delimiterLength)
        backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: startDelim)
        backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: endDelim)
    }

    private func applyPattern(_ pattern: String, in range: NSRange, nsText: NSString, handler: (NSRange, NSTextCheckingResult) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        regex.enumerateMatches(in: nsText as String, range: range) { match, _, _ in
            guard let match else { return }
            handler(match.range, match)
        }
    }

    // MARK: - Load / Export

    func load(markdown: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.bodyFont,
            .foregroundColor: Self.bodyColor
        ]
        let attrStr = NSAttributedString(string: markdown, attributes: attrs)
        beginEditing()
        backing.setAttributedString(attrStr)
        edited(.editedCharacters, range: NSRange(location: 0, length: 0), changeInLength: backing.length)
        endEditing()
    }

    func markdownContent() -> String {
        backing.string
    }
}
