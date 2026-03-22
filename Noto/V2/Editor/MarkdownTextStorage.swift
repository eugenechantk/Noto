import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "MarkdownTextStorage")

/// Custom NSTextStorage that applies rich formatting for markdown syntax.
/// Supports: # headings, **bold**, *italic*, - / * / 1. lists, [x] checkmarks, `code`.
final class MarkdownTextStorage: NSTextStorage {

    private let backing = NSMutableAttributedString()
    private var isFormatting = false

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
        if !isFormatting {
            isFormatting = true
            applyMarkdownFormatting()
            isFormatting = false
        }
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

        // Hide YAML frontmatter block
        var contentStart = 0
        if text.hasPrefix("---") {
            if let closeRange = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
                let fmEnd = text.index(closeRange.upperBound, offsetBy: 0)
                contentStart = NSRange(text.startIndex..<fmEnd, in: text).length
                // Make frontmatter tiny and invisible
                let fmRange = NSRange(location: 0, length: contentStart)
                let fmStyle = NSMutableParagraphStyle()
                fmStyle.lineSpacing = 0
                fmStyle.paragraphSpacing = 0
                fmStyle.minimumLineHeight = 0.1
                fmStyle.maximumLineHeight = 0.1
                backing.addAttributes([
                    .font: UIFont.systemFont(ofSize: 0.1),
                    .foregroundColor: UIColor.clear,
                    .paragraphStyle: fmStyle
                ], range: fmRange)
            }
        }

        // Process line by line (skip frontmatter)
        let bodyStart = text.index(text.startIndex, offsetBy: contentStart)
        if bodyStart < text.endIndex {
            text.enumerateSubstrings(in: bodyStart..<text.endIndex, options: [.byLines, .substringNotRequired]) { [weak self] _, substringRange, _, _ in
                guard let self else { return }
                let nsRange = NSRange(substringRange, in: text)
                let line = String(text[substringRange])
                self.formatLine(line, range: nsRange)
            }

            // Inline formatting across body only
            let bodyRange = NSRange(location: contentStart, length: fullRange.length - contentStart)
            applyInlineFormatting(in: bodyRange, text: text)
        }
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
        // Bullet lists: count leading spaces to determine nesting level
        else if let match = line.range(of: #"^(\s*)[*-] "#, options: .regularExpression) {
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" })
            let level = (leadingSpaces.count / 2) + 1 // 0 spaces = level 1, 2 spaces = level 2, etc.
            let prefixLength = line.distance(from: line.startIndex, to: match.upperBound)
            applyBulletList(range: range, prefixLength: prefixLength, level: level)
        }
        // Ordered list
        else if let match = line.range(of: #"^(\s*)\d+\. "#, options: .regularExpression) {
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" })
            let level = (leadingSpaces.count / 2) + 1
            let prefixLength = line.distance(from: line.startIndex, to: match.upperBound)
            applyOrderedList(range: range, prefixLength: prefixLength, level: level)
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

    private static let indentPerLevel: CGFloat = 8

    /// Custom attribute to mark bullet characters that were replaced from `-` or `*`.
    private static let bulletMarkerKey = NSAttributedString.Key("noto.bulletMarker")

    private func applyBulletList(range: NSRange, prefixLength: Int, level: Int) {
        let indent = Self.indentPerLevel * CGFloat(level)

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.firstLineHeadIndent = indent - Self.indentPerLevel
        style.headIndent = indent
        backing.addAttribute(.paragraphStyle, value: style, range: range)

        // Hide leading whitespace
        let prefixStr = (backing.string as NSString).substring(with: NSRange(location: range.location, length: prefixLength))
        let leadingSpaceCount = prefixStr.prefix(while: { $0 == " " || $0 == "\t" }).count
        if leadingSpaceCount > 0 {
            backing.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: range.location, length: leadingSpaceCount))
        }

        // Replace `-` or `*` with `•`
        let bulletCharRange = NSRange(location: range.location + leadingSpaceCount, length: 1)
        let originalChar = (backing.string as NSString).substring(with: bulletCharRange)
        if originalChar == "-" || originalChar == "*" {
            backing.replaceCharacters(in: bulletCharRange, with: "•")
            backing.addAttribute(Self.bulletMarkerKey, value: originalChar, range: bulletCharRange)
            backing.addAttribute(.foregroundColor, value: Self.bodyColor, range: bulletCharRange)
        }
    }

    private func applyOrderedList(range: NSRange, prefixLength: Int, level: Int) {
        let indent = Self.indentPerLevel * CGFloat(level)

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.firstLineHeadIndent = indent - Self.indentPerLevel
        style.headIndent = indent
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
        let result = NSMutableString(string: backing.string)
        // Reverse bullet replacements: `•` back to original `-` or `*`
        backing.enumerateAttribute(Self.bulletMarkerKey, in: NSRange(location: 0, length: backing.length)) { value, attrRange, _ in
            if let original = value as? String {
                result.replaceCharacters(in: attrRange, with: original)
            }
        }
        return result as String
    }
}
