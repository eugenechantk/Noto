#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import Foundation

struct MarkdownFormatter {
    private static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let italicRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
    private static let codeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)

    private static let bulletTextWidth: CGFloat = {
        ("- " as NSString).size(withAttributes: [.font: MarkdownEditorTheme.bodyFont]).width
    }()

    func makeAttributedString(markdown: String, activeLine: NSRange?, cursorPosition: Int?) -> NSMutableAttributedString {
        let attributed = NSMutableAttributedString(string: markdown, attributes: MarkdownEditorTheme.bodyAttributes)
        guard attributed.length > 0 else { return attributed }

        let nsText = attributed.mutableString
        let contentStart = frontmatterEnd(in: nsText)
        if contentStart > 0 {
            applyFrontmatterHiding(to: attributed, range: NSRange(location: 0, length: contentStart))
        }

        guard contentStart < nsText.length else { return attributed }
        let bodyRange = NSRange(location: contentStart, length: nsText.length - contentStart)
        let firstHeadingLocation = firstHeadingLocation(in: nsText, contentStart: contentStart)

        var lines: [(String, NSRange)] = []
        nsText.enumerateSubstrings(in: bodyRange, options: [.byLines, .substringNotRequired]) { _, substringRange, _, _ in
            lines.append((nsText.substring(with: substringRange), substringRange))
        }

        for (line, range) in lines {
            let isTitle = range.location == firstHeadingLocation && line.hasPrefix("# ")
            formatLine(
                line,
                range: range,
                isTitle: isTitle,
                activeLine: activeLine,
                cursorPosition: cursorPosition,
                attributed: attributed,
                nsText: nsText
            )
        }

        applyInlineFormatting(in: bodyRange, attributed: attributed, nsText: nsText)
        return attributed
    }

    private func formatLine(
        _ line: String,
        range: NSRange,
        isTitle: Bool,
        activeLine: NSRange?,
        cursorPosition: Int?,
        attributed: NSMutableAttributedString,
        nsText: NSMutableString
    ) {
        if line.hasPrefix("# ") {
            applyHeading(level: 1, range: range, isTitle: isTitle, activeLine: activeLine, attributed: attributed)
        } else if line.hasPrefix("## ") {
            applyHeading(level: 2, range: range, isTitle: false, activeLine: activeLine, attributed: attributed)
        } else if line.hasPrefix("### ") {
            applyHeading(level: 3, range: range, isTitle: false, activeLine: activeLine, attributed: attributed)
        } else if let todoMatch = TodoMarkdown.match(in: line) {
            let level = (todoMatch.indentation.count / 2) + 1
            applyTodo(
                line: line,
                range: range,
                prefixLength: todoMatch.prefixLength,
                level: level,
                isChecked: todoMatch.isChecked,
                activeLine: activeLine,
                cursorPosition: cursorPosition,
                attributed: attributed
            )
        } else if let match = line.range(of: #"^(\s*)[*\-•] "#, options: .regularExpression) {
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" })
            let level = (leadingSpaces.count / 2) + 1
            let prefixLength = line.distance(from: line.startIndex, to: match.upperBound)
            applyBulletList(range: range, prefixLength: prefixLength, level: level, attributed: attributed, nsText: nsText)
        } else if let match = line.range(of: #"^(\s*)\d+\. "#, options: .regularExpression) {
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" })
            let level = (leadingSpaces.count / 2) + 1
            let prefixLength = line.distance(from: line.startIndex, to: match.upperBound)
            applyOrderedList(range: range, prefixLength: prefixLength, level: level, attributed: attributed, nsText: nsText)
        }
    }

    private func applyHeading(
        level: Int,
        range: NSRange,
        isTitle: Bool,
        activeLine: NSRange?,
        attributed: NSMutableAttributedString
    ) {
        let font = MarkdownEditorTheme.headingFonts[level] ?? MarkdownEditorTheme.bodyFont

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        if !isTitle {
            let spacingBefore: [Int: CGFloat] = [1: 24, 2: 20, 3: 16]
            style.paragraphSpacingBefore = spacingBefore[level] ?? 16
        }
        let spacingAfter: [Int: CGFloat] = [1: 12, 2: 8, 3: 6]
        style.paragraphSpacing = spacingAfter[level] ?? 6

        attributed.addAttributes([
            .font: font,
            .paragraphStyle: style
        ], range: range)

        let prefixLength = level + 1
        guard range.length > prefixLength else { return }

        let prefixRange = NSRange(location: range.location, length: prefixLength)
        if activeLine?.location == range.location {
            attributed.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: prefixRange)
        } else {
            let prefix = String(repeating: "#", count: level) + " "
            let prefixWidth = (prefix as NSString).size(withAttributes: [.font: font]).width
            style.firstLineHeadIndent = -prefixWidth
            style.headIndent = 0
            attributed.addAttribute(.paragraphStyle, value: style, range: range)
            attributed.addAttribute(.foregroundColor, value: PlatformColor.clear, range: prefixRange)
        }
    }

    private func applyTodo(
        line: String,
        range: NSRange,
        prefixLength: Int,
        level: Int,
        isChecked: Bool,
        activeLine: NSRange?,
        cursorPosition: Int?,
        attributed: NSMutableAttributedString
    ) {
        let levelIndent = MarkdownEditorTheme.indentPerLevel * CGFloat(level)
        let prefixRange = NSRange(location: range.location, length: min(prefixLength, range.length))
        let cursorInPrefix: Bool = {
            guard let activeLine, activeLine.location == range.location else { return false }
            guard let cursorPosition else { return false }
            return cursorPosition >= prefixRange.location && cursorPosition < NSMaxRange(prefixRange)
        }()

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 4
        if cursorInPrefix {
            style.firstLineHeadIndent = levelIndent
            style.headIndent = levelIndent + Self.bulletTextWidth
            attributed.addAttribute(.paragraphStyle, value: style, range: range)
            attributed.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: prefixRange)
        } else {
            let prefixText = String(line.prefix(prefixLength))
            let prefixWidth = (prefixText as NSString).size(withAttributes: [.font: MarkdownEditorTheme.bodyFont]).width
            let textIndent = levelIndent + MarkdownTodoCheckboxStyle.size + MarkdownTodoCheckboxStyle.spacing
            style.firstLineHeadIndent = textIndent - prefixWidth
            style.headIndent = textIndent
            attributed.addAttribute(.paragraphStyle, value: style, range: range)
            attributed.addAttribute(.foregroundColor, value: PlatformColor.clear, range: prefixRange)
            attributed.addAttribute(MarkdownTodoCheckboxStyle.attributeKey, value: isChecked, range: prefixRange)
        }

        let contentRange = NSRange(
            location: range.location + prefixLength,
            length: max(0, range.length - prefixLength)
        )
        guard contentRange.length > 0 else { return }

        if isChecked {
            attributed.addAttributes([
                .foregroundColor: PlatformColor.secondaryLabel,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ], range: contentRange)
        } else {
            attributed.removeAttribute(.strikethroughStyle, range: contentRange)
        }
    }

    private func applyBulletList(
        range: NSRange,
        prefixLength: Int,
        level: Int,
        attributed: NSMutableAttributedString,
        nsText: NSMutableString
    ) {
        let levelIndent = MarkdownEditorTheme.indentPerLevel * CGFloat(level)

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 4
        style.firstLineHeadIndent = levelIndent
        style.headIndent = levelIndent + Self.bulletTextWidth
        attributed.addAttribute(.paragraphStyle, value: style, range: range)

        let prefixString = nsText.substring(with: NSRange(location: range.location, length: prefixLength))
        let leadingSpaceCount = prefixString.prefix(while: { $0 == " " || $0 == "\t" }).count
        if leadingSpaceCount > 0 {
            attributed.addAttribute(.foregroundColor, value: PlatformColor.clear, range: NSRange(location: range.location, length: leadingSpaceCount))
        }

        let markerRange = NSRange(location: range.location + leadingSpaceCount, length: 1)
        attributed.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: markerRange)
    }

    private func applyOrderedList(
        range: NSRange,
        prefixLength: Int,
        level: Int,
        attributed: NSMutableAttributedString,
        nsText: NSMutableString
    ) {
        let levelIndent = MarkdownEditorTheme.indentPerLevel * CGFloat(level)
        let prefixString = nsText.substring(with: NSRange(location: range.location, length: prefixLength))
        let visiblePrefix = String(prefixString.drop(while: { $0 == " " || $0 == "\t" }))
        let prefixWidth = (visiblePrefix as NSString).size(withAttributes: [.font: MarkdownEditorTheme.bodyFont]).width

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 4
        style.firstLineHeadIndent = levelIndent
        style.headIndent = levelIndent + prefixWidth
        attributed.addAttribute(.paragraphStyle, value: style, range: range)
    }

    private func applyInlineFormatting(
        in range: NSRange,
        attributed: NSMutableAttributedString,
        nsText: NSMutableString
    ) {
        let string = nsText as String

        Self.boldRegex.enumerateMatches(in: string, range: range) { match, _, _ in
            guard let match else { return }
            let matchRange = match.range
            let currentFont = attributed.attribute(.font, at: matchRange.location, effectiveRange: nil) as? PlatformFont ?? MarkdownEditorTheme.bodyFont
            let boldFont = PlatformFont.systemFont(ofSize: currentFont.pointSize, weight: .bold)
            attributed.addAttribute(.font, value: boldFont, range: matchRange)
            dimDelimiters(matchRange: matchRange, delimiterLength: 2, attributed: attributed)
        }

        Self.italicRegex.enumerateMatches(in: string, range: range) { match, _, _ in
            guard let match else { return }
            let matchRange = match.range
            let currentFont = attributed.attribute(.font, at: matchRange.location, effectiveRange: nil) as? PlatformFont ?? MarkdownEditorTheme.bodyFont
            #if os(iOS)
            let descriptor = currentFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? currentFont.fontDescriptor
            let italicFont = PlatformFont(descriptor: descriptor, size: currentFont.pointSize)
            #elseif os(macOS)
            let descriptor = currentFont.fontDescriptor.withSymbolicTraits(.italic)
            let italicFont = PlatformFont(descriptor: descriptor, size: currentFont.pointSize) ?? currentFont
            #endif
            attributed.addAttribute(.font, value: italicFont, range: matchRange)
            dimDelimiters(matchRange: matchRange, delimiterLength: 1, attributed: attributed)
        }

        Self.codeRegex.enumerateMatches(in: string, range: range) { match, _, _ in
            guard let match else { return }
            let monoFont = PlatformFont.monospacedSystemFont(ofSize: MarkdownEditorTheme.bodySize - 1, weight: .regular)
            attributed.addAttributes([
                .font: monoFont,
                .foregroundColor: PlatformColor.secondaryLabel,
                .backgroundColor: PlatformColor.secondarySystemFill
            ], range: match.range)
        }
    }

    private func dimDelimiters(
        matchRange: NSRange,
        delimiterLength: Int,
        attributed: NSMutableAttributedString
    ) {
        let startDelimiter = NSRange(location: matchRange.location, length: delimiterLength)
        let endDelimiter = NSRange(location: matchRange.location + matchRange.length - delimiterLength, length: delimiterLength)
        attributed.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: startDelimiter)
        attributed.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: endDelimiter)
    }

    private func applyFrontmatterHiding(to attributed: NSMutableAttributedString, range: NSRange) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 0
        style.paragraphSpacing = 0
        style.minimumLineHeight = 0.1
        style.maximumLineHeight = 0.1
        attributed.addAttributes([
            .font: PlatformFont.systemFont(ofSize: 0.1),
            .foregroundColor: PlatformColor.clear,
            .paragraphStyle: style
        ], range: range)
    }

    private func frontmatterEnd(in nsText: NSMutableString) -> Int {
        guard nsText.length >= 3 else { return 0 }
        guard nsText.substring(with: NSRange(location: 0, length: 3)) == "---" else { return 0 }

        let searchRange = NSRange(location: 3, length: nsText.length - 3)
        let closeRange = nsText.range(of: "\n---", range: searchRange)
        guard closeRange.location != NSNotFound else { return 0 }
        return NSMaxRange(closeRange)
    }

    private func firstHeadingLocation(in nsText: NSMutableString, contentStart: Int) -> Int {
        guard contentStart < nsText.length else { return -1 }

        var position = contentStart
        while position < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: position, length: 0))
            let line = nsText.substring(with: lineRange)
            if line.hasPrefix("#") {
                return lineRange.location
            }
            position = NSMaxRange(lineRange)
            if position == lineRange.location {
                break
            }
        }

        return -1
    }
}
