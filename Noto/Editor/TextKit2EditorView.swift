import SwiftUI
import os.log

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "TextKit2Editor")

enum NoteEditorCommands {
    static let toggleStrikethrough = Notification.Name("NoteEditorCommands.toggleStrikethrough")
    static let toggleBold = Notification.Name("NoteEditorCommands.toggleBold")
    static let toggleItalic = Notification.Name("NoteEditorCommands.toggleItalic")
    static let toggleHyperlink = Notification.Name("NoteEditorCommands.toggleHyperlink")

    static func requestToggleStrikethrough() {
        NotificationCenter.default.post(name: toggleStrikethrough, object: nil)
    }

    static func requestToggleBold() {
        NotificationCenter.default.post(name: toggleBold, object: nil)
    }

    static func requestToggleItalic() {
        NotificationCenter.default.post(name: toggleItalic, object: nil)
    }

    static func requestToggleHyperlink() {
        NotificationCenter.default.post(name: toggleHyperlink, object: nil)
    }
}

// MARK: - Platform Aliases

#if os(iOS)
private typealias PlatformFont = UIFont
private typealias PlatformColor = UIColor
private typealias PlatformImage = UIImage
#elseif os(macOS)
private typealias PlatformFont = NSFont
private typealias PlatformColor = NSColor
private typealias PlatformImage = NSImage
#endif

// MARK: - MarkdownImageLink

struct MarkdownImageLink: Equatable {
    let urlString: String
    let altText: String

    var url: URL? {
        URL(string: urlString)
    }
}

enum MarkdownImageLinkParser {
    private static let linkRegex = try! NSRegularExpression(
        pattern: #"^\s*(!)?\[([^\]]*)\]\(([^)\s]+)\)\s*$"#
    )
    private static let imageURLHints = [
        ".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif", ".heic", ".heif", ".tiff", ".bmp",
        "substackcdn.com/image/fetch",
    ]

    static func parse(from text: String) -> MarkdownImageLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let nsText = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let match = linkRegex.firstMatch(in: trimmed, range: fullRange),
              match.numberOfRanges >= 4 else {
            return nil
        }

        let hasImagePrefix = match.range(at: 1).location != NSNotFound
        let altText = nsText.substring(with: match.range(at: 2))
        let urlString = nsText.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return nil }

        let isEmptyImageLink = altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && looksLikeImageURL(urlString)
        guard hasImagePrefix || isEmptyImageLink else { return nil }

        return MarkdownImageLink(urlString: urlString, altText: altText)
    }

    static func looksLikeImageURL(_ urlString: String) -> Bool {
        let decoded = (urlString.removingPercentEncoding ?? urlString).lowercased()
        return imageURLHints.contains { decoded.contains($0) }
    }
}

// MARK: - XMLLikeTagParser

struct XMLLikeTagBlock: Equatable {
    let tagName: String
    let openingLineRange: NSRange
    let closingLineRange: NSRange
    let collapsedContentRange: NSRange
}

enum XMLLikeTagParser {
    private static let openingRegex = try! NSRegularExpression(
        pattern: #"^\s*<([A-Za-z][A-Za-z0-9_:\-]*)(?:\s+[^<>]*)?>\s*$"#
    )
    private static let closingRegex = try! NSRegularExpression(
        pattern: #"^\s*</([A-Za-z][A-Za-z0-9_:\-]*)>\s*$"#
    )
    private static let commentMarkerRegex = try! NSRegularExpression(
        pattern: #"^\s*<!--\s*([A-Za-z][A-Za-z0-9_:\-]*):(start|end)\s*-->\s*$"#
    )

    static func isTagLine(_ text: String) -> Bool {
        openingTagName(in: text) != nil || closingTagName(in: text) != nil
    }

    static func blocks(in text: String) -> [XMLLikeTagBlock] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var stack: [(name: String, lineRange: NSRange)] = []
        var blocks: [XMLLikeTagBlock] = []
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let visibleLineRange = lineRangeWithoutTrailingNewline(lineRange, in: nsText)
            let line = nsText.substring(with: visibleLineRange)

            if let name = openingTagName(in: line) {
                stack.append((name, lineRange))
            } else if let name = closingTagName(in: line),
                      let stackIndex = stack.lastIndex(where: { $0.name == name }) {
                let opening = stack.remove(at: stackIndex)
                stack.removeSubrange(stackIndex..<stack.count)

                let collapsedLocation = NSMaxRange(opening.lineRange)
                let collapsedEnd = NSMaxRange(lineRange)
                if collapsedEnd > collapsedLocation {
                    blocks.append(XMLLikeTagBlock(
                        tagName: name,
                        openingLineRange: opening.lineRange,
                        closingLineRange: lineRange,
                        collapsedContentRange: NSRange(
                            location: collapsedLocation,
                            length: collapsedEnd - collapsedLocation
                        )
                    ))
                }
            }

            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return blocks.sorted { $0.openingLineRange.location < $1.openingLineRange.location }
    }

    private static func openingTagName(in text: String) -> String? {
        if let commentMarker = commentMarker(in: text),
           commentMarker.role == "start" {
            return commentMarker.name
        }

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("</"),
              !trimmed.hasPrefix("<!--"),
              !trimmed.hasSuffix("/>") else {
            return nil
        }
        return matchName(in: text, regex: openingRegex)
    }

    private static func closingTagName(in text: String) -> String? {
        if let commentMarker = commentMarker(in: text),
           commentMarker.role == "end" {
            return commentMarker.name
        }

        return matchName(in: text, regex: closingRegex)
    }

    private static func commentMarker(in text: String) -> (name: String, role: String)? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = commentMarkerRegex.firstMatch(in: text, range: range),
              match.numberOfRanges > 2 else {
            return nil
        }

        return (
            name: nsText.substring(with: match.range(at: 1)),
            role: nsText.substring(with: match.range(at: 2))
        )
    }

    private static func matchName(in text: String, regex: NSRegularExpression) -> String? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
    }

    private static func lineRangeWithoutTrailingNewline(_ range: NSRange, in text: NSString) -> NSRange {
        var length = range.length
        while length > 0 {
            let location = range.location + length - 1
            guard let scalar = UnicodeScalar(text.character(at: location)),
                  CharacterSet.newlines.contains(scalar) else {
                break
            }
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }
}

// MARK: - MarkdownBlockKind

/// Classifies a single paragraph of markdown by its leading syntax.
/// Self-contained — does not depend on the old block editor's BlockType.
enum MarkdownBlockKind: Equatable {
    case paragraph
    case heading(level: Int)
    case todo(checked: Bool, indent: Int)
    case bullet(indent: Int)
    case orderedList(number: Int, indent: Int)
    case frontmatter
    case imageLink(MarkdownImageLink)
    case xmlTag
    case collapsedXMLTagContent

    static func detect(from text: String) -> MarkdownBlockKind {
        let indentCount = text.prefix(while: { $0 == " " }).count
        let indent = indentCount / 2
        let stripped = String(text.dropFirst(indentCount))

        if let imageLink = MarkdownImageLinkParser.parse(from: stripped) {
            return .imageLink(imageLink)
        }

        if stripped.hasPrefix("- [ ] ") || stripped == "- [ ]" {
            return .todo(checked: false, indent: indent)
        }
        if stripped.hasPrefix("- [x] ") || stripped == "- [x]" ||
            stripped.hasPrefix("- [X] ") || stripped == "- [X]" {
            return .todo(checked: true, indent: indent)
        }
        if indent == 0 {
            if stripped.hasPrefix("### ") { return .heading(level: 3) }
            if stripped.hasPrefix("## ") { return .heading(level: 2) }
            if stripped.hasPrefix("# ") { return .heading(level: 1) }
        }
        if stripped.hasPrefix("- ") || stripped.hasPrefix("* ") || stripped.hasPrefix("• ") {
            return .bullet(indent: indent)
        }
        if let dotIdx = stripped.firstIndex(of: "."),
           dotIdx > stripped.startIndex,
           stripped[stripped.startIndex..<dotIdx].allSatisfy(\.isNumber) {
            let afterDot = stripped.index(after: dotIdx)
            if afterDot < stripped.endIndex && stripped[afterDot] == " " {
                let number = Int(stripped[stripped.startIndex..<dotIdx]) ?? 1
                return .orderedList(number: number, indent: indent)
            }
        }
        if XMLLikeTagParser.isTagLine(stripped) {
            return .xmlTag
        }
        return .paragraph
    }

    /// Number of characters in the markdown prefix (including leading indent spaces).
    func prefixLength(in text: String) -> Int {
        let indentCount = text.prefix(while: { $0 == " " }).count
        let stripped = String(text.dropFirst(indentCount))
        switch self {
        case .heading(let level): return level + 1
        case .todo:
            if stripped.hasPrefix("- [ ] ") || stripped.hasPrefix("- [x] ") || stripped.hasPrefix("- [X] ") {
                return indentCount + 6
            }
            if stripped == "- [ ]" || stripped == "- [x]" || stripped == "- [X]" {
                return indentCount + 5
            }
            return 0
        case .bullet:
            return indentCount + (stripped.hasPrefix("- ") || stripped.hasPrefix("* ") || stripped.hasPrefix("• ") ? 2 : 0)
        case .orderedList(let number, _):
            let marker = "\(number). "
            return indentCount + (stripped.hasPrefix(marker) ? marker.count : 0)
        case .frontmatter, .paragraph, .imageLink, .xmlTag, .collapsedXMLTagContent: return 0
        }
    }
}

// MARK: - MarkdownSemanticAnalyzer

struct MarkdownRenderableBlock: Equatable {
    let kind: MarkdownBlockKind
    let effectiveKind: MarkdownBlockKind
    let paragraphRange: NSRange
    let visibleLineRange: NSRange
    let lineText: String
    let isCollapsedXMLTagContent: Bool

    var isNativeOverlayEligible: Bool {
        guard !isCollapsedXMLTagContent else { return false }
        switch kind {
        case .todo, .imageLink:
            return true
        case .paragraph, .heading, .bullet, .orderedList, .frontmatter, .xmlTag, .collapsedXMLTagContent:
            return false
        }
    }
}

enum MarkdownSemanticAnalyzer {
    static func renderableBlocks(
        in text: String,
        collapsedXMLTagRanges: [NSRange] = []
    ) -> [MarkdownRenderableBlock] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var blocks: [MarkdownRenderableBlock] = []
        var paragraphLocation = 0
        while paragraphLocation < nsText.length {
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: paragraphLocation, length: 0))
            let visibleLineRange = MarkdownLineRanges.visibleLineRange(from: paragraphRange, in: nsText)
            let lineText = nsText.substring(with: visibleLineRange)
            let isCollapsed = collapsedXMLTagRanges.contains { collapsedRange in
                NSIntersectionRange(visibleLineRange, collapsedRange).length > 0
            }
            let kind: MarkdownBlockKind = MarkdownFrontmatter.contains(position: paragraphRange.location, in: text)
                ? .frontmatter
                : MarkdownBlockKind.detect(from: lineText)

            blocks.append(MarkdownRenderableBlock(
                kind: kind,
                effectiveKind: isCollapsed ? .collapsedXMLTagContent : kind,
                paragraphRange: paragraphRange,
                visibleLineRange: visibleLineRange,
                lineText: lineText,
                isCollapsedXMLTagContent: isCollapsed
            ))

            let nextLocation = NSMaxRange(paragraphRange)
            guard nextLocation > paragraphLocation else { break }
            paragraphLocation = nextLocation
        }

        return blocks
    }
}

// MARK: - MarkdownFrontmatter

enum MarkdownFrontmatter {
    static func range(in fullText: String) -> NSRange? {
        guard fullText.hasPrefix("---\n") || fullText.hasPrefix("---\r\n") else { return nil }

        let searchStart = fullText.index(fullText.startIndex, offsetBy: min(4, fullText.count))
        guard searchStart < fullText.endIndex,
              let closeRange = fullText.range(of: "\n---", range: searchStart..<fullText.endIndex) else {
            return nil
        }

        let location = 0
        let length = fullText.distance(from: fullText.startIndex, to: closeRange.upperBound)
        return NSRange(location: location, length: length)
    }

    static func contains(position: Int, in fullText: String) -> Bool {
        guard let range = range(in: fullText) else { return false }
        return NSLocationInRange(position, range)
    }
}

// MARK: - MarkdownTheme

/// Declarative visual contract for markdown rendering. Platform adapters below
/// translate these values into UIKit/AppKit fonts, colors, and controls.
enum MarkdownVisualSpec {
    enum FontWeight {
        case regular
        case medium
        case semibold
        case bold
    }

    struct Font {
        let pointSize: CGFloat
        let weight: FontWeight
        var isMonospaced = false
    }

    static let bodyFont = Font(pointSize: 17, weight: .regular)
    static let h1Font = Font(pointSize: 28, weight: .bold)
    static let h2Font = Font(pointSize: 22, weight: .bold)
    static let h3Font = Font(pointSize: 18, weight: .semibold)
    static let codeFont = Font(pointSize: 16, weight: .regular, isMonospaced: true)

    static let listBaseIndent: CGFloat = 12
    static let listIndentStep: CGFloat = 4
    static let listMarkerTextGap: CGFloat = 8
    static let todoPrefixVisualWidth: CGFloat = 2
    static let hyperlinkSyntaxVisualWidth: CGFloat = 0.01
    static let todoTextStartOffset: CGFloat = 28
    static let todoControlSize: CGFloat = 28
    static let todoSymbolSize: CGFloat = 18
    static let todoMarkerContentLeadingAdjustment: CGFloat = 12
    static let todoControlLeadingInset: CGFloat = 2
    static let todoControlImageLeadingInset: CGFloat = 5
    static let imagePreviewReservedHeight: CGFloat = 300
    static let imagePreviewVerticalPadding: CGFloat = 8
    static let imagePreviewCornerRadius: CGFloat = 8
    static let imagePreviewBackingFontSize: CGFloat = 0.01
    static let xmlTagCollapseControlSize: CGFloat = 24
    static let collapsedXMLTagContentFontSize: CGFloat = 0.01

    static func listLeadingOffset(for indentLevel: Int) -> CGFloat {
        listBaseIndent + CGFloat(indentLevel) * listIndentStep
    }

    static func font(for kind: MarkdownBlockKind) -> Font {
        switch kind {
        case .heading(1): return h1Font
        case .heading(2): return h2Font
        case .heading(3): return h3Font
        case .xmlTag: return codeFont
        case .collapsedXMLTagContent: return bodyFont
        default: return bodyFont
        }
    }
}

/// Platform adapter for markdown rendering.
private enum MarkdownTheme {
    static let bodyFont = platformFont(MarkdownVisualSpec.bodyFont)
    static let h1Font = platformFont(MarkdownVisualSpec.h1Font)
    static let h2Font = platformFont(MarkdownVisualSpec.h2Font)
    static let h3Font = platformFont(MarkdownVisualSpec.h3Font)
    static let codeFont = platformFont(MarkdownVisualSpec.codeFont)
    static let listBaseIndent = MarkdownVisualSpec.listBaseIndent
    static let listIndentStep = MarkdownVisualSpec.listIndentStep
    static let listMarkerTextGap = MarkdownVisualSpec.listMarkerTextGap
    static let todoPrefixVisualWidth = MarkdownVisualSpec.todoPrefixVisualWidth
    static let todoTextStartOffset = MarkdownVisualSpec.todoTextStartOffset

    #if os(iOS)
    static let bodyColor: PlatformColor = AppTheme.uiPrimaryText
    static let prefixColor: PlatformColor = AppTheme.uiMutedText
    static let checkedColor: PlatformColor = AppTheme.uiSecondaryText
    static let codeColor: PlatformColor = AppTheme.uiSecondaryText
    static let codeBgColor: PlatformColor = AppTheme.uiCodeBackground
    static let linkColor: PlatformColor = .systemBlue
    #elseif os(macOS)
    static let bodyColor: PlatformColor = AppTheme.nsPrimaryText
    static let prefixColor: PlatformColor = AppTheme.nsMutedText
    static let checkedColor: PlatformColor = AppTheme.nsSecondaryText
    static let codeColor: PlatformColor = AppTheme.nsSecondaryText
    static let codeBgColor: PlatformColor = AppTheme.nsCodeBackground
    static let linkColor: PlatformColor = .linkColor
    #endif

    static func font(for kind: MarkdownBlockKind) -> PlatformFont {
        switch kind {
        case .heading(1): return h1Font
        case .heading(2): return h2Font
        case .heading(3): return h3Font
        default: return bodyFont
        }
    }

    static func listLeadingOffset(for indentLevel: Int) -> CGFloat {
        MarkdownVisualSpec.listLeadingOffset(for: indentLevel)
    }

    static func platformFont(_ spec: MarkdownVisualSpec.Font) -> PlatformFont {
        if spec.isMonospaced {
            return PlatformFont.monospacedSystemFont(ofSize: spec.pointSize, weight: platformWeight(spec.weight))
        }

        return PlatformFont.systemFont(ofSize: spec.pointSize, weight: platformWeight(spec.weight))
    }

    #if os(iOS)
    private static func platformWeight(_ weight: MarkdownVisualSpec.FontWeight) -> UIFont.Weight {
        switch weight {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
    #elseif os(macOS)
    private static func platformWeight(_ weight: MarkdownVisualSpec.FontWeight) -> NSFont.Weight {
        switch weight {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
    #endif
}

// MARK: - MarkdownParagraphStyler

/// Builds an NSAttributedString for a single markdown paragraph.
/// Called by the NSTextContentStorageDelegate — only the changed paragraph
/// gets re-styled, not the entire document.
enum MarkdownParagraphStyler {
    static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    static let italicRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
    static let strikethroughRegex = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
    static let codeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)

    static func paragraphStyle(for kind: MarkdownBlockKind, text: String = "") -> NSParagraphStyle {
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 4

        switch kind {
        case .heading(let level):
            let spacing: CGFloat = level == 1 ? 16 : level == 2 ? 12 : 8
            paraStyle.paragraphSpacingBefore = spacing
            paraStyle.paragraphSpacing = spacing * 0.4

        case .todo(_, let indent):
            let indentPt = MarkdownTheme.listLeadingOffset(for: indent)
            let contentIndent = listContentIndent(for: kind, text: text)
            paraStyle.firstLineHeadIndent = indentPt + contentIndent - MarkdownTheme.todoPrefixVisualWidth
            paraStyle.headIndent = indentPt + contentIndent
            paraStyle.paragraphSpacingBefore = 4

        case .bullet(let indent):
            let indentPt = MarkdownTheme.listLeadingOffset(for: indent)
            let contentIndent = listContentIndent(for: kind, text: text)
            paraStyle.firstLineHeadIndent = indentPt
            paraStyle.headIndent = indentPt + contentIndent
            paraStyle.paragraphSpacingBefore = 4

        case .orderedList(_, let indent):
            let indentPt = MarkdownTheme.listLeadingOffset(for: indent)
            let contentIndent = listContentIndent(for: kind, text: text)
            paraStyle.firstLineHeadIndent = indentPt
            paraStyle.headIndent = indentPt + contentIndent
            paraStyle.paragraphSpacingBefore = 4

        case .frontmatter:
            break

        case .imageLink:
            paraStyle.lineSpacing = 0
            paraStyle.lineBreakMode = .byClipping
            paraStyle.minimumLineHeight = MarkdownVisualSpec.imagePreviewReservedHeight
            paraStyle.maximumLineHeight = MarkdownVisualSpec.imagePreviewReservedHeight
            paraStyle.paragraphSpacingBefore = 10
            paraStyle.paragraphSpacing = 12

        case .xmlTag:
            paraStyle.paragraphSpacingBefore = 4
            paraStyle.paragraphSpacing = 2

        case .collapsedXMLTagContent:
            paraStyle.lineSpacing = 0
            paraStyle.minimumLineHeight = MarkdownVisualSpec.collapsedXMLTagContentFontSize
            paraStyle.maximumLineHeight = MarkdownVisualSpec.collapsedXMLTagContentFontSize
            paraStyle.paragraphSpacingBefore = 0
            paraStyle.paragraphSpacing = 0

        case .paragraph:
            paraStyle.paragraphSpacingBefore = 6
        }

        return paraStyle
    }

    static func listContentIndent(for kind: MarkdownBlockKind, text: String) -> CGFloat {
        if case .todo = kind {
            return MarkdownTheme.todoTextStartOffset
        }

        let prefixLength = kind.prefixLength(in: text)
        guard prefixLength > 0 else { return 0 }

        let prefix = String(text.prefix(prefixLength))
        let font = MarkdownTheme.font(for: kind)
        let prefixWidth = ceil((prefix as NSString).size(withAttributes: [.font: font]).width)
        return prefixWidth
    }

    static func style(
        text: String,
        kind: MarkdownBlockKind,
        paragraphLocation: Int = 0,
        revealedHyperlinkRanges: [NSRange] = []
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributed.length)
        guard fullRange.length > 0 else {
            attributed.addAttributes([
                .font: MarkdownTheme.font(for: kind),
                .foregroundColor: kind == .frontmatter ? MarkdownTheme.prefixColor : MarkdownTheme.bodyColor,
                .paragraphStyle: paragraphStyle(for: kind, text: text),
            ], range: fullRange)
            return attributed
        }

        let paraStyle = paragraphStyle(for: kind, text: text)

        switch kind {
        case .heading:
            let font = MarkdownTheme.font(for: kind)
            attributed.addAttributes([
                .font: font,
                .foregroundColor: MarkdownTheme.bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)

        case .todo(let checked, _):
            attributed.addAttributes([
                .font: MarkdownTheme.bodyFont,
                .foregroundColor: checked ? MarkdownTheme.checkedColor : MarkdownTheme.bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
            if checked {
                let pfxLen = kind.prefixLength(in: text)
                if pfxLen < fullRange.length {
                    attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                                            range: NSRange(location: pfxLen, length: fullRange.length - pfxLen))
                }
            }

        case .bullet:
            attributed.addAttributes([
                .font: MarkdownTheme.bodyFont,
                .foregroundColor: MarkdownTheme.bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)

        case .orderedList:
            attributed.addAttributes([
                .font: MarkdownTheme.bodyFont,
                .foregroundColor: MarkdownTheme.bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)

        case .frontmatter:
            attributed.addAttributes([
                .font: MarkdownTheme.codeFont,
                .foregroundColor: MarkdownTheme.prefixColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
            return attributed // No inline formatting for frontmatter

        case .imageLink:
            attributed.addAttributes([
                .font: PlatformFont.systemFont(
                    ofSize: MarkdownVisualSpec.imagePreviewBackingFontSize,
                    weight: .regular
                ),
                .foregroundColor: PlatformColor.clear,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
            return attributed

        case .xmlTag:
            attributed.addAttributes([
                .font: MarkdownTheme.codeFont,
                .foregroundColor: MarkdownTheme.prefixColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
            return attributed

        case .collapsedXMLTagContent:
            attributed.addAttributes([
                .font: PlatformFont.systemFont(
                    ofSize: MarkdownVisualSpec.collapsedXMLTagContentFontSize,
                    weight: .regular
                ),
                .foregroundColor: PlatformColor.clear,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
            return attributed

        case .paragraph:
            attributed.addAttributes([
                .font: MarkdownTheme.bodyFont,
                .foregroundColor: MarkdownTheme.bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
        }

        // Dim prefix characters. Todo prefixes stay in the backing markdown but
        // are hidden because a todo layout fragment draws the marker in their place.
        let pfxLen = kind.prefixLength(in: text)
        if pfxLen > 0 && pfxLen <= fullRange.length {
            let prefixColor: PlatformColor
            if case .todo = kind {
                prefixColor = .clear
                let hiddenPrefixLength = todoHiddenPrefixLength(prefixLength: pfxLen, fullLength: fullRange.length)
                attributed.addAttribute(
                    .font,
                    value: PlatformFont.systemFont(ofSize: MarkdownTheme.todoPrefixVisualWidth, weight: .regular),
                    range: NSRange(location: 0, length: hiddenPrefixLength)
                )
            } else {
                prefixColor = MarkdownTheme.prefixColor
            }
            attributed.addAttribute(.foregroundColor, value: prefixColor,
                                    range: NSRange(location: 0, length: pfxLen))
            applyListPrefixStyling(to: attributed, kind: kind, prefixLength: pfxLen)
        }

        // Inline formatting
        applyInlineStyles(to: attributed, baseFont: MarkdownTheme.font(for: kind))
        applyHyperlinkStyles(
            to: attributed,
            paragraphLocation: paragraphLocation,
            revealedHyperlinkRanges: revealedHyperlinkRanges
        )

        return attributed
    }

    private static func todoHiddenPrefixLength(prefixLength: Int, fullLength: Int) -> Int {
        guard prefixLength == fullLength else { return prefixLength }
        return max(0, prefixLength - 1)
    }

    private static func applyListPrefixStyling(
        to attributed: NSMutableAttributedString,
        kind: MarkdownBlockKind,
        prefixLength: Int
    ) {
        let markerRange: NSRange
        switch kind {
        case .bullet(let indent):
            markerRange = NSRange(location: indent * 2, length: 1)
        case .orderedList(let number, let indent):
            markerRange = NSRange(location: indent * 2, length: "\(number).".count)
        case .todo(_, let indent):
            markerRange = NSRange(location: indent * 2, length: 5)
        default:
            return
        }

        if markerRange.location + markerRange.length <= attributed.length {
            if case .todo = kind {
                attributed.addAttribute(.foregroundColor, value: PlatformColor.clear, range: markerRange)
            } else {
                attributed.addAttributes([
                    .foregroundColor: MarkdownTheme.prefixColor,
                    .font: PlatformFont.systemFont(ofSize: MarkdownTheme.bodyFont.pointSize, weight: .semibold),
                ], range: markerRange)
            }
        }

    }

    private static func applyInlineStyles(to attributed: NSMutableAttributedString, baseFont: PlatformFont) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let string = attributed.string

        // Bold: **text**
        boldRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let r = match?.range else { return }
            attributed.addAttribute(.font, value: PlatformFont.systemFont(ofSize: baseFont.pointSize, weight: .bold), range: r)
            attributed.addAttribute(.foregroundColor, value: MarkdownTheme.prefixColor,
                                    range: NSRange(location: r.location, length: 2))
            attributed.addAttribute(.foregroundColor, value: MarkdownTheme.prefixColor,
                                    range: NSRange(location: r.location + r.length - 2, length: 2))
        }

        // Italic: *text*
        italicRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let r = match?.range else { return }
            #if os(iOS)
            let desc = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? baseFont.fontDescriptor
            let font = PlatformFont(descriptor: desc, size: baseFont.pointSize)
            #elseif os(macOS)
            let desc = baseFont.fontDescriptor.withSymbolicTraits(.italic)
            let font = PlatformFont(descriptor: desc, size: baseFont.pointSize) ?? baseFont
            #endif
            attributed.addAttribute(.font, value: font, range: r)
            attributed.addAttribute(.foregroundColor, value: MarkdownTheme.prefixColor,
                                    range: NSRange(location: r.location, length: 1))
            attributed.addAttribute(.foregroundColor, value: MarkdownTheme.prefixColor,
                                    range: NSRange(location: r.location + r.length - 1, length: 1))
        }

        // Strikethrough: ~~text~~
        strikethroughRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let r = match?.range, r.length >= 4 else { return }
            let contentRange = NSRange(location: r.location + 2, length: r.length - 4)
            if contentRange.length > 0 {
                attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            }
            attributed.addAttribute(.foregroundColor, value: MarkdownTheme.prefixColor,
                                    range: NSRange(location: r.location, length: 2))
            attributed.addAttribute(.foregroundColor, value: MarkdownTheme.prefixColor,
                                    range: NSRange(location: r.location + r.length - 2, length: 2))
        }

        // Code: `text`
        codeRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let r = match?.range else { return }
            attributed.addAttribute(.font, value: MarkdownTheme.codeFont, range: r)
            attributed.addAttribute(.foregroundColor, value: MarkdownTheme.codeColor, range: r)
            attributed.addAttribute(.backgroundColor, value: MarkdownTheme.codeBgColor, range: r)
        }
    }

    private static func applyHyperlinkStyles(
        to attributed: NSMutableAttributedString,
        paragraphLocation: Int,
        revealedHyperlinkRanges: [NSRange]
    ) {
        for match in HyperlinkMarkdown.matches(in: attributed.string) {
            guard let url = match.url else { continue }
            let isRevealed = revealedHyperlinkRanges.contains { revealedRange in
                NSEqualRanges(
                    revealedRange,
                    NSRange(location: paragraphLocation + match.fullRange.location, length: match.fullRange.length)
                )
            }

            if isRevealed {
                attributed.removeAttribute(.link, range: match.fullRange)
                attributed.addAttributes([
                    .font: MarkdownTheme.bodyFont,
                    .foregroundColor: MarkdownTheme.bodyColor,
                    .underlineStyle: 0,
                ], range: match.titleRange)
            } else {
                attributed.addAttributes([
                    .link: url,
                    .foregroundColor: MarkdownTheme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: match.titleRange)
            }

            let syntaxRanges = [
                NSRange(location: match.fullRange.location, length: 1),
                NSRange(location: NSMaxRange(match.titleRange), length: 2),
                match.urlRange,
                NSRange(location: NSMaxRange(match.urlRange), length: 1),
            ]
            for syntaxRange in syntaxRanges {
                if isRevealed {
                    addSyntaxColor(to: attributed, range: syntaxRange)
                } else {
                    hideSyntax(to: attributed, range: syntaxRange)
                }
            }
        }
    }

    private static func addSyntaxColor(to attributed: NSMutableAttributedString, range: NSRange) {
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= attributed.length else {
            return
        }

        attributed.addAttribute(.foregroundColor, value: MarkdownTheme.prefixColor, range: range)
    }

    private static func hideSyntax(to attributed: NSMutableAttributedString, range: NSRange) {
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= attributed.length else {
            return
        }

        attributed.addAttributes([
            .font: PlatformFont.systemFont(ofSize: MarkdownVisualSpec.hyperlinkSyntaxVisualWidth, weight: .regular),
            .foregroundColor: PlatformColor.clear,
            .underlineStyle: 0,
        ], range: range)
    }
}

// MARK: - MarkdownTypingAttributes

private enum MarkdownTypingAttributes {
    static func attributes(for documentText: String, selectionLocation: Int) -> [NSAttributedString.Key: Any] {
        let nsText = documentText as NSString
        guard selectionLocation <= nsText.length else {
            return baseAttributes(for: .paragraph, text: "")
        }

        let paragraphRange = nsText.paragraphRange(for: NSRange(location: selectionLocation, length: 0))
        var paragraphText = nsText.substring(with: paragraphRange)
        if paragraphText.hasSuffix("\n") {
            paragraphText = String(paragraphText.dropLast())
        }
        return baseAttributes(for: MarkdownBlockKind.detect(from: paragraphText), text: paragraphText)
    }

    private static func baseAttributes(for kind: MarkdownBlockKind, text: String) -> [NSAttributedString.Key: Any] {
        [
            .font: MarkdownTheme.font(for: kind),
            .foregroundColor: MarkdownTheme.bodyColor,
            .paragraphStyle: MarkdownParagraphStyler.paragraphStyle(for: kind, text: text),
        ]
    }
}

// MARK: - MarkdownParagraph

/// Custom NSTextParagraph carrying markdown block-kind metadata.
/// The content-storage delegate returns these so each paragraph in the
/// element tree knows its semantic type.
final class MarkdownParagraph: NSTextParagraph {
    let blockKind: MarkdownBlockKind

    init(attributedString: NSAttributedString, blockKind: MarkdownBlockKind) {
        self.blockKind = blockKind
        super.init(attributedString: attributedString)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - HiddenFrontmatterLayoutFragment

final class HiddenFrontmatterLayoutFragment: NSTextLayoutFragment {
    override var layoutFragmentFrame: CGRect {
        CGRect(origin: super.layoutFragmentFrame.origin, size: .zero)
    }

    override var renderingSurfaceBounds: CGRect {
        .zero
    }

    #if os(iOS)
    override func draw(at point: CGPoint, in context: CGContext) {
        // Frontmatter remains in the text storage but produces no visible output.
    }
    #elseif os(macOS)
    override func draw(at point: CGPoint, in context: CGContext) {
        // Frontmatter remains in the text storage but produces no visible output.
    }
    #endif
}

// MARK: - TodoMarkerGeometry

enum TodoMarkerGeometry {
    static func markerRect(
        contentLeadingX: CGFloat,
        lineMidY: CGFloat
    ) -> CGRect {
        let controlSize = MarkdownVisualSpec.todoControlSize
        let symbolSize = MarkdownVisualSpec.todoSymbolSize
        let symbolLeading = contentLeadingX
            - MarkdownVisualSpec.todoTextStartOffset
            - MarkdownVisualSpec.todoMarkerContentLeadingAdjustment
        return CGRect(
            x: symbolLeading,
            y: lineMidY - symbolSize / 2,
            width: symbolSize,
            height: symbolSize
        ).integral.insetBy(dx: -max(0, (controlSize - symbolSize) / 2), dy: -max(0, (controlSize - symbolSize) / 2))
    }

    static func markerRect(
        textContainerOriginX: CGFloat,
        lineMidY: CGFloat,
        indent: Int
    ) -> CGRect {
        let contentLeadingX = textContainerOriginX
            + MarkdownVisualSpec.listLeadingOffset(for: indent)
            + MarkdownVisualSpec.todoTextStartOffset
        return markerRect(contentLeadingX: contentLeadingX, lineMidY: lineMidY)
    }
}

// MARK: - TodoLayoutFragment

final class TodoLayoutFragment: NSTextLayoutFragment {
    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard let paragraph = textElement as? MarkdownParagraph,
              case .todo(let checked, _) = paragraph.blockKind else {
            return
        }

        let markerAnchorFrame = textLineFragments.first?.typographicBounds ?? layoutFragmentFrame
        let markerRect = TodoMarkerGeometry.markerRect(
            contentLeadingX: point.x + markerAnchorFrame.minX + MarkdownVisualSpec.todoTextStartOffset,
            lineMidY: point.y + markerAnchorFrame.midY
        )
        drawTodoMarker(checked: checked, in: markerRect, context: context)
    }

    static func markerRect(
        fragmentFrame: CGRect,
        point: CGPoint = .zero,
        indent: Int
    ) -> CGRect {
        TodoMarkerGeometry.markerRect(
            textContainerOriginX: point.x,
            lineMidY: point.y + fragmentFrame.midY,
            indent: indent
        )
    }

    private func drawTodoMarker(checked: Bool, in rect: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        let lineWidth: CGFloat = 2
        let circleRect = rect.insetBy(dx: (rect.width - MarkdownVisualSpec.todoSymbolSize) / 2,
                                      dy: (rect.height - MarkdownVisualSpec.todoSymbolSize) / 2)
        let markerColor = checked ? MarkdownTheme.checkedColor : MarkdownTheme.prefixColor

        #if os(iOS)
        context.setStrokeColor(markerColor.cgColor)
        context.setFillColor(markerColor.cgColor)
        #elseif os(macOS)
        context.setStrokeColor(markerColor.cgColor)
        context.setFillColor(markerColor.cgColor)
        #endif
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: circleRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))

        guard checked else { return }
        let checkPath = CGMutablePath()
        checkPath.move(to: CGPoint(x: circleRect.minX + circleRect.width * 0.28, y: circleRect.midY))
        checkPath.addLine(to: CGPoint(x: circleRect.minX + circleRect.width * 0.44, y: circleRect.maxY - circleRect.height * 0.30))
        checkPath.addLine(to: CGPoint(x: circleRect.maxX - circleRect.width * 0.24, y: circleRect.minY + circleRect.height * 0.28))
        context.addPath(checkPath)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }
}

// MARK: - ImageLayoutFragment

enum ImageFragmentGeometry {
    static func imageRect(
        fragmentFrame: CGRect,
        point: CGPoint = .zero,
        availableWidth: CGFloat? = nil
    ) -> CGRect {
        let verticalPadding = MarkdownVisualSpec.imagePreviewVerticalPadding
        let resolvedWidth = max(
            fragmentFrame.width,
            max(0, (availableWidth ?? fragmentFrame.width) - point.x)
        )
        return CGRect(
            x: point.x,
            y: point.y + verticalPadding,
            width: resolvedWidth,
            height: max(0, fragmentFrame.height - verticalPadding * 2)
        ).integral
    }

    static func aspectFillRect(
        imageSize: CGSize,
        in bounds: CGRect
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return bounds
        }

        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }
}

final class ImageLayoutFragment: NSTextLayoutFragment {
    override var renderingSurfaceBounds: CGRect {
        let baseBounds = super.renderingSurfaceBounds
        let targetWidth = max(baseBounds.width, expandedRenderingWidth())
        let targetHeight = max(baseBounds.height, layoutFragmentFrame.height)
        return CGRect(x: 0, y: baseBounds.minY, width: targetWidth, height: targetHeight)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard let paragraph = textElement as? MarkdownParagraph,
              case .imageLink(let imageLink) = paragraph.blockKind else {
            return
        }

        let imageRect = ImageFragmentGeometry.imageRect(
            fragmentFrame: layoutFragmentFrame,
            point: point,
            availableWidth: textLayoutManager?.usageBoundsForTextContainer.width
        )
        guard imageRect.width > 0, imageRect.height > 0 else { return }

        context.saveGState()
        defer { context.restoreGState() }

        let clipPath = CGPath(
            roundedRect: imageRect,
            cornerWidth: MarkdownVisualSpec.imagePreviewCornerRadius,
            cornerHeight: MarkdownVisualSpec.imagePreviewCornerRadius,
            transform: nil
        )
        context.addPath(clipPath)
        context.clip()

        #if os(iOS)
        context.setFillColor(AppTheme.uiCodeBackground.cgColor)
        #elseif os(macOS)
        context.setFillColor(AppTheme.nsCodeBackground.cgColor)
        #endif
        context.fill(imageRect)

        guard let url = imageLink.url,
              let image = MarkdownImageLoader.cachedImage(for: url) else {
            return
        }

        let drawRect = ImageFragmentGeometry.aspectFillRect(imageSize: image.size, in: imageRect)
        #if os(iOS)
        image.draw(in: drawRect)
        #elseif os(macOS)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        #endif
    }

    private func expandedRenderingWidth() -> CGFloat {
        let usageWidth = textLayoutManager?.usageBoundsForTextContainer.width ?? 0
        if usageWidth > 0 {
            return max(layoutFragmentFrame.width, usageWidth - layoutFragmentFrame.minX)
        }

        let containerWidth = textLayoutManager?.textContainer?.size.width ?? 0
        if containerWidth.isFinite && containerWidth > 0 {
            return max(layoutFragmentFrame.width, containerWidth - layoutFragmentFrame.minX)
        }

        return layoutFragmentFrame.width
    }
}

// MARK: - MarkdownImageLoader

private enum MarkdownImageLoader {
    private static let cache = NSCache<NSURL, PlatformImage>()

    static func cachedImage(for url: URL) -> PlatformImage? {
        cache.object(forKey: url as NSURL)
    }

    static func load(url: URL, completion: @escaping (PlatformImage?) -> Void) {
        if let cached = cachedImage(for: url) {
            completion(cached)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap { PlatformImage(data: $0) }
            if let image {
                cache.setObject(image, forKey: url as NSURL)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
}

// MARK: - MarkdownTextDelegate

/// The heart of the TextKit 2 integration.
///
/// Implements **NSTextContentStorageDelegate** to intercept paragraph creation.
/// For each paragraph the content storage builds, we return a styled
/// `MarkdownParagraph` with the correct fonts, colors, and indentation.
/// Only the *changed* paragraph is re-styled — not the whole document.
final class MarkdownTextDelegate: NSObject, NSTextContentStorageDelegate, NSTextLayoutManagerDelegate {
    var revealedHyperlinkRanges: [NSRange] = []
    var collapsedXMLTagRanges: [NSRange] = []
    var requestImageLoad: ((URL) -> Void)?

    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard let textStorage = textContentStorage.textStorage,
              range.location + range.length <= textStorage.length else { return nil }

        let original = textStorage.attributedSubstring(from: range).string

        // Strip trailing newline for block-kind detection
        let text = original.hasSuffix("\n") ? String(original.dropLast()) : original

        // Detect kind — frontmatter needs position-aware detection
        let kind: MarkdownBlockKind
        if collapsedXMLTagRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
            kind = .collapsedXMLTagContent
        } else if MarkdownFrontmatter.contains(position: range.location, in: textStorage.string) {
            kind = .frontmatter
        } else {
            kind = MarkdownBlockKind.detect(from: text)
        }

        // Style the visible text
        let styled = MarkdownParagraphStyler.style(
            text: text,
            kind: kind,
            paragraphLocation: range.location,
            revealedHyperlinkRanges: revealedHyperlinkRanges
        )

        // Re-append the trailing newline so the paragraph's character count
        // matches the backing-store range that TextKit expects.
        let result = NSMutableAttributedString(attributedString: styled)
        if original.hasSuffix("\n") {
            result.append(NSAttributedString(
                string: "\n",
                attributes: newlineAttributes(for: kind, text: text)
            ))
        }

        return MarkdownParagraph(attributedString: result, blockKind: kind)
    }

    private func newlineAttributes(for kind: MarkdownBlockKind, text: String) -> [NSAttributedString.Key: Any] {
        if case .imageLink = kind {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 0
            paragraphStyle.minimumLineHeight = MarkdownVisualSpec.collapsedXMLTagContentFontSize
            paragraphStyle.maximumLineHeight = MarkdownVisualSpec.collapsedXMLTagContentFontSize
            paragraphStyle.paragraphSpacingBefore = 0
            paragraphStyle.paragraphSpacing = 0
            return [
                .font: PlatformFont.systemFont(
                    ofSize: MarkdownVisualSpec.collapsedXMLTagContentFontSize,
                    weight: .regular
                ),
                .foregroundColor: PlatformColor.clear,
                .paragraphStyle: paragraphStyle,
            ]
        }

        return [
            .font: MarkdownTheme.font(for: kind),
            .foregroundColor: MarkdownTheme.bodyColor,
            .paragraphStyle: MarkdownParagraphStyler.paragraphStyle(for: kind, text: text),
        ]
    }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        layoutFragment(for: textElement)
    }

    func layoutFragment(for textElement: NSTextElement) -> NSTextLayoutFragment {
        guard let paragraph = textElement as? MarkdownParagraph else {
            return NSTextLayoutFragment(textElement: textElement, range: nil)
        }

        if case .imageLink(let imageLink) = paragraph.blockKind {
            if let url = imageLink.url,
               MarkdownImageLoader.cachedImage(for: url) == nil {
                requestImageLoad?(url)
            }
            return ImageLayoutFragment(textElement: textElement, range: nil)
        }

        if isTodo(paragraph.blockKind) {
            return TodoLayoutFragment(textElement: textElement, range: nil)
        }

        if paragraph.blockKind == .frontmatter || paragraph.blockKind == .collapsedXMLTagContent {
            return HiddenFrontmatterLayoutFragment(textElement: textElement, range: nil)
        }

        return NSTextLayoutFragment(textElement: textElement, range: nil)
    }

    private func isTodo(_ kind: MarkdownBlockKind) -> Bool {
        if case .todo = kind {
            return true
        }
        return false
    }
}

// MARK: - Shared Coordinator

final class TextKit2EditorCoordinator {
    @Binding var text: String
    var onTextChange: ((String) -> Void)?
    var isUpdatingText = false
    let autoFocus: Bool
    private(set) var isApplyingEditorText = false
    private(set) var lastPublishedText: String

    init(text: Binding<String>, onTextChange: ((String) -> Void)?, autoFocus: Bool) {
        _text = text
        self.onTextChange = onTextChange
        self.autoFocus = autoFocus
        self.lastPublishedText = text.wrappedValue
    }

    func publishEditorText(_ newText: String) {
        guard !isApplyingEditorText else { return }
        guard newText != lastPublishedText else { return }
        DebugTrace.record("editor publish \(DebugTrace.textSummary(newText))")
        isUpdatingText = true
        text = newText
        lastPublishedText = newText
        isUpdatingText = false
        onTextChange?(newText)
    }

    func beginApplyingEditorText(_ text: String) {
        isApplyingEditorText = true
        lastPublishedText = text
    }

    func finishApplyingEditorText() {
        isApplyingEditorText = false
    }

    func commitAppliedEditorText(_ newText: String) {
        isApplyingEditorText = false
        guard newText != text else {
            lastPublishedText = newText
            return
        }

        DebugTrace.record("editor commit applied \(DebugTrace.textSummary(newText))")
        isUpdatingText = true
        text = newText
        lastPublishedText = newText
        isUpdatingText = false
        onTextChange?(newText)
    }

    func typingAttributes(for documentText: String, selectionLocation: Int) -> [NSAttributedString.Key: Any] {
        MarkdownTypingAttributes.attributes(for: documentText, selectionLocation: selectionLocation)
    }
}

enum MarkdownLineRanges {
    static func visibleLineRange(from paragraphRange: NSRange, in text: NSString) -> NSRange {
        var length = paragraphRange.length
        while length > 0 {
            let lastLocation = paragraphRange.location + length - 1
            guard let scalar = UnicodeScalar(text.character(at: lastLocation)),
                  CharacterSet.newlines.contains(scalar) else {
                break
            }
            length -= 1
        }
        return NSRange(location: paragraphRange.location, length: length)
    }
}

// ╔══════════════════════════════════════════════════════════════╗
// ║  iOS — UITextView (TextKit 2 by default on iOS 16+)        ║
// ╚══════════════════════════════════════════════════════════════╝

#if os(iOS)

private final class EditorAccessoryView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 56)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        clearAccessoryChrome()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clearAccessoryChrome()
    }

    private func clearAccessoryChrome() {
        var view = superview
        while let currentView = view, currentView !== window {
            currentView.isOpaque = false
            currentView.backgroundColor = .clear
            view = currentView.superview
        }
    }
}

private final class PageMentionSheetViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    var onSelectDocument: ((PageMentionDocument) -> Void)?
    var onDismissWithoutSelection: (() -> Void)?

    private let documentProvider: (String) -> [PageMentionDocument]
    private let initialQuery: String
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var documents: [PageMentionDocument] = []
    private var didSelectDocument = false
    private var searchDebounceTimer: Timer?

    init(initialQuery: String, documentProvider: @escaping (String) -> [PageMentionDocument]) {
        self.initialQuery = initialQuery
        self.documentProvider = documentProvider
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        searchDebounceTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Mention Document"
        view.backgroundColor = AppTheme.uiBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )

        searchBar.placeholder = "Search documents"
        searchBar.text = initialQuery
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.autocorrectionType = .no
        searchBar.autocapitalizationType = .none
        searchBar.returnKeyType = .done
        searchBar.accessibilityIdentifier = "page_mention_search_field"
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = AppTheme.uiBackground
        tableView.separatorColor = AppTheme.uiSeparator
        tableView.sectionHeaderTopPadding = 0
        tableView.keyboardDismissMode = .interactive
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PageMentionDocumentCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchBar.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        preferredContentSize = CGSize(width: 420, height: 560)
        updateEmptyState(for: initialQuery)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        focusSearchField()
        updateContent(for: searchBar.text ?? "", debounce: false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        searchDebounceTimer?.invalidate()
        guard !didSelectDocument,
              isBeingDismissed || navigationController?.isBeingDismissed == true else {
            return
        }
        onDismissWithoutSelection?()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        updateContent(for: searchText, debounce: true)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func focusSearchField() {
        DispatchQueue.main.async { [weak self] in
            self?.searchBar.becomeFirstResponder()
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        documents.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PageMentionDocumentCell", for: indexPath)
        let document = documents[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = document.title
        content.secondaryText = document.relativePath
        content.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
        content.textProperties.color = AppTheme.uiPrimaryText
        content.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .caption1)
        content.secondaryTextProperties.color = AppTheme.uiMutedText
        content.textToSecondaryTextVerticalPadding = 4
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = .clear
        cell.accessibilityIdentifier = "page_mention_suggestion_\(indexPath.row)"
        cell.accessibilityLabel = "Mention \(document.title), \(document.relativePath)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < documents.count else { return }
        didSelectDocument = true
        onSelectDocument?(documents[indexPath.row])
        dismiss(animated: true)
    }

    private func updateContent(for query: String, debounce: Bool) {
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = nil

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            documents = []
            tableView.reloadData()
            updateEmptyState(for: query)
            return
        }

        guard debounce else {
            DispatchQueue.main.async { [weak self] in
                self?.reloadDocuments(for: query)
            }
            return
        }

        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { [weak self] _ in
            guard let self, self.searchBar.text == query else { return }
            self.reloadDocuments(for: query)
        }
    }

    private func reloadDocuments(for query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            documents = []
            tableView.reloadData()
            updateEmptyState(for: query)
            return
        }

        documents = documentProvider(query)
        tableView.reloadData()
        updateEmptyState(for: query)
    }

    private func updateEmptyState(for query: String) {
        guard documents.isEmpty else {
            tableView.backgroundView = nil
            return
        }

        let emptyView = makeEmptyStateView()
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyView.label.text = "Type to search for notes"
        } else {
            emptyView.label.text = "No matching notes"
        }
        emptyView.container.accessibilityIdentifier = "page_mention_empty_state"
        tableView.backgroundView = emptyView.container
    }

    private func makeEmptyStateView() -> (container: UIView, label: UILabel) {
        let container = UIView()
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .callout)
        label.textColor = AppTheme.uiMutedText
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -24),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 28),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -28),
        ])

        return (container, label)
    }

    @objc
    private func cancel() {
        dismiss(animated: true)
    }
}

struct TextKit2EditorView: UIViewControllerRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?
    var pageMentionProvider: ((String) -> [PageMentionDocument])?
    var onOpenDocumentLink: ((String) -> Void)?

    func makeCoordinator() -> TextKit2EditorCoordinator {
        TextKit2EditorCoordinator(text: $text, onTextChange: onTextChange, autoFocus: autoFocus)
    }

    func makeUIViewController(context: Context) -> TextKit2EditorViewController {
        let vc = TextKit2EditorViewController()
        vc.coordinator = context.coordinator
        vc.pageMentionProvider = pageMentionProvider
        vc.onOpenDocumentLink = onOpenDocumentLink
        vc.loadText(text)
        return vc
    }

    func updateUIViewController(_ vc: TextKit2EditorViewController, context: Context) {
        vc.pageMentionProvider = pageMentionProvider
        vc.onOpenDocumentLink = onOpenDocumentLink
        guard !context.coordinator.isUpdatingText else { return }
        guard !vc.textView.isFirstResponder else { return }
        let currentText = vc.textView.text ?? ""
        if currentText != text {
            vc.loadText(text)
        }
    }
}

final class TextKit2EditorViewController: UIViewController, UITextViewDelegate, UIGestureRecognizerDelegate {
    private static let parentBottomToolbarClearance: CGFloat = 72

    var coordinator: TextKit2EditorCoordinator?
    var pageMentionProvider: ((String) -> [PageMentionDocument])?
    var onOpenDocumentLink: ((String) -> Void)?
    private(set) var textView: UITextView!
    private let markdownDelegate = MarkdownTextDelegate()
    private var pendingText: String?
    private var xmlTagCollapseButtons: [UIButton] = []
    private var pageMentionSuggestionView: UIStackView?
    private var pageMentionSuggestionDocuments: [PageMentionDocument] = []
    private var selectedPageMentionSuggestionIndex = 0
    private var activePageMentionQuery: PageMentionQuery?
    private var pageMentionSheetViewController: PageMentionSheetViewController?
    private var pendingPageMentionTriggerLocation: Int?
    private var suppressedPageMentionLocation: Int?
    private var collapsedXMLTagOpeningLocations: Set<Int> = []
    private var revealedHyperlinkRanges: [NSRange] = []
    private var hyperlinkRangesAtTapStart: [NSRange] = []
    private weak var todoMarkerTapRecognizer: UITapGestureRecognizer?
    private weak var hyperlinkTapRecognizer: UITapGestureRecognizer?
    private var isRestylingText = false
    private var isOverlayRefreshScheduled = false
    private var lastOverlayLayoutSize: CGSize = .zero
    private var keyboardObserverTokens: [NSObjectProtocol] = []
    private var keyboardFrameInScreen: CGRect?
    private var loadingImageURLs: Set<URL> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppTheme.uiBackground

        // UITextView uses TextKit 2 by default on iOS 16+.
        // We hook into its existing stack via delegates.
        textView = UITextView()

        if let layoutManager = textView.textLayoutManager,
           let contentStorage = layoutManager.textContentManager as? NSTextContentStorage {
            contentStorage.delegate = markdownDelegate
            layoutManager.delegate = markdownDelegate
            markdownDelegate.requestImageLoad = { [weak self] url in
                self?.requestImageLoad(for: url)
            }
        } else {
            logger.warning("TextKit 2 not available — falling back to unstyled editing")
        }

        textView.font = MarkdownTheme.bodyFont
        textView.textColor = MarkdownTheme.bodyColor
        textView.backgroundColor = AppTheme.uiBackground
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.inputAccessoryView = makeInputAccessoryView()
        textView.accessibilityIdentifier = "note_editor"
        textView.delegate = self
        textView.linkTextAttributes = [
            .foregroundColor: MarkdownTheme.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.translatesAutoresizingMaskIntoConstraints = false
        installTodoMarkerTapRecognizer()
        installHyperlinkTapRecognizer()
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        if let pendingText {
            applyText(pendingText)
            self.pendingText = nil
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startKeyboardObservation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopKeyboardObservation()
    }

    deinit {
        stopKeyboardObservation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateKeyboardAvoidanceInsets()
        refreshEditorOverlaysAfterLayoutChangeIfNeeded()
        positionPageMentionSuggestions()
    }

    override var keyCommands: [UIKeyCommand]? {
        var commands = [
            UIKeyCommand(
                input: "\t",
                modifierFlags: [],
                action: #selector(indentSelectedLines),
                discoverabilityTitle: "Indent"
            ),
            UIKeyCommand(
                input: "\t",
                modifierFlags: [.shift],
                action: #selector(outdentSelectedLines),
                discoverabilityTitle: "Outdent"
            ),
            UIKeyCommand(
                input: "b",
                modifierFlags: [.command],
                action: #selector(toggleSelectedBold),
                discoverabilityTitle: "Bold"
            ),
            UIKeyCommand(
                input: "i",
                modifierFlags: [.command],
                action: #selector(toggleSelectedItalic),
                discoverabilityTitle: "Italic"
            ),
            UIKeyCommand(
                input: "k",
                modifierFlags: [.command],
                action: #selector(toggleSelectedHyperlink),
                discoverabilityTitle: "Link"
            ),
        ]

        if isPageMentionPopoverVisible {
            commands.append(contentsOf: [
                UIKeyCommand(
                    input: UIKeyCommand.inputUpArrow,
                    modifierFlags: [],
                    action: #selector(selectPreviousPageMentionSuggestion),
                    discoverabilityTitle: "Previous Mention"
                ),
                UIKeyCommand(
                    input: UIKeyCommand.inputDownArrow,
                    modifierFlags: [],
                    action: #selector(selectNextPageMentionSuggestion),
                    discoverabilityTitle: "Next Mention"
                ),
                UIKeyCommand(
                    input: UIKeyCommand.inputEscape,
                    modifierFlags: [],
                    action: #selector(dismissPageMentionSuggestions),
                    discoverabilityTitle: "Dismiss Mention"
                ),
            ])
        }

        return commands
    }

    func loadText(_ markdown: String) {
        guard isViewLoaded, textView != nil else {
            pendingText = markdown
            return
        }
        applyText(markdown)
    }

    private func applyText(_ markdown: String) {
        coordinator?.beginApplyingEditorText(markdown)
        textView.text = markdown
        coordinator?.finishApplyingEditorText()
        updateTypingAttributes()
        if coordinator?.autoFocus == true {
            DispatchQueue.main.async { [weak self] in
                guard let tv = self?.textView else { return }
                tv.becomeFirstResponder()
                let end = tv.endOfDocument
                tv.selectedTextRange = tv.textRange(from: end, to: end)
                self?.scheduleEditorOverlayRefresh()
            }
        }
        scheduleEditorOverlayRefresh()
        updatePageMentionSuggestions()
    }

    private func makeInputAccessoryView() -> UIView {
        let toolbar = EditorAccessoryView(frame: CGRect(x: 0, y: 0, width: 0, height: 56))
        toolbar.backgroundColor = .clear
        toolbar.accessibilityIdentifier = "note_editor_toolbar"

        let glassEffect = UIGlassEffect()
        glassEffect.isInteractive = true
        let pill = UIVisualEffectView(effect: glassEffect)
        pill.backgroundColor = .clear
        pill.layer.cornerRadius = 22
        pill.layer.cornerCurve = .continuous
        pill.clipsToBounds = true
        pill.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView(arrangedSubviews: [
            makeToolbarButton(
                systemName: "checklist",
                accessibilityIdentifier: "toggle_todo_button",
                accessibilityLabel: "Toggle Todo",
                action: #selector(toggleTodoForSelectedLines)
            ),
            makeToolbarButton(
                systemName: "increase.indent",
                accessibilityIdentifier: "indent_button",
                accessibilityLabel: "Indent",
                action: #selector(indentSelectedLines)
            ),
            makeToolbarButton(
                systemName: "decrease.indent",
                accessibilityIdentifier: "outdent_button",
                accessibilityLabel: "Outdent",
                action: #selector(outdentSelectedLines)
            ),
            makeToolbarButton(
                systemName: "strikethrough",
                accessibilityIdentifier: "toggle_strikethrough_button",
                accessibilityLabel: "Strikethrough",
                action: #selector(toggleSelectedStrikethrough)
            ),
            makeToolbarButton(
                systemName: "link",
                accessibilityIdentifier: "toggle_hyperlink_button",
                accessibilityLabel: "Link",
                action: #selector(toggleSelectedHyperlink)
            ),
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 16

        toolbar.addSubview(pill)
        pill.contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            pill.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            pill.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 4),
            pill.heightAnchor.constraint(equalToConstant: 44),

            stackView.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor, constant: 14),
            stackView.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor, constant: -14),
            stackView.centerYAnchor.constraint(equalTo: pill.contentView.centerYAnchor),
        ])

        return toolbar
    }

    private func makeToolbarButton(
        systemName: String,
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = AppTheme.uiPrimaryText
        button.accessibilityIdentifier = accessibilityIdentifier
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])
        return button
    }

    @objc
    private func toggleTodoForSelectedLines() {
        guard let transform = BlockEditingCommands.toggledTodoLines(
            in: textView.text ?? "",
            selection: textView.selectedRange
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    @objc
    private func indentSelectedLines() {
        guard let transform = BlockEditingCommands.indentedLines(
            in: textView.text ?? "",
            selection: textView.selectedRange
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    @objc
    private func outdentSelectedLines() {
        guard let transform = BlockEditingCommands.outdentedLines(
            in: textView.text ?? "",
            selection: textView.selectedRange
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    @objc
    private func toggleSelectedStrikethrough() {
        guard let transform = BlockEditingCommands.toggledStrikethrough(
            in: textView.text ?? "",
            selection: textView.selectedRange
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    @objc
    private func toggleSelectedBold() {
        guard let transform = BlockEditingCommands.toggledBold(
            in: textView.text ?? "",
            selection: textView.selectedRange
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    @objc
    private func toggleSelectedItalic() {
        guard let transform = BlockEditingCommands.toggledItalic(
            in: textView.text ?? "",
            selection: textView.selectedRange
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    @objc
    private func toggleSelectedHyperlink() {
        guard let transform = BlockEditingCommands.toggledHyperlink(
            in: textView.text ?? "",
            selection: textView.selectedRange
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    private func applySelectionTransform(_ transform: TextSelectionTransform) {
        let currentText = textView.text ?? ""
        guard let replacement = TextEditDiff.singleReplacement(from: currentText, to: transform.text) else {
            textView.selectedRange = transform.selection
            return
        }

        coordinator?.beginApplyingEditorText(transform.text)
        if let start = textView.position(from: textView.beginningOfDocument, offset: replacement.range.location),
           let end = textView.position(from: start, offset: replacement.range.length),
           let textRange = textView.textRange(from: start, to: end) {
            textView.replace(textRange, withText: replacement.replacement)
        } else {
            textView.text = transform.text
        }
        textView.selectedRange = transform.selection
        updateTypingAttributes()
        coordinator?.commitAppliedEditorText(transform.text)
        scheduleEditorOverlayRefresh()
    }

    private func updatePageMentionSuggestions() {
        guard let pageMentionProvider,
              textView.isFirstResponder,
              let query = PageMentionMarkdown.activeQuery(
                  in: textView.text ?? "",
                  selection: textView.selectedRange
              ) else {
            pendingPageMentionTriggerLocation = nil
            clearSuppressedPageMentionIfNeeded(activeQuery: nil)
            return
        }

        clearSuppressedPageMentionIfNeeded(activeQuery: query)
        guard pendingPageMentionTriggerLocation == query.range.location else {
            pendingPageMentionTriggerLocation = nil
            return
        }

        guard suppressedPageMentionLocation != query.range.location,
              pageMentionSheetViewController == nil,
              presentedViewController == nil else {
            return
        }

        pendingPageMentionTriggerLocation = nil
        presentPageMentionSheet(for: query, documentProvider: pageMentionProvider)
    }

    private func presentPageMentionSheet(
        for query: PageMentionQuery,
        documentProvider: @escaping (String) -> [PageMentionDocument]
    ) {
        activePageMentionQuery = query

        let sheetViewController = PageMentionSheetViewController(
            initialQuery: query.query,
            documentProvider: documentProvider
        )
        pageMentionSheetViewController = sheetViewController
        sheetViewController.onSelectDocument = { [weak self, query] document in
            self?.pageMentionSheetViewController = nil
            self?.suppressedPageMentionLocation = nil
            self?.selectPageMentionDocument(document, replacing: query)
        }
        sheetViewController.onDismissWithoutSelection = { [weak self, location = query.range.location] in
            guard let self else { return }
            self.pageMentionSheetViewController = nil
            self.activePageMentionQuery = nil
            self.suppressedPageMentionLocation = location
            DispatchQueue.main.async { [weak self] in
                self?.textView.becomeFirstResponder()
            }
        }

        let navigationController = UINavigationController(rootViewController: sheetViewController)
        navigationController.modalPresentationStyle = .pageSheet
        if let sheetPresentationController = navigationController.sheetPresentationController {
            sheetPresentationController.detents = [.medium(), .large()]
            sheetPresentationController.prefersGrabberVisible = true
            sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = true
        }

        textView.resignFirstResponder()
        present(navigationController, animated: true) {
            sheetViewController.focusSearchField()
        }
    }

    private func selectPageMentionDocument(_ document: PageMentionDocument, replacing query: PageMentionQuery) {
        let currentText = textView.text ?? ""
        let nsText = currentText as NSString
        guard NSMaxRange(query.range) <= nsText.length else {
            return
        }

        let markdownLink = PageMentionMarkdown.markdownLink(for: document)
        let updatedText = nsText.replacingCharacters(in: query.range, with: markdownLink)
        let selection = NSRange(location: query.range.location + markdownLink.utf16.count, length: 0)
        activePageMentionQuery = nil
        applySelectionTransform(TextSelectionTransform(text: updatedText, selection: selection))
        textView.becomeFirstResponder()
    }

    private func clearSuppressedPageMentionIfNeeded(activeQuery: PageMentionQuery?) {
        guard let suppressedPageMentionLocation else { return }
        guard let activeQuery,
              activeQuery.range.location == suppressedPageMentionLocation else {
            self.suppressedPageMentionLocation = nil
            return
        }

        let nsText = (textView.text ?? "") as NSString
        guard suppressedPageMentionLocation < nsText.length,
              nsText.substring(with: NSRange(location: suppressedPageMentionLocation, length: 1)) == "@" else {
            self.suppressedPageMentionLocation = nil
            return
        }
    }

    private func showPageMentionSuggestions(_ documents: [PageMentionDocument], emptyStateText: String?) {
        let stackView = pageMentionSuggestionView ?? makePageMentionSuggestionView()
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if let emptyStateText {
            let label = UILabel()
            label.numberOfLines = 2
            label.attributedText = pageMentionEmptyStateTitle(emptyStateText)
            label.accessibilityIdentifier = "page_mention_empty_state"
            label.accessibilityLabel = emptyStateText
            stackView.addArrangedSubview(label)
        }

        for (index, document) in documents.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.contentHorizontalAlignment = .left
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.titleLabel?.numberOfLines = 2
            button.layer.cornerRadius = 6
            button.layer.cornerCurve = .continuous
            button.setAttributedTitle(pageMentionButtonTitle(for: document), for: .normal)
            button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
            button.accessibilityIdentifier = "page_mention_suggestion_\(index)"
            button.accessibilityLabel = "Mention \(document.title), \(document.relativePath)"
            button.addTarget(self, action: #selector(pageMentionSuggestionTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }

        if stackView.superview == nil {
            view.addSubview(stackView)
        }
        refreshPageMentionSelection()
        positionPageMentionSuggestions()
    }

    private func makePageMentionSuggestionView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 2
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stackView.backgroundColor = AppTheme.uiBackground
        stackView.layer.cornerRadius = 10
        stackView.layer.cornerCurve = .continuous
        stackView.layer.borderColor = AppTheme.uiSeparator.cgColor
        stackView.layer.borderWidth = 1
        stackView.clipsToBounds = true
        pageMentionSuggestionView = stackView
        return stackView
    }

    private func pageMentionEmptyStateTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: AppTheme.uiMutedText,
            ]
        )
    }

    private func pageMentionButtonTitle(for document: PageMentionDocument) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: document.title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: AppTheme.uiPrimaryText,
            ]
        )
        result.append(NSAttributedString(
            string: "\n\(document.relativePath)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: AppTheme.uiMutedText,
            ]
        ))
        return result
    }

    private func positionPageMentionSuggestions() {
        guard let stackView = pageMentionSuggestionView,
              stackView.superview != nil,
              let query = activePageMentionQuery,
              let position = textView.position(
                  from: textView.beginningOfDocument,
                  offset: NSMaxRange(query.range)
              ) else {
            return
        }

        let caretRect = textView.caretRect(for: position)
        let horizontalMargin: CGFloat = 12
        let rowCount = max(1, min(pageMentionSuggestionDocuments.count, 5))
        let width = min(max(320, view.bounds.width * 0.72), view.bounds.width - horizontalMargin * 2)
        let height = CGFloat(rowCount) * 52 + 16
        let x = min(max(horizontalMargin, textView.frame.minX + caretRect.minX), max(horizontalMargin, view.bounds.width - width - horizontalMargin))
        let keyboardInset = textView.contentInset.bottom
        var y = textView.frame.minY + caretRect.maxY + 6
        if y + height > view.bounds.height - keyboardInset - 8 {
            y = textView.frame.minY + caretRect.minY - height - 6
        }
        stackView.frame = CGRect(x: x, y: max(8, y), width: width, height: height)
    }

    private func hidePageMentionSuggestions() {
        activePageMentionQuery = nil
        pageMentionSuggestionDocuments = []
        selectedPageMentionSuggestionIndex = 0
        pageMentionSuggestionView?.removeFromSuperview()
    }

    @objc
    private func pageMentionSuggestionTapped(_ sender: UIButton) {
        selectPageMentionSuggestion(at: sender.tag)
    }

    private var isPageMentionPopoverVisible: Bool {
        pageMentionSuggestionView?.superview != nil
    }

    private var hasSelectablePageMentionSuggestion: Bool {
        isPageMentionPopoverVisible && !pageMentionSuggestionDocuments.isEmpty
    }

    @objc
    private func selectPreviousPageMentionSuggestion() {
        movePageMentionSelection(by: -1)
    }

    @objc
    private func selectNextPageMentionSuggestion() {
        movePageMentionSelection(by: 1)
    }

    @objc
    private func dismissPageMentionSuggestions() {
        hidePageMentionSuggestions()
    }

    private func movePageMentionSelection(by delta: Int) {
        guard hasSelectablePageMentionSuggestion else { return }
        let maxIndex = pageMentionSuggestionDocuments.count - 1
        selectedPageMentionSuggestionIndex = min(max(selectedPageMentionSuggestionIndex + delta, 0), maxIndex)
        refreshPageMentionSelection()
    }

    private func refreshPageMentionSelection() {
        guard let stackView = pageMentionSuggestionView else { return }
        for case let button as UIButton in stackView.arrangedSubviews {
            button.backgroundColor = button.tag == selectedPageMentionSuggestionIndex
                ? AppTheme.uiSeparator.withAlphaComponent(0.75)
                : .clear
        }
    }

    private func selectCurrentPageMentionSuggestion() {
        guard hasSelectablePageMentionSuggestion else { return }
        selectPageMentionSuggestion(at: selectedPageMentionSuggestionIndex)
    }

    private func selectPageMentionSuggestion(at index: Int) {
        guard index >= 0,
              index < pageMentionSuggestionDocuments.count,
              let activePageMentionQuery else { return }

        let document = pageMentionSuggestionDocuments[index]
        let currentText = textView.text ?? ""
        let nsText = currentText as NSString
        guard NSMaxRange(activePageMentionQuery.range) <= nsText.length else { return }

        let markdownLink = PageMentionMarkdown.markdownLink(for: document)
        let updatedText = nsText.replacingCharacters(in: activePageMentionQuery.range, with: markdownLink)
        let selection = NSRange(location: activePageMentionQuery.range.location + markdownLink.utf16.count, length: 0)
        hidePageMentionSuggestions()
        applySelectionTransform(TextSelectionTransform(text: updatedText, selection: selection))
        textView.becomeFirstResponder()
    }

    // MARK: UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text.isEmpty, revealHyperlinkMarkdownForDeletionIfNeeded(changeRange: range) {
            return false
        }

        if text == "@", range.length == 0 {
            pendingPageMentionTriggerLocation = range.location
            suppressedPageMentionLocation = nil
        } else if !text.isEmpty {
            pendingPageMentionTriggerLocation = nil
        }

        if text == "\n", hasSelectablePageMentionSuggestion {
            selectCurrentPageMentionSuggestion()
            return false
        }

        guard text == "\n",
              let transform = BlockEditingCommands.continuedListLineBreak(
                in: textView.text ?? "",
                selection: range
              ) else {
            return true
        }

        applySelectionTransform(transform)
        return false
    }

    func textViewDidChange(_ textView: UITextView) {
        if !isRestylingText {
            updateRevealedHyperlinkRangesForSelection(restyle: false)
        }
        coordinator?.publishEditorText(textView.text ?? "")
        updateTypingAttributes()
        scrollSelectionAboveKeyboard()
        scheduleEditorOverlayRefresh()
        updatePageMentionSuggestions()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if !isRestylingText {
            updateRevealedHyperlinkRangesForSelection(restyle: true)
        }
        updateTypingAttributes()
        updatePageMentionSuggestions()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        coordinator?.publishEditorText(textView.text ?? "")
    }

    private func revealHyperlinkMarkdownForDeletionIfNeeded(changeRange: NSRange) -> Bool {
        let currentText = textView.text ?? ""
        guard let match = hyperlinkMatch(intersecting: changeRange, in: currentText) else { return false }
        if revealedHyperlinkRanges.contains(where: { NSEqualRanges($0, match.fullRange) }) {
            return false
        }

        setRevealedHyperlinkRanges([match.fullRange])
        restyleTextPreservingSelection()
        return true
    }

    private func hyperlinkMatch(intersecting range: NSRange, in text: String) -> HyperlinkMarkdown.Match? {
        HyperlinkMarkdown.matches(in: text).first { match in
            if range.length == 0 {
                return NSLocationInRange(range.location, match.fullRange)
            }
            return NSIntersectionRange(range, match.fullRange).length > 0
        }
    }

    private func setRevealedHyperlinkRanges(_ ranges: [NSRange]) {
        revealedHyperlinkRanges = ranges
        markdownDelegate.revealedHyperlinkRanges = ranges
    }

    private func updateRevealedHyperlinkRangesForSelection(restyle: Bool) {
        let ranges = hyperlinkRangesOnSelectedLines(in: textView.text ?? "", selection: textView.selectedRange)
        guard !nsRangesEqual(ranges, revealedHyperlinkRanges) else { return }
        setRevealedHyperlinkRanges(ranges)
        if restyle {
            restyleTextPreservingSelection()
        }
    }

    private func hyperlinkRangesOnSelectedLines(in text: String, selection: NSRange) -> [NSRange] {
        let nsText = text as NSString
        guard nsText.length > 0, selection.location != NSNotFound else { return [] }

        let safeLocation = max(0, min(selection.location, nsText.length))
        let safeLength = max(0, min(selection.length, nsText.length - safeLocation))
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: safeLength))

        return HyperlinkMarkdown.matches(in: text)
            .map(\.fullRange)
            .filter { NSIntersectionRange($0, lineRange).length > 0 }
    }

    private func nsRangesEqual(_ lhs: [NSRange], _ rhs: [NSRange]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            guard NSEqualRanges(left, right) else { return false }
        }
        return true
    }

    private func restyleTextPreservingSelection() {
        applyHyperlinkRenderAttributesToTextStorage()
        updateTypingAttributes()
        scheduleEditorOverlayRefresh()
    }

    private func applyHyperlinkRenderAttributesToTextStorage() {
        let textStorage = textView.textStorage
        let matches = HyperlinkMarkdown.matches(in: textView.text ?? "")

        for match in matches {
            guard let url = match.url else { continue }
            let isRevealed = revealedHyperlinkRanges.contains { NSEqualRanges($0, match.fullRange) }
            textStorage.removeAttribute(.link, range: match.fullRange)
            textStorage.addAttributes([
                .font: MarkdownTheme.bodyFont,
                .foregroundColor: MarkdownTheme.bodyColor,
                .underlineStyle: 0,
            ], range: match.fullRange)

            if !isRevealed {
                textStorage.addAttributes([
                    .link: url,
                    .foregroundColor: MarkdownTheme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: match.titleRange)
            }

            for syntaxRange in hyperlinkSyntaxRanges(for: match) {
                if isRevealed {
                    textStorage.addAttributes([
                        .font: MarkdownTheme.bodyFont,
                        .foregroundColor: MarkdownTheme.prefixColor,
                        .underlineStyle: 0,
                    ], range: syntaxRange)
                } else {
                    textStorage.addAttributes([
                        .font: PlatformFont.systemFont(ofSize: MarkdownVisualSpec.hyperlinkSyntaxVisualWidth, weight: .regular),
                        .foregroundColor: PlatformColor.clear,
                        .underlineStyle: 0,
                    ], range: syntaxRange)
                }
            }
        }
    }

    private func hyperlinkSyntaxRanges(for match: HyperlinkMarkdown.Match) -> [NSRange] {
        [
            NSRange(location: match.fullRange.location, length: 1),
            NSRange(location: NSMaxRange(match.titleRange), length: 2),
            match.urlRange,
            NSRange(location: NSMaxRange(match.urlRange), length: 1),
        ]
    }

    private func installHyperlinkTapRecognizer() {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleHyperlinkTap(_:)))
        recognizer.numberOfTapsRequired = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        textView.addGestureRecognizer(recognizer)
        hyperlinkTapRecognizer = recognizer
    }

    private func installTodoMarkerTapRecognizer() {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTodoMarkerTap(_:)))
        recognizer.numberOfTapsRequired = 1
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        textView.addGestureRecognizer(recognizer)
        todoMarkerTapRecognizer = recognizer
    }

    @objc
    private func handleTodoMarkerTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let textView = recognizer.view as? UITextView else {
            return
        }

        toggleTodoMarker(atTextViewPoint: recognizer.location(in: textView))
    }

    @objc
    private func handleHyperlinkTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let textView = recognizer.view as? UITextView else {
            return
        }

        let location = recognizer.location(in: textView)
        guard let position = textView.closestPosition(to: location) else { return }

        let characterIndex = textView.offset(from: textView.beginningOfDocument, to: position)
        guard let match = HyperlinkMarkdown.match(at: characterIndex, in: textView.text ?? ""),
              let target = match.target,
              !hyperlinkRangesAtTapStart.contains(where: { NSEqualRanges($0, match.fullRange) }) else {
            return
        }

        switch target {
        case .external(let url):
            UIApplication.shared.open(url)
        case .vaultDocument(let relativePath):
            onOpenDocumentLink?(relativePath)
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === todoMarkerTapRecognizer {
            return todoBlock(containingMarkerPoint: touch.location(in: textView)) != nil
        }
        if gestureRecognizer === hyperlinkTapRecognizer {
            hyperlinkRangesAtTapStart = revealedHyperlinkRanges
        }
        return true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        coordinator?.publishEditorText(textView.text ?? "")
    }

    private func startKeyboardObservation() {
        guard keyboardObserverTokens.isEmpty else { return }

        let center = NotificationCenter.default
        keyboardObserverTokens.append(center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleKeyboardFrameChange(notification)
        })
        keyboardObserverTokens.append(center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleKeyboardHide(notification)
        })
    }

    private func stopKeyboardObservation() {
        let center = NotificationCenter.default
        keyboardObserverTokens.forEach { center.removeObserver($0) }
        keyboardObserverTokens.removeAll()
        keyboardFrameInScreen = nil
    }

    private func handleKeyboardFrameChange(_ notification: Notification) {
        keyboardFrameInScreen = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        animateKeyboardAvoidance(using: notification)
    }

    private func handleKeyboardHide(_ notification: Notification) {
        keyboardFrameInScreen = nil
        animateKeyboardAvoidance(using: notification)
    }

    private func animateKeyboardAvoidance(using notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveRawValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int
            ?? UIView.AnimationCurve.easeInOut.rawValue
        let options = UIView.AnimationOptions(rawValue: UInt(curveRawValue << 16))

        UIView.animate(withDuration: duration, delay: 0, options: options) { [weak self] in
            self?.updateKeyboardAvoidanceInsets()
            self?.view.layoutIfNeeded()
        } completion: { [weak self] _ in
            self?.scrollSelectionAboveKeyboard()
        }
    }

    private func updateKeyboardAvoidanceInsets() {
        guard isViewLoaded, textView != nil else { return }

        let overlap = keyboardFrameInScreen.map { keyboardFrame -> CGFloat in
            let keyboardFrameInView = view.convert(keyboardFrame, from: nil)
            guard keyboardFrameInView.intersects(view.bounds) else { return 0 }
            return max(0, view.bounds.maxY - keyboardFrameInView.minY)
        } ?? 0
        let accessoryHeight = overlap > 0 ? (textView.inputAccessoryView?.bounds.height ?? 0) : 0
        let bottomInset = max(Self.parentBottomToolbarClearance, overlap + accessoryHeight)

        textView.contentInset.bottom = bottomInset
        textView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    private func scrollSelectionAboveKeyboard() {
        guard textView.isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.textView != nil else { return }
            self.textView.scrollRangeToVisible(self.textView.selectedRange)
        }
    }

    /// Sets typing attributes to match the current paragraph's block kind,
    /// so newly typed characters inherit the correct font immediately
    /// (before the content-storage delegate re-styles the paragraph).
    private func updateTypingAttributes() {
        textView.typingAttributes = coordinator?.typingAttributes(
            for: textView.text ?? "",
            selectionLocation: textView.selectedRange.location
        ) ?? MarkdownTypingAttributes.attributes(
            for: textView.text ?? "",
            selectionLocation: textView.selectedRange.location
        )
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Rebuilding XML collapse controls during an active pan can cancel
        // scrolling gestures, so the scroll callback stays passive.
    }

    private func scheduleEditorOverlayRefresh() {
        guard !isOverlayRefreshScheduled else { return }
        isOverlayRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isOverlayRefreshScheduled = false
            self.refreshEditorOverlays()
        }
    }

    private func refreshEditorOverlaysAfterLayoutChangeIfNeeded() {
        let size = textView.bounds.size
        guard size != lastOverlayLayoutSize else { return }
        lastOverlayLayoutSize = size
        refreshEditorOverlays()
    }

    private func refreshEditorOverlays() {
        syncCollapsedXMLTagState()
        refreshXMLTagCollapseButtons()
    }

    private func refreshXMLTagCollapseButtons() {
        guard isViewLoaded, textView != nil else { return }

        xmlTagCollapseButtons.forEach { $0.removeFromSuperview() }
        xmlTagCollapseButtons.removeAll()

        let text = textView.text ?? ""
        let blocks = XMLLikeTagParser.blocks(in: text)
        guard !blocks.isEmpty else { return }

        textView.layoutIfNeeded()

        for block in blocks {
            addXMLTagCollapseButton(for: block)
        }
    }

    private func addXMLTagCollapseButton(for block: XMLLikeTagBlock) {
        guard let startPosition = textView.position(
            from: textView.beginningOfDocument,
            offset: block.openingLineRange.location
        ) else {
            return
        }

        let caretRect = textView.caretRect(for: startPosition)
        guard !caretRect.isNull,
              caretRect.origin.x.isFinite,
              caretRect.origin.y.isFinite,
              caretRect.size.width.isFinite,
              caretRect.size.height.isFinite else {
            return
        }

        let buttonSize = MarkdownVisualSpec.xmlTagCollapseControlSize
        let hitTargetWidth = max(CGFloat(44), caretRect.minX + 6)
        let hitTargetHeight = max(CGFloat(32), buttonSize)
        let isCollapsed = collapsedXMLTagOpeningLocations.contains(block.openingLineRange.location)
        let button = UIButton(type: .system)
        let imageName = isCollapsed ? "chevron.right" : "chevron.down"
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
        button.tintColor = AppTheme.uiMutedText
        button.backgroundColor = textView.backgroundColor ?? AppTheme.uiBackground
        button.tag = block.openingLineRange.location
        button.accessibilityIdentifier = "xml_tag_collapse_\(block.openingLineRange.location)"
        button.accessibilityLabel = isCollapsed ? "Expand \(block.tagName)" : "Collapse \(block.tagName)"
        button.frame = CGRect(
            x: 0,
            y: caretRect.midY - hitTargetHeight / 2,
            width: hitTargetWidth,
            height: hitTargetHeight
        )
        button.addTarget(self, action: #selector(xmlTagCollapseButtonTapped(_:)), for: .touchUpInside)

        textView.addSubview(button)
        xmlTagCollapseButtons.append(button)
    }

    @objc
    private func xmlTagCollapseButtonTapped(_ sender: UIButton) {
        let openingLocation = sender.tag
        let visibleOffset = textView.contentOffset
        if collapsedXMLTagOpeningLocations.contains(openingLocation) {
            collapsedXMLTagOpeningLocations.remove(openingLocation)
        } else {
            collapsedXMLTagOpeningLocations.insert(openingLocation)
        }
        syncCollapsedXMLTagState()
        rebuildTextLayoutPreservingSelection()
        refreshEditorOverlays()
        restoreVisibleOffset(visibleOffset)
        refreshEditorOverlaysAfterTextLayoutSettles(restoring: visibleOffset)
    }

    private func syncCollapsedXMLTagState() {
        let blocks = XMLLikeTagParser.blocks(in: textView.text ?? "")
        let validOpeningLocations = Set(blocks.map(\.openingLineRange.location))
        collapsedXMLTagOpeningLocations = collapsedXMLTagOpeningLocations.intersection(validOpeningLocations)
        markdownDelegate.collapsedXMLTagRanges = blocks
            .filter { collapsedXMLTagOpeningLocations.contains($0.openingLineRange.location) }
            .map(\.collapsedContentRange)
    }

    private func rebuildTextLayoutPreservingSelection() {
        let currentText = textView.text ?? ""
        let selectedRange = textView.selectedRange
        isRestylingText = true
        textView.text = currentText
        isRestylingText = false
        textView.selectedRange = NSRange(
            location: min(selectedRange.location, (currentText as NSString).length),
            length: min(selectedRange.length, max(0, (currentText as NSString).length - selectedRange.location))
        )
        updateTypingAttributes()
    }

    private func refreshEditorOverlaysAfterTextLayoutSettles(restoring offset: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.restoreVisibleOffset(offset)
            self.forceEditorLayout()
            self.refreshEditorOverlays()
            self.restoreVisibleOffset(offset)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.restoreVisibleOffset(offset)
                self.forceEditorLayout()
                self.refreshEditorOverlays()
                self.restoreVisibleOffset(offset)
            }
        }
    }

    private func forceEditorLayout() {
        view.setNeedsLayout()
        textView.setNeedsLayout()
        view.layoutIfNeeded()
        textView.layoutIfNeeded()
    }

    private func restoreVisibleOffset(_ offset: CGPoint) {
        textView.layoutIfNeeded()
        let maxX = max(0, textView.contentSize.width - textView.bounds.width)
        let maxY = max(0, textView.contentSize.height - textView.bounds.height)
        textView.setContentOffset(CGPoint(
            x: min(max(offset.x, 0), maxX),
            y: min(max(offset.y, 0), maxY)
        ), animated: false)
    }

    private func requestImageLoad(for url: URL) {
        guard loadingImageURLs.insert(url).inserted else { return }

        MarkdownImageLoader.load(url: url) { [weak self] _ in
            guard let self else { return }
            self.loadingImageURLs.remove(url)
            self.invalidateImageFragments()
        }
    }

    private func invalidateImageFragments() {
        guard isViewLoaded, textView != nil else { return }
        guard let layoutManager = textView.textLayoutManager,
              let documentRange = layoutManager.textContentManager?.documentRange else {
            textView.setNeedsDisplay()
            return
        }

        layoutManager.invalidateLayout(for: documentRange)
        layoutManager.ensureLayout(for: documentRange)
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        textView.setNeedsDisplay()
    }

    @discardableResult
    func toggleTodoMarker(atTextViewPoint point: CGPoint) -> Bool {
        syncCollapsedXMLTagState()
        guard let block = todoBlock(containingMarkerPoint: point) else { return false }
        toggleTodoCheckbox(atParagraphLocation: block.paragraphRange.location)
        return true
    }

    func todoMarkerHitRect(forParagraphLocation paragraphLocation: Int) -> CGRect? {
        syncCollapsedXMLTagState()
        guard let block = MarkdownSemanticAnalyzer.renderableBlocks(
            in: textView.text ?? "",
            collapsedXMLTagRanges: markdownDelegate.collapsedXMLTagRanges
        ).first(where: { $0.paragraphRange.location == paragraphLocation }),
              !block.isCollapsedXMLTagContent,
              case .todo = block.kind else {
            return nil
        }

        let prefixLength = block.kind.prefixLength(in: block.lineText)
        let contentLocation = paragraphLocation + prefixLength
        guard let contentPosition = textView.position(from: textView.beginningOfDocument, offset: contentLocation) else {
            return nil
        }

        let caretRect = textView.caretRect(for: contentPosition)
        guard isFiniteRect(caretRect) else { return nil }

        let markerRect = TodoMarkerGeometry.markerRect(
            contentLeadingX: caretRect.minX,
            lineMidY: caretRect.midY
        )
        let hitLeading = max(0, markerRect.minX - 8)
        let hitTrailing = max(markerRect.maxX, caretRect.minX + 8)
        return CGRect(
            x: hitLeading,
            y: markerRect.minY,
            width: hitTrailing - hitLeading,
            height: markerRect.height
        )
    }

    private func todoBlock(containingMarkerPoint point: CGPoint) -> MarkdownRenderableBlock? {
        let blocks = MarkdownSemanticAnalyzer.renderableBlocks(
            in: textView.text ?? "",
            collapsedXMLTagRanges: markdownDelegate.collapsedXMLTagRanges
        )

        for block in blocks where !block.isCollapsedXMLTagContent {
            guard case .todo = block.kind,
                  let rect = todoMarkerHitRect(forParagraphLocation: block.paragraphRange.location),
                  rect.insetBy(dx: -4, dy: -4).contains(point) else {
                continue
            }
            return block
        }

        return nil
    }

    private func isFiniteRect(_ rect: CGRect) -> Bool {
        !rect.isNull &&
        rect.origin.x.isFinite &&
        rect.origin.y.isFinite &&
        rect.size.width.isFinite &&
        rect.size.height.isFinite
    }

    private func toggleTodoCheckbox(atParagraphLocation paragraphLocation: Int) {
        let nsText = (textView.text ?? "") as NSString
        guard paragraphLocation >= 0, paragraphLocation < nsText.length else { return }

        let paragraphRange = nsText.paragraphRange(for: NSRange(location: paragraphLocation, length: 0))
        let lineRange = MarkdownLineRanges.visibleLineRange(from: paragraphRange, in: nsText)
        let lineText = nsText.substring(with: lineRange)
        let toggledLine = TodoMarkdown.checkboxToggledLine(lineText)
        guard toggledLine != lineText else { return }

        let updatedText = nsText.replacingCharacters(in: lineRange, with: toggledLine)
        let selectedRange = textView.selectedRange
        applySelectionTransform(TextSelectionTransform(text: updatedText, selection: selectedRange))
        textView.becomeFirstResponder()
    }

}

#endif

// ╔══════════════════════════════════════════════════════════════╗
// ║  macOS — NSTextView with manually-built TextKit 2 stack    ║
// ╚══════════════════════════════════════════════════════════════╝

#if os(macOS)

private final class HyperlinkOpeningTextView: NSTextView {
    var openHyperlinkTarget: ((HyperlinkMarkdown.Target) -> Void)?
    var shouldOpenHyperlinkAtIndex: ((Int) -> Bool)?
    var toggleTodoMarkerAtPoint: ((NSPoint) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if toggleTodoMarkerAtPoint?(point) == true {
            return
        }

        let characterIndex = characterIndexForInsertion(at: point)

        if shouldOpenHyperlinkAtIndex?(characterIndex) != false,
           let target = HyperlinkMarkdown.target(at: characterIndex, in: string) {
            openHyperlinkTarget?(target)
            return
        }

        super.mouseDown(with: event)
    }
}

struct TextKit2EditorView: NSViewControllerRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?
    var pageMentionProvider: ((String) -> [PageMentionDocument])?
    var onOpenDocumentLink: ((String) -> Void)?

    func makeCoordinator() -> TextKit2EditorCoordinator {
        TextKit2EditorCoordinator(text: $text, onTextChange: onTextChange, autoFocus: autoFocus)
    }

    func makeNSViewController(context: Context) -> TextKit2EditorViewController {
        let vc = TextKit2EditorViewController()
        vc.coordinator = context.coordinator
        vc.pageMentionProvider = pageMentionProvider
        vc.onOpenDocumentLink = onOpenDocumentLink
        vc.loadText(text)
        return vc
    }

    func updateNSViewController(_ vc: TextKit2EditorViewController, context: Context) {
        vc.pageMentionProvider = pageMentionProvider
        vc.onOpenDocumentLink = onOpenDocumentLink
        guard !context.coordinator.isUpdatingText else { return }
        guard vc.textView.window?.firstResponder !== vc.textView else { return }
        if vc.textView.string != text {
            vc.loadText(text)
        }
    }
}

final class TextKit2EditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate {
    var coordinator: TextKit2EditorCoordinator?
    var pageMentionProvider: ((String) -> [PageMentionDocument])?
    var onOpenDocumentLink: ((String) -> Void)?
    private(set) var textView: NSTextView!
    private let scrollView = NSScrollView()
    private let markdownDelegate = MarkdownTextDelegate()
    private var pendingText: String?
    private var xmlTagCollapseButtons: [NSButton] = []
    private var pageMentionSuggestionView: NSStackView?
    private var pageMentionSuggestionDocuments: [PageMentionDocument] = []
    private var selectedPageMentionSuggestionIndex = 0
    private var activePageMentionQuery: PageMentionQuery?
    private var collapsedXMLTagOpeningLocations: Set<Int> = []
    private var strikethroughObserver: NSObjectProtocol?
    private var boldObserver: NSObjectProtocol?
    private var italicObserver: NSObjectProtocol?
    private var hyperlinkObserver: NSObjectProtocol?
    private var revealedHyperlinkRanges: [NSRange] = []
    private var isRestylingText = false
    private var isOverlayRefreshScheduled = false
    private var lastOverlayLayoutSize: NSSize = .zero
    private let minimumHorizontalTextInset: CGFloat = 48
    private let maximumTextWidth: CGFloat = 600
    private let verticalTextInset: CGFloat = 16
    private var loadingImageURLs: Set<URL> = []

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Build the TextKit 2 stack explicitly for macOS.
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer()
        container.widthTracksTextView = true
        container.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)

        // Set our delegate on the content storage
        contentStorage.delegate = markdownDelegate
        layoutManager.delegate = markdownDelegate
        markdownDelegate.requestImageLoad = { [weak self] url in
            self?.requestImageLoad(for: url)
        }

        // Create NSTextView backed by the TextKit 2 container
        textView = HyperlinkOpeningTextView(frame: .zero, textContainer: container)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = MarkdownTheme.bodyFont
        textView.textColor = MarkdownTheme.bodyColor
        textView.backgroundColor = AppTheme.nsBackground
        textView.textContainerInset = NSSize(width: minimumHorizontalTextInset, height: verticalTextInset)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.setAccessibilityIdentifier("note_editor")
        textView.linkTextAttributes = [
            .foregroundColor: MarkdownTheme.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        (textView as? HyperlinkOpeningTextView)?.openHyperlinkTarget = { [weak self] target in
            switch target {
            case .external(let url):
                NSWorkspace.shared.open(url)
            case .vaultDocument(let relativePath):
                self?.onOpenDocumentLink?(relativePath)
            }
        }
        (textView as? HyperlinkOpeningTextView)?.shouldOpenHyperlinkAtIndex = { [weak self] characterIndex in
            guard let self else { return true }
            return !self.revealedHyperlinkRanges.contains { NSLocationInRange(characterIndex, $0) }
        }
        (textView as? HyperlinkOpeningTextView)?.toggleTodoMarkerAtPoint = { [weak self] point in
            self?.toggleTodoMarker(atTextViewPoint: point) ?? false
        }

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        if let pendingText {
            applyText(pendingText)
            self.pendingText = nil
        }

        strikethroughObserver = NotificationCenter.default.addObserver(
            forName: NoteEditorCommands.toggleStrikethrough,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleStrikethroughCommand()
        }

        boldObserver = NotificationCenter.default.addObserver(
            forName: NoteEditorCommands.toggleBold,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleBoldCommand()
        }

        italicObserver = NotificationCenter.default.addObserver(
            forName: NoteEditorCommands.toggleItalic,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleItalicCommand()
        }

        hyperlinkObserver = NotificationCenter.default.addObserver(
            forName: NoteEditorCommands.toggleHyperlink,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleHyperlinkCommand()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let didUpdateTextContainerInsets = syncTextContainerInsets()
        refreshEditorOverlaysAfterLayoutChangeIfNeeded(force: didUpdateTextContainerInsets)
        positionPageMentionSuggestions()
    }

    private func syncTextContainerInsets() -> Bool {
        let visibleWidth = scrollView.contentView.bounds.width
        guard visibleWidth > 0 else { return false }

        let centeredInset = floor((visibleWidth - maximumTextWidth) / 2)
        let horizontalInset = max(minimumHorizontalTextInset, centeredInset)
        let targetInset = NSSize(width: horizontalInset, height: verticalTextInset)
        guard textView.textContainerInset != targetInset else { return false }

        textView.textContainerInset = targetInset
        return true
    }

    func loadText(_ markdown: String) {
        guard isViewLoaded, textView != nil else {
            pendingText = markdown
            return
        }
        applyText(markdown)
    }

    private func applyText(_ markdown: String) {
        coordinator?.beginApplyingEditorText(markdown)
        textView.string = markdown
        coordinator?.finishApplyingEditorText()
        updateTypingAttributes()
        if coordinator?.autoFocus == true {
            DispatchQueue.main.async { [weak self] in
                guard let tv = self?.textView else { return }
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: tv.string.count, length: 0))
                self?.scheduleEditorOverlayRefresh()
            }
        }
        scheduleEditorOverlayRefresh()
        updatePageMentionSuggestions()
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        DebugTrace.record("mac textDidChange")
        if !isRestylingText {
            updateRevealedHyperlinkRangesForSelection(restyle: false)
        }
        flushTextToBinding()
        updateTypingAttributes()
        scheduleEditorOverlayRefresh()
        updatePageMentionSuggestions()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if !isRestylingText {
            updateRevealedHyperlinkRangesForSelection(restyle: true)
        }
        updateTypingAttributes()
        updatePageMentionSuggestions()
    }

    func textDidEndEditing(_ notification: Notification) {
        DebugTrace.record("mac textDidEndEditing")
        flushTextToBinding()
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        DebugTrace.record("mac textStorage didProcessEditing range=\(editedRange.location):\(editedRange.length) delta=\(delta) \(DebugTrace.textSummary(textStorage.string))")
        coordinator?.publishEditorText(textStorage.string)
    }

    private func updateTypingAttributes() {
        textView.typingAttributes = coordinator?.typingAttributes(
            for: textView.string,
            selectionLocation: textView.selectedRange().location
        ) ?? MarkdownTypingAttributes.attributes(
            for: textView.string,
            selectionLocation: textView.selectedRange().location
        )
    }

    private func flushTextToBinding() {
        DebugTrace.record("mac flushTextToBinding \(DebugTrace.textSummary(textView.textStorage?.string ?? textView.string))")
        coordinator?.publishEditorText(textView.textStorage?.string ?? textView.string)
    }

    private func handleStrikethroughCommand() {
        guard textView.window?.firstResponder === textView else { return }
        guard let transform = BlockEditingCommands.toggledStrikethrough(
            in: textView.string,
            selection: textView.selectedRange()
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    private func handleBoldCommand() {
        guard textView.window?.firstResponder === textView else { return }
        guard let transform = BlockEditingCommands.toggledBold(
            in: textView.string,
            selection: textView.selectedRange()
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    private func handleItalicCommand() {
        guard textView.window?.firstResponder === textView else { return }
        guard let transform = BlockEditingCommands.toggledItalic(
            in: textView.string,
            selection: textView.selectedRange()
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    private func handleHyperlinkCommand() {
        guard textView.window?.firstResponder === textView else { return }
        guard let transform = BlockEditingCommands.toggledHyperlink(
            in: textView.string,
            selection: textView.selectedRange()
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    private func handleIndentCommand() {
        guard textView.window?.firstResponder === textView else { return }
        guard let transform = BlockEditingCommands.indentedLines(
            in: textView.string,
            selection: textView.selectedRange()
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    private func handleOutdentCommand() {
        guard textView.window?.firstResponder === textView else { return }
        guard let transform = BlockEditingCommands.outdentedLines(
            in: textView.string,
            selection: textView.selectedRange()
        ) else {
            return
        }

        applySelectionTransform(transform)
    }

    private func applySelectionTransform(_ transform: TextSelectionTransform) {
        guard let replacement = TextEditDiff.singleReplacement(from: textView.string, to: transform.text) else {
            textView.setSelectedRange(transform.selection)
            return
        }

        let visibleOrigin = scrollView.contentView.bounds.origin
        coordinator?.beginApplyingEditorText(transform.text)
        if textView.shouldChangeText(in: replacement.range, replacementString: replacement.replacement) {
            textView.textStorage?.replaceCharacters(in: replacement.range, with: replacement.replacement)
            textView.didChangeText()
        } else {
            textView.string = transform.text
        }
        textView.setSelectedRange(transform.selection)
        restoreVisibleOrigin(visibleOrigin)
        updateTypingAttributes()
        coordinator?.commitAppliedEditorText(transform.text)
        scheduleEditorOverlayRefresh()
    }

    private func updatePageMentionSuggestions() {
        guard let pageMentionProvider,
              textView.window?.firstResponder === textView,
              let query = PageMentionMarkdown.activeQuery(
                  in: textView.string,
                  selection: textView.selectedRange()
              ) else {
            hidePageMentionSuggestions()
            return
        }

        let shouldResetSelection = query.query != activePageMentionQuery?.query
        activePageMentionQuery = query
        let normalizedQuery = query.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            pageMentionSuggestionDocuments = []
            selectedPageMentionSuggestionIndex = 0
            showPageMentionSuggestions([], emptyStateText: "Type to search documents")
            return
        }

        let documents = pageMentionProvider(query.query)
        guard !documents.isEmpty else {
            pageMentionSuggestionDocuments = []
            selectedPageMentionSuggestionIndex = 0
            showPageMentionSuggestions([], emptyStateText: "No matching documents")
            return
        }

        pageMentionSuggestionDocuments = documents
        selectedPageMentionSuggestionIndex = shouldResetSelection
            ? 0
            : min(selectedPageMentionSuggestionIndex, documents.count - 1)
        showPageMentionSuggestions(documents, emptyStateText: nil)
    }

    private func showPageMentionSuggestions(_ documents: [PageMentionDocument], emptyStateText: String?) {
        let stackView = pageMentionSuggestionView ?? makePageMentionSuggestionView()
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if let emptyStateText {
            let label = NSTextField(labelWithAttributedString: pageMentionEmptyStateTitle(emptyStateText))
            label.lineBreakMode = .byTruncatingTail
            label.setAccessibilityIdentifier("page_mention_empty_state")
            label.setAccessibilityLabel(emptyStateText)
            stackView.addArrangedSubview(label)
        }

        for (index, document) in documents.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(pageMentionSuggestionClicked(_:)))
            button.tag = index
            button.isBordered = false
            button.alignment = .left
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.attributedTitle = pageMentionButtonTitle(for: document)
            button.setAccessibilityIdentifier("page_mention_suggestion_\(index)")
            button.setAccessibilityLabel("Mention \(document.title), \(document.relativePath)")
            stackView.addArrangedSubview(button)
        }

        if stackView.superview == nil {
            view.addSubview(stackView)
        }
        refreshPageMentionSelection()
        positionPageMentionSuggestions()
    }

    private func makePageMentionSuggestionView() -> NSStackView {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 2
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stackView.wantsLayer = true
        stackView.layer?.backgroundColor = AppTheme.nsBackground.cgColor
        stackView.layer?.cornerRadius = 10
        stackView.layer?.borderColor = AppTheme.nsSeparator.cgColor
        stackView.layer?.borderWidth = 1
        stackView.layer?.shadowColor = NSColor.black.cgColor
        stackView.layer?.shadowOpacity = 0.25
        stackView.layer?.shadowRadius = 14
        stackView.layer?.shadowOffset = CGSize(width: 0, height: -8)
        pageMentionSuggestionView = stackView
        return stackView
    }

    private func pageMentionEmptyStateTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: AppTheme.nsMutedText,
            ]
        )
    }

    private func pageMentionButtonTitle(for document: PageMentionDocument) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: document.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: AppTheme.nsPrimaryText,
            ]
        )
        result.append(NSAttributedString(
            string: "\n\(document.relativePath)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: AppTheme.nsMutedText,
            ]
        ))
        return result
    }

    private func positionPageMentionSuggestions() {
        guard let stackView = pageMentionSuggestionView,
              stackView.superview != nil,
              let query = activePageMentionQuery,
              let window = textView.window else {
            return
        }

        let screenRect = textView.firstRect(
            forCharacterRange: NSRange(location: NSMaxRange(query.range), length: 0),
            actualRange: nil
        )
        guard !screenRect.isNull else { return }

        let windowRect = window.convertFromScreen(screenRect)
        let caretRect = view.convert(windowRect, from: nil)
        let horizontalMargin: CGFloat = 16
        let rowCount = max(1, min(pageMentionSuggestionDocuments.count, 5))
        let width = min(max(360, view.bounds.width * 0.45), view.bounds.width - horizontalMargin * 2)
        let height = CGFloat(rowCount) * 48 + 16
        let x = min(max(horizontalMargin, caretRect.minX), max(horizontalMargin, view.bounds.width - width - horizontalMargin))
        var y = caretRect.minY - height - 6
        if y < 8 {
            y = caretRect.maxY + 6
        }
        stackView.frame = NSRect(x: x, y: y, width: width, height: height)
    }

    private func hidePageMentionSuggestions() {
        activePageMentionQuery = nil
        pageMentionSuggestionDocuments = []
        selectedPageMentionSuggestionIndex = 0
        pageMentionSuggestionView?.removeFromSuperview()
    }

    @objc
    private func pageMentionSuggestionClicked(_ sender: NSButton) {
        selectPageMentionSuggestion(at: sender.tag)
    }

    private var isPageMentionPopoverVisible: Bool {
        pageMentionSuggestionView?.superview != nil
    }

    private var hasSelectablePageMentionSuggestion: Bool {
        isPageMentionPopoverVisible && !pageMentionSuggestionDocuments.isEmpty
    }

    private func movePageMentionSelection(by delta: Int) {
        guard hasSelectablePageMentionSuggestion else { return }
        let maxIndex = pageMentionSuggestionDocuments.count - 1
        selectedPageMentionSuggestionIndex = min(max(selectedPageMentionSuggestionIndex + delta, 0), maxIndex)
        refreshPageMentionSelection()
    }

    private func refreshPageMentionSelection() {
        guard let stackView = pageMentionSuggestionView else { return }
        for case let button as NSButton in stackView.arrangedSubviews {
            button.layer?.backgroundColor = button.tag == selectedPageMentionSuggestionIndex
                ? AppTheme.nsSeparator.withAlphaComponent(0.75).cgColor
                : NSColor.clear.cgColor
        }
    }

    private func selectCurrentPageMentionSuggestion() {
        guard hasSelectablePageMentionSuggestion else { return }
        selectPageMentionSuggestion(at: selectedPageMentionSuggestionIndex)
    }

    private func selectPageMentionSuggestion(at index: Int) {
        guard index >= 0,
              index < pageMentionSuggestionDocuments.count,
              let activePageMentionQuery else { return }

        let document = pageMentionSuggestionDocuments[index]
        let nsText = textView.string as NSString
        guard NSMaxRange(activePageMentionQuery.range) <= nsText.length else { return }

        let markdownLink = PageMentionMarkdown.markdownLink(for: document)
        let updatedText = nsText.replacingCharacters(in: activePageMentionQuery.range, with: markdownLink)
        let selection = NSRange(location: activePageMentionQuery.range.location + markdownLink.utf16.count, length: 0)
        hidePageMentionSuggestions()
        applySelectionTransform(TextSelectionTransform(text: updatedText, selection: selection))
        textView.window?.makeFirstResponder(textView)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if isPageMentionPopoverVisible {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                movePageMentionSelection(by: -1)
                return true
            }

            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                movePageMentionSelection(by: 1)
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               hasSelectablePageMentionSuggestion {
                selectCurrentPageMentionSuggestion()
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                hidePageMentionSuggestions()
                return true
            }
        }

        if commandSelector == #selector(NSResponder.deleteBackward(_:)),
           let changeRange = deletionRangeForBackwardDelete(),
           revealHyperlinkMarkdownForDeletionIfNeeded(changeRange: changeRange) {
            return true
        }

        if commandSelector == #selector(NSResponder.deleteForward(_:)),
           let changeRange = deletionRangeForForwardDelete(),
           revealHyperlinkMarkdownForDeletionIfNeeded(changeRange: changeRange) {
            return true
        }

        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            handleIndentCommand()
            return true
        }

        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            handleOutdentCommand()
            return true
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)),
           let transform = BlockEditingCommands.continuedListLineBreak(
            in: textView.string,
            selection: textView.selectedRange()
           ) {
            applySelectionTransform(transform)
            return true
        }

        return false
    }

    private func deletionRangeForBackwardDelete() -> NSRange? {
        let selection = textView.selectedRange()
        if selection.length > 0 {
            return selection
        }

        guard selection.location > 0 else { return nil }
        return NSRange(location: selection.location - 1, length: 1)
    }

    private func deletionRangeForForwardDelete() -> NSRange? {
        let selection = textView.selectedRange()
        if selection.length > 0 {
            return selection
        }

        guard selection.location < (textView.string as NSString).length else { return nil }
        return NSRange(location: selection.location, length: 1)
    }

    private func revealHyperlinkMarkdownForDeletionIfNeeded(changeRange: NSRange) -> Bool {
        guard let match = hyperlinkMatch(intersecting: changeRange, in: textView.string) else { return false }
        if revealedHyperlinkRanges.contains(where: { NSEqualRanges($0, match.fullRange) }) {
            return false
        }

        setRevealedHyperlinkRanges([match.fullRange])
        restyleTextPreservingSelection()
        return true
    }

    private func hyperlinkMatch(intersecting range: NSRange, in text: String) -> HyperlinkMarkdown.Match? {
        HyperlinkMarkdown.matches(in: text).first { match in
            if range.length == 0 {
                return NSLocationInRange(range.location, match.fullRange)
            }
            return NSIntersectionRange(range, match.fullRange).length > 0
        }
    }

    private func setRevealedHyperlinkRanges(_ ranges: [NSRange]) {
        revealedHyperlinkRanges = ranges
        markdownDelegate.revealedHyperlinkRanges = ranges
    }

    private func updateRevealedHyperlinkRangesForSelection(restyle: Bool) {
        let ranges = hyperlinkRangesOnSelectedLines(in: textView.string, selection: textView.selectedRange())
        guard !nsRangesEqual(ranges, revealedHyperlinkRanges) else { return }
        setRevealedHyperlinkRanges(ranges)
        if restyle {
            restyleTextPreservingSelection()
        }
    }

    private func hyperlinkRangesOnSelectedLines(in text: String, selection: NSRange) -> [NSRange] {
        let nsText = text as NSString
        guard nsText.length > 0, selection.location != NSNotFound else { return [] }

        let safeLocation = max(0, min(selection.location, nsText.length))
        let safeLength = max(0, min(selection.length, nsText.length - safeLocation))
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: safeLength))

        return HyperlinkMarkdown.matches(in: text)
            .map(\.fullRange)
            .filter { NSIntersectionRange($0, lineRange).length > 0 }
    }

    private func nsRangesEqual(_ lhs: [NSRange], _ rhs: [NSRange]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            guard NSEqualRanges(left, right) else { return false }
        }
        return true
    }

    private func restyleTextPreservingSelection() {
        applyHyperlinkRenderAttributesToTextStorage()
        updateTypingAttributes()
        scheduleEditorOverlayRefresh()
    }

    private func applyHyperlinkRenderAttributesToTextStorage() {
        guard let textStorage = textView.textStorage else { return }
        let matches = HyperlinkMarkdown.matches(in: textView.string)

        for match in matches {
            guard let url = match.url else { continue }
            let isRevealed = revealedHyperlinkRanges.contains { NSEqualRanges($0, match.fullRange) }
            textStorage.removeAttribute(.link, range: match.fullRange)
            textStorage.addAttributes([
                .font: MarkdownTheme.bodyFont,
                .foregroundColor: MarkdownTheme.bodyColor,
                .underlineStyle: 0,
            ], range: match.fullRange)

            if !isRevealed {
                textStorage.addAttributes([
                    .link: url,
                    .foregroundColor: MarkdownTheme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: match.titleRange)
            }

            for syntaxRange in hyperlinkSyntaxRanges(for: match) {
                if isRevealed {
                    textStorage.addAttributes([
                        .font: MarkdownTheme.bodyFont,
                        .foregroundColor: MarkdownTheme.prefixColor,
                        .underlineStyle: 0,
                    ], range: syntaxRange)
                } else {
                    textStorage.addAttributes([
                        .font: PlatformFont.systemFont(ofSize: MarkdownVisualSpec.hyperlinkSyntaxVisualWidth, weight: .regular),
                        .foregroundColor: PlatformColor.clear,
                        .underlineStyle: 0,
                    ], range: syntaxRange)
                }
            }
        }
    }

    private func hyperlinkSyntaxRanges(for match: HyperlinkMarkdown.Match) -> [NSRange] {
        [
            NSRange(location: match.fullRange.location, length: 1),
            NSRange(location: NSMaxRange(match.titleRange), length: 2),
            match.urlRange,
            NSRange(location: NSMaxRange(match.urlRange), length: 1),
        ]
    }

    private func scheduleEditorOverlayRefresh() {
        guard !isOverlayRefreshScheduled else { return }
        isOverlayRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isOverlayRefreshScheduled = false
            self.refreshEditorOverlays()
        }
    }

    private func refreshEditorOverlaysAfterLayoutChangeIfNeeded(force: Bool = false) {
        let size = textView.bounds.size
        guard force || size != lastOverlayLayoutSize else { return }
        lastOverlayLayoutSize = size
        refreshEditorOverlays()
    }

    private func refreshEditorOverlays() {
        syncCollapsedXMLTagState()
        refreshXMLTagCollapseButtons()
    }

    private func refreshXMLTagCollapseButtons() {
        guard isViewLoaded, textView != nil else { return }

        xmlTagCollapseButtons.forEach { $0.removeFromSuperview() }
        xmlTagCollapseButtons.removeAll()

        let blocks = XMLLikeTagParser.blocks(in: textView.string)
        guard !blocks.isEmpty else { return }

        textView.layoutSubtreeIfNeeded()

        for block in blocks {
            addXMLTagCollapseButton(for: block)
        }
    }

    private func addXMLTagCollapseButton(for block: XMLLikeTagBlock) {
        let screenRect = textView.firstRect(
            forCharacterRange: NSRange(location: block.openingLineRange.location, length: 0),
            actualRange: nil
        )

        guard let window = textView.window,
              !screenRect.isNull,
              screenRect.origin.x.isFinite,
              screenRect.origin.y.isFinite,
              screenRect.size.width.isFinite,
              screenRect.size.height.isFinite else {
            return
        }

        let windowRect = window.convertFromScreen(screenRect)
        let caretRect = textView.convert(windowRect, from: nil)
        guard !caretRect.isNull,
              caretRect.origin.x.isFinite,
              caretRect.origin.y.isFinite,
              caretRect.size.width.isFinite,
              caretRect.size.height.isFinite else {
            return
        }

        let buttonSize = MarkdownVisualSpec.xmlTagCollapseControlSize
        let hitTargetWidth = max(CGFloat(44), caretRect.minX + 6)
        let hitTargetHeight = max(CGFloat(32), buttonSize)
        let isCollapsed = collapsedXMLTagOpeningLocations.contains(block.openingLineRange.location)
        let button = NSButton()
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.bezelStyle = .shadowlessSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(
            systemSymbolName: isCollapsed ? "chevron.right" : "chevron.down",
            accessibilityDescription: nil
        )
        button.contentTintColor = AppTheme.nsMutedText
        button.target = self
        button.action = #selector(xmlTagCollapseButtonTapped(_:))
        button.tag = block.openingLineRange.location
        button.setAccessibilityIdentifier("xml_tag_collapse_\(block.openingLineRange.location)")
        button.setAccessibilityLabel(isCollapsed ? "Expand \(block.tagName)" : "Collapse \(block.tagName)")
        button.wantsLayer = true
        button.layer?.backgroundColor = (textView.backgroundColor ?? AppTheme.nsBackground).cgColor
        button.imageScaling = .scaleProportionallyDown
        button.frame = NSRect(
            x: 0,
            y: caretRect.midY - hitTargetHeight / 2,
            width: hitTargetWidth,
            height: hitTargetHeight
        )

        textView.addSubview(button)
        xmlTagCollapseButtons.append(button)
    }

    @objc
    private func xmlTagCollapseButtonTapped(_ sender: NSButton) {
        let openingLocation = sender.tag
        let visibleOrigin = scrollView.contentView.bounds.origin
        if collapsedXMLTagOpeningLocations.contains(openingLocation) {
            collapsedXMLTagOpeningLocations.remove(openingLocation)
        } else {
            collapsedXMLTagOpeningLocations.insert(openingLocation)
        }
        syncCollapsedXMLTagState()
        rebuildTextLayoutPreservingSelection()
        refreshEditorOverlays()
        restoreVisibleOrigin(visibleOrigin)
        refreshEditorOverlaysAfterTextLayoutSettles(restoring: visibleOrigin)
    }

    private func syncCollapsedXMLTagState() {
        let blocks = XMLLikeTagParser.blocks(in: textView.string)
        let validOpeningLocations = Set(blocks.map(\.openingLineRange.location))
        collapsedXMLTagOpeningLocations = collapsedXMLTagOpeningLocations.intersection(validOpeningLocations)
        markdownDelegate.collapsedXMLTagRanges = blocks
            .filter { collapsedXMLTagOpeningLocations.contains($0.openingLineRange.location) }
            .map(\.collapsedContentRange)
    }

    private func rebuildTextLayoutPreservingSelection() {
        let currentText = textView.string
        let selectedRange = textView.selectedRange()
        isRestylingText = true
        textView.string = currentText
        isRestylingText = false
        textView.setSelectedRange(NSRange(
            location: min(selectedRange.location, (currentText as NSString).length),
            length: min(selectedRange.length, max(0, (currentText as NSString).length - selectedRange.location))
        ))
        updateTypingAttributes()
    }

    private func refreshEditorOverlaysAfterTextLayoutSettles(restoring origin: NSPoint) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.restoreVisibleOrigin(origin)
            self.forceEditorLayout()
            self.refreshEditorOverlays()
            self.restoreVisibleOrigin(origin)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.restoreVisibleOrigin(origin)
                self.forceEditorLayout()
                self.refreshEditorOverlays()
                self.restoreVisibleOrigin(origin)
            }
        }
    }

    private func forceEditorLayout() {
        view.needsLayout = true
        textView.needsLayout = true
        view.layoutSubtreeIfNeeded()
        textView.layoutSubtreeIfNeeded()
    }

    private func requestImageLoad(for url: URL) {
        guard loadingImageURLs.insert(url).inserted else { return }

        MarkdownImageLoader.load(url: url) { [weak self] _ in
            guard let self else { return }
            self.loadingImageURLs.remove(url)
            self.invalidateImageFragments()
        }
    }

    private func invalidateImageFragments() {
        guard isViewLoaded, textView != nil else { return }
        guard let layoutManager = textView.textLayoutManager,
              let documentRange = layoutManager.textContentManager?.documentRange else {
            textView.needsDisplay = true
            return
        }

        layoutManager.invalidateLayout(for: documentRange)
        layoutManager.ensureLayout(for: documentRange)
        view.needsLayout = true
        textView.needsLayout = true
        view.layoutSubtreeIfNeeded()
        textView.layoutSubtreeIfNeeded()
        textView.needsDisplay = true
    }

    @discardableResult
    func toggleTodoMarker(atTextViewPoint point: NSPoint) -> Bool {
        syncCollapsedXMLTagState()
        guard let block = todoBlock(containingMarkerPoint: point) else { return false }
        toggleTodoCheckbox(atParagraphLocation: block.paragraphRange.location)
        return true
    }

    func todoMarkerHitRect(forParagraphLocation paragraphLocation: Int) -> NSRect? {
        syncCollapsedXMLTagState()
        guard let block = MarkdownSemanticAnalyzer.renderableBlocks(
            in: textView.string,
            collapsedXMLTagRanges: markdownDelegate.collapsedXMLTagRanges
        ).first(where: { $0.paragraphRange.location == paragraphLocation }),
              !block.isCollapsedXMLTagContent,
              case .todo = block.kind else {
            return nil
        }

        let prefixLength = block.kind.prefixLength(in: block.lineText)
        let contentLocation = paragraphLocation + prefixLength
        let screenRect = textView.firstRect(
            forCharacterRange: NSRange(location: contentLocation, length: 0),
            actualRange: nil
        )

        guard let window = textView.window,
              isFiniteRect(screenRect) else {
            return nil
        }

        let windowRect = window.convertFromScreen(screenRect)
        let caretRect = textView.convert(windowRect, from: nil)
        guard isFiniteRect(caretRect) else { return nil }

        let markerRect = TodoMarkerGeometry.markerRect(
            contentLeadingX: caretRect.minX,
            lineMidY: caretRect.midY
        )
        let hitLeading = max(0, markerRect.minX - 8)
        let hitTrailing = max(markerRect.maxX, caretRect.minX + 8)
        return NSRect(
            x: hitLeading,
            y: markerRect.minY,
            width: hitTrailing - hitLeading,
            height: markerRect.height
        )
    }

    private func todoBlock(containingMarkerPoint point: NSPoint) -> MarkdownRenderableBlock? {
        let blocks = MarkdownSemanticAnalyzer.renderableBlocks(
            in: textView.string,
            collapsedXMLTagRanges: markdownDelegate.collapsedXMLTagRanges
        )

        for block in blocks where !block.isCollapsedXMLTagContent {
            guard case .todo = block.kind,
                  let rect = todoMarkerHitRect(forParagraphLocation: block.paragraphRange.location),
                  rect.insetBy(dx: -4, dy: -4).contains(point) else {
                continue
            }
            return block
        }

        return nil
    }

    private func isFiniteRect(_ rect: NSRect) -> Bool {
        !rect.isNull &&
        rect.origin.x.isFinite &&
        rect.origin.y.isFinite &&
        rect.size.width.isFinite &&
        rect.size.height.isFinite
    }

    private func toggleTodoCheckbox(atParagraphLocation paragraphLocation: Int) {
        let nsText = textView.string as NSString
        guard paragraphLocation >= 0, paragraphLocation < nsText.length else { return }

        let paragraphRange = nsText.paragraphRange(for: NSRange(location: paragraphLocation, length: 0))
        let lineRange = MarkdownLineRanges.visibleLineRange(from: paragraphRange, in: nsText)
        let lineText = nsText.substring(with: lineRange)
        let toggledLine = TodoMarkdown.checkboxToggledLine(lineText)
        guard toggledLine != lineText else { return }

        let updatedText = nsText.replacingCharacters(in: lineRange, with: toggledLine)
        let selectedRange = textView.selectedRange()
        let adjustedSelection = NSRange(
            location: min(selectedRange.location, (updatedText as NSString).length),
            length: min(selectedRange.length, max(0, (updatedText as NSString).length - selectedRange.location))
        )
        applySelectionTransform(TextSelectionTransform(text: updatedText, selection: adjustedSelection))
    }

    private func restoreVisibleOrigin(_ origin: NSPoint) {
        scrollView.layoutSubtreeIfNeeded()
        textView.layoutSubtreeIfNeeded()

        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxX = max(0, documentSize.width - clipView.bounds.width)
        let maxY = max(0, documentSize.height - clipView.bounds.height)
        let clampedOrigin = NSPoint(
            x: min(max(origin.x, 0), maxX),
            y: min(max(origin.y, 0), maxY)
        )

        clipView.scroll(to: clampedOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        flushTextToBinding()
    }

    deinit {
        if let strikethroughObserver {
            NotificationCenter.default.removeObserver(strikethroughObserver)
        }
        if let boldObserver {
            NotificationCenter.default.removeObserver(boldObserver)
        }
        if let italicObserver {
            NotificationCenter.default.removeObserver(italicObserver)
        }
        if let hyperlinkObserver {
            NotificationCenter.default.removeObserver(hyperlinkObserver)
        }
    }
}

#endif
