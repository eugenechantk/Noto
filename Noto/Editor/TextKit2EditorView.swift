import SwiftUI
import os.log
import UniformTypeIdentifiers

#if os(iOS)
import PhotosUI
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "TextKit2Editor")

private enum HyperlinkInsertionStrings {
    static let title = "Insert Link"
    static let destinationPlaceholder = "URL or note path"
    static let cancel = "Cancel"
    static let insert = "Insert"
}

enum ReadableTextColumnLayout {
    static func textHorizontalInset(
        for availableWidth: CGFloat,
        maximumTextWidth: CGFloat,
        minimumHorizontalInset: CGFloat,
        constrainsToReadableWidth: Bool
    ) -> CGFloat {
        guard constrainsToReadableWidth, availableWidth > 0 else {
            return minimumHorizontalInset
        }

        let centeredInset = floor((availableWidth - maximumTextWidth) / 2)
        return max(minimumHorizontalInset, centeredInset)
    }
}

enum NoteEditorCommands {
    static let toggleStrikethrough = Notification.Name("NoteEditorCommands.toggleStrikethrough")
    static let toggleBold = Notification.Name("NoteEditorCommands.toggleBold")
    static let toggleItalic = Notification.Name("NoteEditorCommands.toggleItalic")
    static let toggleHyperlink = Notification.Name("NoteEditorCommands.toggleHyperlink")
    static let showFind = Notification.Name("NoteEditorCommands.showFind")
    static let closeFind = Notification.Name("NoteEditorCommands.closeFind")

    static func requestToggleStrikethrough() {
        NotificationCenter.default.post(name: toggleStrikethrough, object: commandTarget)
    }

    static func requestToggleBold() {
        NotificationCenter.default.post(name: toggleBold, object: commandTarget)
    }

    static func requestToggleItalic() {
        NotificationCenter.default.post(name: toggleItalic, object: commandTarget)
    }

    static func requestToggleHyperlink() {
        NotificationCenter.default.post(name: toggleHyperlink, object: commandTarget)
    }

    static func requestShowFind() {
        NotificationCenter.default.post(name: showFind, object: commandTarget)
    }

    static func requestCloseFind() {
        NotificationCenter.default.post(name: closeFind, object: commandTarget)
    }

    private static var commandTarget: Any? {
        #if os(macOS)
        NotoCommandTarget.activeWindow
        #else
        nil
        #endif
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

private struct EditorFindBackgroundSnapshot {
    let range: NSRange
    let value: Any?
}

private enum EditorFindHighlightPalette {
    static var matchBackground: PlatformColor {
        PlatformColor.white.withAlphaComponent(0.34)
    }

    static var currentMatchBackground: PlatformColor {
        PlatformColor.systemYellow.withAlphaComponent(0.62)
    }
}

// MARK: - MarkdownImageLink

struct MarkdownImageLink: Equatable {
    let urlString: String
    let altText: String
    var resolvedURL: URL? = nil

    var url: URL? {
        if let resolvedURL {
            return resolvedURL
        }

        guard let url = URL(string: urlString),
              url.scheme != nil else {
            return nil
        }
        return url
    }

    func resolving(relativeTo vaultRootURL: URL?) -> MarkdownImageLink {
        guard let vaultRootURL,
              resolvedURL == nil,
              !urlString.hasPrefix("/") else {
            return self
        }

        if let absoluteURL = URL(string: urlString),
           absoluteURL.scheme != nil {
            return self
        }

        let decodedPath = urlString.removingPercentEncoding ?? urlString
        let components = decodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return self
        }

        var fileURL = vaultRootURL
        for component in components {
            fileURL.appendPathComponent(component)
        }

        var resolved = self
        resolved.resolvedURL = fileURL.standardizedFileURL
        return resolved
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
    case divider
    case xmlTag
    case collapsedXMLTagContent

    static func detect(from text: String, vaultRootURL: URL? = nil) -> MarkdownBlockKind {
        let indentCount = text.prefix(while: { $0 == " " }).count
        let indent = indentCount / 2
        let stripped = String(text.dropFirst(indentCount))

        if let imageLink = MarkdownImageLinkParser.parse(from: stripped) {
            return .imageLink(imageLink.resolving(relativeTo: vaultRootURL))
        }

        if stripped == "---" {
            return .divider
        }

        if stripped.hasPrefix("- [ ] ") {
            return .todo(checked: false, indent: indent)
        }
        if stripped.hasPrefix("- [x] ") || stripped.hasPrefix("- [X] ") {
            return .todo(checked: true, indent: indent)
        }
        if isNonRenderableTodoPrefix(stripped) {
            return .paragraph
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
            return 0
        case .bullet:
            return indentCount + (stripped.hasPrefix("- ") || stripped.hasPrefix("* ") || stripped.hasPrefix("• ") ? 2 : 0)
        case .orderedList(let number, _):
            let marker = "\(number). "
            return indentCount + (stripped.hasPrefix(marker) ? marker.count : 0)
        case .frontmatter, .paragraph, .imageLink, .divider, .xmlTag, .collapsedXMLTagContent: return 0
        }
    }

    private static func isNonRenderableTodoPrefix(_ stripped: String) -> Bool {
        let exactPendingPrefixes = ["- [", "- [ ", "- [x", "- [X", "- [ ]", "- [x]", "- [X]"]
        if exactPendingPrefixes.contains(stripped) {
            return true
        }

        if stripped.hasPrefix("- [ ]"), stripped != "- [ ] " {
            return true
        }

        if stripped.hasPrefix("- [x]"), stripped != "- [x] " {
            return true
        }

        if stripped.hasPrefix("- [X]"), stripped != "- [X] " {
            return true
        }

        return false
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
        case .todo, .imageLink, .divider:
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
        renderableBlocks(in: text as NSString, collapsedXMLTagRanges: collapsedXMLTagRanges, intersecting: nil)
    }

    static func renderableBlocks(
        in text: NSString,
        collapsedXMLTagRanges: [NSRange] = []
    ) -> [MarkdownRenderableBlock] {
        renderableBlocks(in: text, collapsedXMLTagRanges: collapsedXMLTagRanges, intersecting: nil)
    }

    static func renderableBlocks(
        in text: String,
        collapsedXMLTagRanges: [NSRange] = [],
        intersecting targetRange: NSRange?
    ) -> [MarkdownRenderableBlock] {
        renderableBlocks(in: text as NSString, collapsedXMLTagRanges: collapsedXMLTagRanges, intersecting: targetRange)
    }

    static func renderableBlocks(
        in nsText: NSString,
        collapsedXMLTagRanges: [NSRange] = [],
        intersecting targetRange: NSRange?
    ) -> [MarkdownRenderableBlock] {
        guard nsText.length > 0 else { return [] }
        let frontmatterRange = MarkdownFrontmatter.range(in: nsText)

        var blocks: [MarkdownRenderableBlock] = []
        let safeTargetRange = targetRange.flatMap { range -> NSRange? in
            guard range.location != NSNotFound else { return nil }
            let safeLocation = max(0, min(range.location, nsText.length))
            let safeLength = max(0, min(range.length, nsText.length - safeLocation))
            return NSRange(location: safeLocation, length: safeLength)
        }
        let scanLimit = safeTargetRange.map(NSMaxRange) ?? nsText.length
        let initialLocation = safeTargetRange?.location ?? 0
        var paragraphLocation = nsText.paragraphRange(
            for: NSRange(location: min(initialLocation, max(nsText.length - 1, 0)), length: 0)
        ).location

        while paragraphLocation < nsText.length, paragraphLocation <= scanLimit {
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: paragraphLocation, length: 0))
            let visibleLineRange = MarkdownLineRanges.visibleLineRange(from: paragraphRange, in: nsText)
            if let safeTargetRange,
               NSIntersectionRange(paragraphRange, safeTargetRange).length == 0,
               !(safeTargetRange.length == 0 && NSLocationInRange(safeTargetRange.location, paragraphRange)) {
                let nextLocation = NSMaxRange(paragraphRange)
                guard nextLocation > paragraphLocation else { break }
                paragraphLocation = nextLocation
                continue
            }

            let lineText = nsText.substring(with: visibleLineRange)
            let isCollapsed = collapsedXMLTagRanges.contains { collapsedRange in
                NSIntersectionRange(visibleLineRange, collapsedRange).length > 0
            }
            let kind: MarkdownBlockKind = MarkdownFrontmatter.contains(position: paragraphRange.location, inRange: frontmatterRange)
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
        range(in: fullText as NSString)
    }

    static func range(in fullText: NSString) -> NSRange? {
        guard fullText.length > 0 else { return nil }

        let openingLineRange = fullText.lineRange(for: NSRange(location: 0, length: 0))
        let openingVisibleRange = MarkdownLineRanges.visibleLineRange(from: openingLineRange, in: fullText)
        guard fullText.substring(with: openingVisibleRange) == "---" else { return nil }

        var location = NSMaxRange(openingLineRange)
        while location < fullText.length {
            let lineRange = fullText.lineRange(for: NSRange(location: location, length: 0))
            let visibleLineRange = MarkdownLineRanges.visibleLineRange(from: lineRange, in: fullText)
            if fullText.substring(with: visibleLineRange) == "---" {
                return NSRange(location: 0, length: NSMaxRange(visibleLineRange))
            }

            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return nil
    }

    static func contains(position: Int, in fullText: String) -> Bool {
        guard let range = range(in: fullText) else { return false }
        return NSLocationInRange(position, range)
    }

    static func contains(position: Int, inRange frontmatterRange: NSRange?) -> Bool {
        guard let frontmatterRange else { return false }
        return NSLocationInRange(position, frontmatterRange)
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

    // Legacy list indent values kept for inactive block-editor compatibility.
    static let listBaseIndent: CGFloat = 12
    static let listIndentStep: CGFloat = 4
    // Bullets, ordered lists, and todos all share this marker-to-text gap.
    static let listMarkerTextGap: CGFloat = 8
    static let todoPrefixVisualWidth: CGFloat = 2
    static let hyperlinkSyntaxVisualWidth: CGFloat = 0.01
    static let todoControlSize: CGFloat = 28
    static let todoSymbolSize: CGFloat = 20
    static let todoTextStartOffset: CGFloat = todoSymbolSize + listMarkerTextGap
    static let todoMarkerHitInset: CGFloat = max(0, (todoControlSize - todoSymbolSize) / 2)
    static let todoVisibleInset: CGFloat = 1
    static let todoCheckedVisibleInset: CGFloat = 2
    static let todoOutlineWidth: CGFloat = 2
    static let todoCheckmarkWidth: CGFloat = 2
    static let imagePreviewReservedHeight: CGFloat = 300
    static let imagePreviewVerticalPadding: CGFloat = 8
    static let imagePreviewCornerRadius: CGFloat = 8
    static let imagePreviewBackingFontSize: CGFloat = 0.01
    static let xmlTagCollapseControlSize: CGFloat = 24
    static let collapsedXMLTagContentFontSize: CGFloat = 0.01
    static let dividerLineHeight: CGFloat = 1
    static let dividerVerticalPadding: CGFloat = 10

    static func listLeadingOffset(for indentLevel: Int) -> CGFloat {
        listBaseIndent + CGFloat(indentLevel) * listIndentStep
    }

    static func font(for kind: MarkdownBlockKind) -> Font {
        switch kind {
        case .heading(1): return h1Font
        case .heading(2): return h2Font
        case .heading(3): return h3Font
        case .xmlTag: return codeFont
        case .divider:
            return bodyFont
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
    static let listMarkerTextGap = MarkdownVisualSpec.listMarkerTextGap
    static let todoPrefixVisualWidth = MarkdownVisualSpec.todoPrefixVisualWidth
    static let todoTextStartOffset = MarkdownVisualSpec.todoTextStartOffset

    #if os(iOS)
    static let bodyColor: PlatformColor = AppTheme.uiPrimaryText
    static let prefixColor: PlatformColor = AppTheme.uiMutedText
    static let checkedTextColor: PlatformColor = AppTheme.uiSecondaryText
    static let todoUncheckedColor: PlatformColor = .systemGray2
    static let todoCheckedFillColor: PlatformColor = .systemGreen
    static let todoCheckmarkColor: PlatformColor = .white
    static let codeColor: PlatformColor = AppTheme.uiSecondaryText
    static let codeBgColor: PlatformColor = AppTheme.uiCodeBackground
    static let linkColor: PlatformColor = .systemBlue
    #elseif os(macOS)
    static let bodyColor: PlatformColor = AppTheme.nsPrimaryText
    static let prefixColor: PlatformColor = AppTheme.nsMutedText
    static let checkedTextColor: PlatformColor = AppTheme.nsSecondaryText
    static let todoUncheckedColor: PlatformColor = .tertiaryLabelColor
    static let todoCheckedFillColor: PlatformColor = .systemGreen
    static let todoCheckmarkColor: PlatformColor = .white
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
            let indentPt = sourceIndentWidth(for: kind, text: text, indentLevel: indent)
            let contentIndent = listContentIndent(for: kind, text: text)
            let hiddenPrefixWidth = todoHiddenPrefixWidth(for: kind, text: text)
            let trailingSpaceCompensation = todoTrailingSpaceWidthCompensation(for: kind, text: text)
            paraStyle.firstLineHeadIndent = indentPt + contentIndent - hiddenPrefixWidth - trailingSpaceCompensation
            paraStyle.headIndent = indentPt + contentIndent
            paraStyle.paragraphSpacingBefore = 4

        case .bullet(let indent):
            let indentPt = sourceIndentWidth(for: kind, text: text, indentLevel: indent)
            let contentIndent = listContentIndent(for: kind, text: text)
            paraStyle.firstLineHeadIndent = indentPt
            paraStyle.headIndent = indentPt + contentIndent
            paraStyle.paragraphSpacingBefore = 4

        case .orderedList(_, let indent):
            let indentPt = sourceIndentWidth(for: kind, text: text, indentLevel: indent)
            let contentIndent = listContentIndent(for: kind, text: text)
            paraStyle.firstLineHeadIndent = indentPt
            paraStyle.headIndent = indentPt + contentIndent
            paraStyle.paragraphSpacingBefore = 4

        case .frontmatter:
            paraStyle.lineSpacing = 0
            paraStyle.minimumLineHeight = MarkdownVisualSpec.collapsedXMLTagContentFontSize
            paraStyle.maximumLineHeight = MarkdownVisualSpec.collapsedXMLTagContentFontSize
            paraStyle.paragraphSpacingBefore = 0
            paraStyle.paragraphSpacing = 0

        case .imageLink:
            paraStyle.lineSpacing = 0
            paraStyle.lineBreakMode = .byClipping
            paraStyle.minimumLineHeight = MarkdownVisualSpec.imagePreviewReservedHeight
            paraStyle.maximumLineHeight = MarkdownVisualSpec.imagePreviewReservedHeight
            paraStyle.paragraphSpacingBefore = 10
            paraStyle.paragraphSpacing = 12

        case .divider:
            paraStyle.lineSpacing = 0
            paraStyle.paragraphSpacingBefore = MarkdownVisualSpec.dividerVerticalPadding
            paraStyle.paragraphSpacing = MarkdownVisualSpec.dividerVerticalPadding

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
            paraStyle.paragraphSpacingBefore = paragraphUsesListSpacingWhileTyping(text) ? 4 : 6
        }

        return paraStyle
    }

    static func sourceIndentWidth(for kind: MarkdownBlockKind, text: String, indentLevel: Int) -> CGFloat {
        let _ = indentLevel
        let leadingSpaces = text.prefix(while: { $0 == " " }).count
        guard leadingSpaces > 0 else { return 0 }

        let indentString = String(repeating: " ", count: leadingSpaces)
        let font = MarkdownTheme.font(for: kind)
        return ceil((indentString as NSString).size(withAttributes: [.font: font]).width)
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

    static func todoHiddenPrefixWidth(for kind: MarkdownBlockKind, text: String) -> CGFloat {
        guard case .todo = kind else { return 0 }

        let prefixLength = kind.prefixLength(in: text)
        let fullLength = (text as NSString).length
        let hiddenPrefixLength = todoHiddenPrefixLength(prefixLength: prefixLength, fullLength: fullLength)
        guard hiddenPrefixLength > 0 else { return 0 }

        let hiddenPrefix = String((text as NSString).substring(to: hiddenPrefixLength))
        let hiddenFont = PlatformFont.systemFont(ofSize: MarkdownTheme.todoPrefixVisualWidth, weight: .regular)
        return ceil((hiddenPrefix as NSString).size(withAttributes: [.font: hiddenFont]).width)
    }

    static func todoTrailingSpaceWidthCompensation(for kind: MarkdownBlockKind, text: String) -> CGFloat {
        guard case .todo = kind else { return 0 }

        let prefixLength = kind.prefixLength(in: text)
        let fullLength = (text as NSString).length
        guard prefixLength > 0, prefixLength == fullLength, text.hasSuffix(" ") else { return 0 }

        return ceil((" " as NSString).size(withAttributes: [.font: MarkdownTheme.font(for: kind)]).width)
    }

    static func style(
        text: String,
        kind: MarkdownBlockKind,
        paragraphLocation: Int = 0,
        revealedHyperlinkRanges: [NSRange] = [],
        revealedDividerRanges: [NSRange] = []
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
                .foregroundColor: checked ? MarkdownTheme.checkedTextColor : MarkdownTheme.bodyColor,
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
                .font: PlatformFont.systemFont(
                    ofSize: MarkdownVisualSpec.collapsedXMLTagContentFontSize,
                    weight: .regular
                ),
                .foregroundColor: PlatformColor.clear,
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

        case .divider:
            let fullDocumentRange = NSRange(location: paragraphLocation, length: fullRange.length)
            let isRevealed = revealedDividerRanges.contains { NSEqualRanges($0, fullDocumentRange) }
            attributed.addAttributes([
                .font: MarkdownTheme.bodyFont,
                .foregroundColor: isRevealed ? MarkdownTheme.bodyColor : PlatformColor.clear,
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

    private static func paragraphUsesListSpacingWhileTyping(_ text: String) -> Bool {
        let stripped = String(text.dropFirst(text.prefix(while: { $0 == " " }).count))
        guard !stripped.isEmpty else { return false }

        if stripped == "-" || stripped == "*" || stripped == "•" {
            return true
        }

        if stripped.hasPrefix("- [") {
            return true
        }

        guard let dotIndex = stripped.firstIndex(of: "."),
              dotIndex > stripped.startIndex,
              stripped[stripped.startIndex..<dotIndex].allSatisfy(\.isNumber) else {
            return false
        }

        return stripped.distance(from: stripped.startIndex, to: dotIndex) == stripped.count - 1
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
        return attributes(in: nsText, selectionLocation: selectionLocation)
    }

    static func attributes(in nsText: NSString, selectionLocation: Int) -> [NSAttributedString.Key: Any] {
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
        let controlLeading = contentLeadingX - MarkdownVisualSpec.todoTextStartOffset
        return CGRect(
            x: controlLeading - MarkdownVisualSpec.todoMarkerHitInset,
            y: lineMidY - controlSize / 2,
            width: controlSize,
            height: controlSize
        ).integral
    }

    static func symbolRect(in markerRect: CGRect) -> CGRect {
        CGRect(
            x: markerRect.minX + MarkdownVisualSpec.todoMarkerHitInset,
            y: markerRect.midY - MarkdownVisualSpec.todoSymbolSize / 2,
            width: MarkdownVisualSpec.todoSymbolSize,
            height: MarkdownVisualSpec.todoSymbolSize
        )
    }

}

#if os(iOS)
final class TodoMarkerButton: UIControl {
    var paragraphLocation: Int = 0
    var isChecked = false {
        didSet { setNeedsDisplay() }
    }
    var markerRectInBounds = CGRect(
        x: 0,
        y: 0,
        width: MarkdownVisualSpec.todoControlSize,
        height: MarkdownVisualSpec.todoControlSize
    ) {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()
        defer { context.restoreGState() }

        let symbolRect = TodoMarkerGeometry.symbolRect(in: markerRectInBounds)
        let uncheckedColor = MarkdownTheme.todoUncheckedColor.cgColor
        let checkedFillColor = MarkdownTheme.todoCheckedFillColor.cgColor
        let checkmarkColor = MarkdownTheme.todoCheckmarkColor.cgColor

        if isChecked {
            context.setFillColor(checkedFillColor)
            context.fillEllipse(
                in: symbolRect.insetBy(
                    dx: MarkdownVisualSpec.todoCheckedVisibleInset,
                    dy: MarkdownVisualSpec.todoCheckedVisibleInset
                )
            )
        } else {
            context.setStrokeColor(uncheckedColor)
            context.setLineWidth(MarkdownVisualSpec.todoOutlineWidth)
            context.strokeEllipse(
                in: symbolRect.insetBy(
                    dx: MarkdownVisualSpec.todoOutlineWidth / 2,
                    dy: MarkdownVisualSpec.todoOutlineWidth / 2
                )
            )
            return
        }

        let checkmarkRect = symbolRect.insetBy(
            dx: MarkdownVisualSpec.todoCheckedVisibleInset,
            dy: MarkdownVisualSpec.todoCheckedVisibleInset
        )
        let checkPath = CGMutablePath()
        checkPath.move(to: CGPoint(x: checkmarkRect.minX + checkmarkRect.width * 0.26, y: checkmarkRect.midY))
        checkPath.addLine(to: CGPoint(x: checkmarkRect.minX + checkmarkRect.width * 0.43, y: checkmarkRect.maxY - checkmarkRect.height * 0.30))
        checkPath.addLine(to: CGPoint(x: checkmarkRect.maxX - checkmarkRect.width * 0.22, y: checkmarkRect.minY + checkmarkRect.height * 0.30))
        context.addPath(checkPath)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(checkmarkColor)
        context.setLineWidth(MarkdownVisualSpec.todoCheckmarkWidth)
        context.strokePath()
    }
}
#endif

// MARK: - XMLCollapseControlGeometry

enum XMLCollapseControlGeometry {
    static func buttonFrame(
        for fragment: NSTextLayoutFragment
    ) -> CGRect {
        let anchorBounds = fragment.textLineFragments.first?.typographicBounds
            ?? CGRect(origin: .zero, size: fragment.layoutFragmentFrame.size)
        let buttonSize = MarkdownVisualSpec.xmlTagCollapseControlSize
        let hitTargetWidth = max(CGFloat(44), fragment.layoutFragmentFrame.minX + 6)
        let hitTargetHeight = max(CGFloat(32), buttonSize)

        return CGRect(
            x: 0,
            y: fragment.layoutFragmentFrame.minY + anchorBounds.midY - hitTargetHeight / 2,
            width: hitTargetWidth,
            height: hitTargetHeight
        )
    }
}

// MARK: - TodoLayoutFragment

final class TodoLayoutFragment: NSTextLayoutFragment {
    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
    }

    static func markerRect(
        fragmentFrame: CGRect,
        point: CGPoint = .zero,
        indent: Int
    ) -> CGRect {
        let _ = indent
        return TodoMarkerGeometry.markerRect(
            contentLeadingX: point.x + MarkdownVisualSpec.todoTextStartOffset,
            lineMidY: point.y + fragmentFrame.midY
        )
    }
}

// MARK: - ImageLayoutFragment

enum ImageFragmentGeometry {
    static func imageRect(
        fragmentFrame: CGRect,
        point: CGPoint = .zero,
        availableContentWidth: CGFloat? = nil
    ) -> CGRect {
        let verticalPadding = MarkdownVisualSpec.imagePreviewVerticalPadding
        let resolvedWidth = max(fragmentFrame.width, availableContentWidth ?? fragmentFrame.width)
        return CGRect(
            x: point.x,
            y: point.y + verticalPadding,
            width: resolvedWidth,
            height: max(0, fragmentFrame.height - verticalPadding * 2)
        ).integral
    }

    static func aspectFitRect(
        imageSize: CGSize,
        in bounds: CGRect
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    static func aspectAdjustedFragmentHeight(
        imageSize: CGSize,
        containerWidth: CGFloat
    ) -> CGFloat? {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerWidth > 0,
              containerWidth.isFinite else {
            return nil
        }

        let imageHeight = containerWidth * (imageSize.height / imageSize.width)
        return imageHeight + MarkdownVisualSpec.imagePreviewVerticalPadding * 2
    }
}

final class ImageLayoutFragment: NSTextLayoutFragment {
    private var cachedComputedHeight: CGFloat?
    private var cachedComputedHeightContainerWidth: CGFloat?

    override var layoutFragmentFrame: CGRect {
        let base = super.layoutFragmentFrame
        guard let height = aspectAdjustedHeight() else { return base }
        return CGRect(origin: base.origin, size: CGSize(width: base.width, height: height))
    }

    override var renderingSurfaceBounds: CGRect {
        let baseBounds = super.renderingSurfaceBounds
        let frameHeight = layoutFragmentFrame.height
        let targetWidth = max(baseBounds.width, expandedRenderingWidth())
        let targetHeight = max(baseBounds.height, frameHeight)
        return CGRect(x: 0, y: baseBounds.minY, width: targetWidth, height: targetHeight)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        #if os(macOS)
        drawMacImagePreview(at: point, in: context)
        #endif
    }

    #if os(macOS)
    private func drawMacImagePreview(at point: CGPoint, in context: CGContext) {
        guard let paragraph = textElement as? MarkdownParagraph,
              case .imageLink(let imageLink) = paragraph.blockKind else {
            return
        }

        let previewRect = ImageFragmentGeometry.imageRect(
            fragmentFrame: layoutFragmentFrame,
            point: point,
            availableContentWidth: availableImageContentWidth()
        )
        guard previewRect.width > 0,
              previewRect.height > 0,
              previewRect.origin.x.isFinite,
              previewRect.origin.y.isFinite,
              previewRect.size.width.isFinite,
              previewRect.size.height.isFinite else {
            return
        }

        context.saveGState()
        let backgroundPath = CGPath(
            roundedRect: previewRect,
            cornerWidth: MarkdownVisualSpec.imagePreviewCornerRadius,
            cornerHeight: MarkdownVisualSpec.imagePreviewCornerRadius,
            transform: nil
        )
        context.addPath(backgroundPath)
        context.setFillColor(AppTheme.nsCodeBackground.cgColor)
        context.fillPath()
        context.restoreGState()

        guard let url = imageLink.url else { return }

        let maxPixel = ceil(max(previewRect.width, previewRect.height) * 2)
        guard let image = MarkdownImageLoader.cachedDisplayImage(for: url, maxPixelSize: maxPixel) else {
            return
        }

        let imageRect = ImageFragmentGeometry.aspectFitRect(
            imageSize: image.size,
            in: previewRect
        ).integral
        guard imageRect.width > 0, imageRect.height > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        image.draw(
            in: imageRect,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()
    }
    #endif

    private func aspectAdjustedHeight() -> CGFloat? {
        let containerWidth = availableImageContentWidth() ?? 0
        if let cached = cachedComputedHeight,
           let cachedWidth = cachedComputedHeightContainerWidth,
           abs(cachedWidth - containerWidth) < 0.5 {
            return cached
        }

        let computed = computeAspectAdjustedHeight(containerWidth: containerWidth)
        cachedComputedHeight = computed
        cachedComputedHeightContainerWidth = containerWidth
        return computed
    }

    private func computeAspectAdjustedHeight(containerWidth: CGFloat) -> CGFloat? {
        guard containerWidth > 0,
              let paragraph = textElement as? MarkdownParagraph,
              case .imageLink(let imageLink) = paragraph.blockKind,
              let url = imageLink.url,
              let imageSize = MarkdownImageDimensionCache.cachedSize(for: url)
        else { return nil }

        return ImageFragmentGeometry.aspectAdjustedFragmentHeight(
            imageSize: imageSize,
            containerWidth: containerWidth
        )
    }

    private func expandedRenderingWidth() -> CGFloat {
        let frame = layoutFragmentFrame
        if let contentWidth = availableImageContentWidth() {
            return max(frame.width, frame.minX + contentWidth)
        }

        let usageWidth = textLayoutManager?.usageBoundsForTextContainer.width ?? 0
        if usageWidth.isFinite && usageWidth > 0 {
            return max(frame.width, frame.minX + usageWidth)
        }

        return frame.width
    }

    private func availableImageContentWidth() -> CGFloat? {
        let containerWidth = textLayoutManager?.textContainer?.size.width ?? 0
        if containerWidth.isFinite && containerWidth > 0 {
            return containerWidth
        }

        let usageWidth = textLayoutManager?.usageBoundsForTextContainer.width ?? 0
        if usageWidth.isFinite && usageWidth > 0 {
            return usageWidth
        }

        return nil
    }
}

// MARK: - MarkdownImageDimensionCache

enum MarkdownImageDimensionCache {
    private static let cache = NSCache<NSURL, NSValue>()

    static func cachedSize(for url: URL) -> CGSize? {
        guard let value = cache.object(forKey: url as NSURL) else { return nil }
        #if os(iOS)
        return value.cgSizeValue
        #elseif os(macOS)
        return value.sizeValue
        #endif
    }

    static func setSize(_ size: CGSize, for url: URL) {
        guard size.width > 0, size.height > 0 else { return }
        #if os(iOS)
        cache.setObject(NSValue(cgSize: size), forKey: url as NSURL)
        #elseif os(macOS)
        cache.setObject(NSValue(size: size), forKey: url as NSURL)
        #endif
    }

    static func removeSize(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}

// MARK: - MarkdownImageLoader

fileprivate enum MarkdownImageLoader {
    private static let cache = NSCache<NSURL, PlatformImage>()
    private static let displayCache = NSCache<NSString, PlatformImage>()
    private static let displayBucketSize: CGFloat = 64

    static func cachedImage(for url: URL) -> PlatformImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Returns a downsampled variant suitable for drawing at the given pixel size.
    /// Multiple call sites with similar sizes hit the same cache bucket.
    static func cachedDisplayImage(for url: URL, maxPixelSize: CGFloat) -> PlatformImage? {
        guard let source = cachedImage(for: url) else { return nil }
        let bucket = displayBucket(for: maxPixelSize)
        let key = displayCacheKey(url: url, bucket: bucket)
        if let cached = displayCache.object(forKey: key) {
            return cached
        }
        let downsampled = downsample(source, maxPixelSize: bucket)
        displayCache.setObject(downsampled, forKey: key)
        return downsampled
    }

    private static func store(image: PlatformImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
        MarkdownImageDimensionCache.setSize(image.size, for: url)
    }

    private static func displayBucket(for maxPixelSize: CGFloat) -> CGFloat {
        let clamped = max(displayBucketSize, maxPixelSize)
        return ceil(clamped / displayBucketSize) * displayBucketSize
    }

    private static func displayCacheKey(url: URL, bucket: CGFloat) -> NSString {
        "\(url.absoluteString)|\(Int(bucket))" as NSString
    }

    private static func downsample(_ image: PlatformImage, maxPixelSize: CGFloat) -> PlatformImage {
        guard maxPixelSize > 0 else { return image }
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return image }

        #if os(iOS)
        let sourcePixelMax = max(sourceSize.width, sourceSize.height) * image.scale
        if sourcePixelMax <= maxPixelSize { return image }

        let renderScale = image.scale > 0 ? image.scale : UIScreen.main.scale
        let pointMax = maxPixelSize / renderScale
        let scale = pointMax / max(sourceSize.width, sourceSize.height)
        let targetPointSize = CGSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, sourceSize.height * scale)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = renderScale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetPointSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetPointSize))
        }
        #elseif os(macOS)
        let sourcePixelMax = max(sourceSize.width, sourceSize.height)
        if sourcePixelMax <= maxPixelSize { return image }

        let scale = maxPixelSize / max(sourceSize.width, sourceSize.height)
        let targetSize = CGSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, sourceSize.height * scale)
        )

        let scaled = NSImage(size: targetSize)
        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .default
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        scaled.unlockFocus()
        return scaled
        #endif
    }

    static func load(url: URL, completion: @escaping (PlatformImage?) -> Void) {
        if let cached = cachedImage(for: url) {
            MarkdownImageDimensionCache.setSize(cached.size, for: url)
            completion(cached)
            return
        }

        if url.isFileURL {
            if let data = CoordinatedFileManager.readData(from: url),
               let image = PlatformImage(data: data) {
                store(image: image, for: url)
                completion(image)
                return
            }

            if !CoordinatedFileManager.isDownloaded(at: url) {
                CoordinatedFileManager.startDownloading(at: url)
            }
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap { PlatformImage(data: $0) }
            if let image {
                store(image: image, for: url)
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
    var revealedDividerRanges: [NSRange] = []
    var collapsedXMLTagRanges: [NSRange] = []
    var frontmatterRange: NSRange?
    var frontmatterDocument: EditableFrontmatterDocument?
    var vaultRootURL: URL?
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
        } else if MarkdownFrontmatter.contains(position: range.location, inRange: frontmatterRange) {
            kind = .frontmatter
        } else {
            kind = MarkdownBlockKind.detect(from: text, vaultRootURL: vaultRootURL)
        }

        // Style the visible text
        let styled = MarkdownParagraphStyler.style(
            text: text,
            kind: kind,
            paragraphLocation: range.location,
            revealedHyperlinkRanges: revealedHyperlinkRanges,
            revealedDividerRanges: revealedDividerRanges
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
    private var lastPublishedTextBeforeApplying: String?

    init(text: Binding<String>, onTextChange: ((String) -> Void)?, autoFocus: Bool) {
        _text = text
        self.onTextChange = onTextChange
        self.autoFocus = autoFocus
        self.lastPublishedText = text.wrappedValue
    }

    func publishEditorText(_ newText: String, updateBinding: Bool = false) {
        guard !isApplyingEditorText else { return }
        guard newText != lastPublishedText else { return }
        DebugTrace.record("editor publish \(DebugTrace.textSummary(newText))")
        lastPublishedText = newText
        if updateBinding {
            isUpdatingText = true
            text = newText
            isUpdatingText = false
        }
        onTextChange?(newText)
    }

    func beginApplyingEditorText(_ text: String) {
        isApplyingEditorText = true
        lastPublishedTextBeforeApplying = lastPublishedText
        lastPublishedText = text
    }

    func finishApplyingEditorText() {
        isApplyingEditorText = false
        lastPublishedTextBeforeApplying = nil
    }

    func commitAppliedEditorText(_ newText: String) {
        isApplyingEditorText = false
        let previousPublishedText = lastPublishedTextBeforeApplying ?? lastPublishedText
        lastPublishedTextBeforeApplying = nil
        guard newText != previousPublishedText else {
            lastPublishedText = newText
            return
        }

        DebugTrace.record("editor commit applied \(DebugTrace.textSummary(newText))")
        lastPublishedText = newText
        onTextChange?(newText)
    }

    func typingAttributes(for documentText: String, selectionLocation: Int) -> [NSAttributedString.Key: Any] {
        MarkdownTypingAttributes.attributes(for: documentText, selectionLocation: selectionLocation)
    }
}

enum HyperlinkSelectionRanges {
    static func fullRangesOnSelectedLines(in text: String, selection: NSRange) -> [NSRange] {
        let nsText = text as NSString
        return fullRangesOnSelectedLines(in: nsText, selection: selection)
    }

    static func fullRangesOnSelectedLines(in nsText: NSString, selection: NSRange) -> [NSRange] {
        guard nsText.length > 0, selection.location != NSNotFound else { return [] }

        let safeLocation = max(0, min(selection.location, nsText.length))
        let safeLength = max(0, min(selection.length, nsText.length - safeLocation))
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: safeLength))
        let lineText = nsText.substring(with: lineRange)

        return HyperlinkMarkdown.matches(in: lineText).map { match in
            NSRange(
                location: lineRange.location + match.fullRange.location,
                length: match.fullRange.length
            )
        }
    }
}

enum DividerMarkdown {
    static func isDividerLine(_ text: String) -> Bool {
        let indentCount = text.prefix(while: { $0 == " " }).count
        return String(text.dropFirst(indentCount)) == "---"
    }

    static func rangesOnSelectedLines(in text: String, selection: NSRange) -> [NSRange] {
        let nsText = text as NSString
        return rangesOnSelectedLines(in: nsText, selection: selection)
    }

    static func rangesOnSelectedLines(in nsText: NSString, selection: NSRange) -> [NSRange] {
        guard nsText.length > 0, selection.location != NSNotFound else { return [] }

        let safeLocation = max(0, min(selection.location, nsText.length))
        let safeLength = max(0, min(selection.length, nsText.length - safeLocation))
        let selectedLineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: safeLength))
        let frontmatterRange = MarkdownFrontmatter.range(in: nsText)
        var ranges: [NSRange] = []
        var location = selectedLineRange.location
        let selectedLineEnd = NSMaxRange(selectedLineRange)

        while location < selectedLineEnd, location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let visibleLineRange = MarkdownLineRanges.visibleLineRange(from: lineRange, in: nsText)
            let lineText = nsText.substring(with: visibleLineRange)
            if isDividerLine(lineText),
               !MarkdownFrontmatter.contains(position: visibleLineRange.location, inRange: frontmatterRange) {
                ranges.append(visibleLineRange)
            }

            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return ranges
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

private enum FrontmatterEditingTarget: Equatable {
    case existingValue(key: String)
    case newField
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

private final class HyperlinkInsertionSheetViewController: UIViewController, UITextFieldDelegate {
    var onCancel: (() -> Void)?
    var onInsert: ((String) -> Void)?

    private let draft: HyperlinkInsertionDraft
    private let destinationField = UITextField()
    private var didComplete = false

    init(draft: HyperlinkInsertionDraft) {
        self.draft = draft
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppTheme.uiBackground
        navigationItem.title = HyperlinkInsertionStrings.title
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: HyperlinkInsertionStrings.cancel,
            style: .plain,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: HyperlinkInsertionStrings.insert,
            style: .done,
            target: self,
            action: #selector(insert)
        )

        let labelTitle = UILabel()
        labelTitle.text = "Label"
        labelTitle.font = UIFont.preferredFont(forTextStyle: .caption1)
        labelTitle.textColor = AppTheme.uiMutedText

        let labelValue = UILabel()
        labelValue.text = draft.label
        labelValue.font = UIFont.preferredFont(forTextStyle: .body)
        labelValue.textColor = AppTheme.uiPrimaryText
        labelValue.numberOfLines = 2

        destinationField.placeholder = HyperlinkInsertionStrings.destinationPlaceholder
        destinationField.borderStyle = .roundedRect
        destinationField.textContentType = .URL
        destinationField.keyboardType = .URL
        destinationField.autocapitalizationType = .none
        destinationField.autocorrectionType = .no
        destinationField.returnKeyType = .done
        destinationField.clearButtonMode = .whileEditing
        destinationField.delegate = self
        destinationField.accessibilityIdentifier = "hyperlink_destination_field"

        let stackView = UIStackView(arrangedSubviews: [labelTitle, labelValue, destinationField])
        stackView.axis = .vertical
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])

        preferredContentSize = CGSize(width: 420, height: 220)
        destinationField.addTarget(self, action: #selector(destinationChanged), for: .editingChanged)
        updateInsertButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        destinationField.becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !didComplete,
              isBeingDismissed || navigationController?.isBeingDismissed == true else {
            return
        }
        onCancel?()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        insert()
        return true
    }

    @objc
    private func destinationChanged() {
        updateInsertButton()
    }

    private func updateInsertButton() {
        navigationItem.rightBarButtonItem?.isEnabled = HyperlinkMarkdown.target(from: destinationField.text ?? "") != nil
    }

    @objc
    private func cancel() {
        didComplete = true
        onCancel?()
        dismiss(animated: true)
    }

    @objc
    private func insert() {
        let destination = destinationField.text ?? ""
        guard HyperlinkMarkdown.target(from: destination) != nil else { return }
        didComplete = true
        onInsert?(destination)
        dismiss(animated: true)
    }
}

private final class PaddedTextField: UITextField {
    var insets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        super.textRect(forBounds: bounds.inset(by: insets))
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        super.editingRect(forBounds: bounds.inset(by: insets))
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        super.placeholderRect(forBounds: bounds.inset(by: insets))
    }
}

private final class FrontmatterBlockView: UIView {
    var document: EditableFrontmatterDocument?
    var isExpanded = true
    var editingTarget: FrontmatterEditingTarget?

    func configure(
        document: EditableFrontmatterDocument,
        isExpanded: Bool,
        editingTarget: FrontmatterEditingTarget?
    ) {
        self.document = document
        self.isExpanded = isExpanded
        self.editingTarget = editingTarget
        setNeedsDisplay()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        isOpaque = false
        layer.backgroundColor = FrontmatterBlockLayout.uiSurfaceColor.cgColor
        layer.cornerRadius = FrontmatterBlockLayout.cornerRadius
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let document else {
            return
        }

        let blockRect = bounds.integral
        let path = UIBezierPath(
            roundedRect: blockRect,
            cornerRadius: FrontmatterBlockLayout.cornerRadius
        )
        FrontmatterBlockLayout.uiSurfaceColor.setFill()
        path.fill()
        AppTheme.uiSeparator.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1
        path.stroke()

        drawChevron(in: blockRect, context: context)
        drawText("Metadata", in: titleRect(in: blockRect), font: .systemFont(ofSize: 15, weight: .semibold), color: AppTheme.uiPrimaryText)
        drawText(
            "\(document.fields.count)",
            in: countRect(in: blockRect),
            font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            color: AppTheme.uiMutedText,
            alignment: .right
        )

        guard isExpanded else { return }
        for index in 0..<FrontmatterBlockLayout.rowCount(for: document) {
            let rowRect = FrontmatterBlockLayout.rowRect(at: index, in: blockRect)
            let keyRect = FrontmatterBlockLayout.keyRect(for: rowRect, blockWidth: blockRect.width)
            let isExistingField = index < document.fields.count
            let isURLField = isExistingField && document.fields[index].url != nil
            let valueRect = FrontmatterBlockLayout.valueRect(
                for: rowRect,
                blockWidth: blockRect.width,
                hasEditControl: isURLField
            )

            context.move(to: CGPoint(x: rowRect.minX, y: rowRect.minY))
            context.addLine(to: CGPoint(x: blockRect.maxX - FrontmatterBlockLayout.horizontalPadding, y: rowRect.minY))
            context.setStrokeColor(AppTheme.uiSeparator.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(1)
            context.strokePath()

            if isExistingField {
                let field = document.fields[index]
                let isEditingThisRow = editingTarget == .existingValue(key: field.key)
                drawText(field.key, in: keyRect, font: .monospacedSystemFont(ofSize: 12, weight: .regular), color: AppTheme.uiMutedText)
                if !isEditingThisRow {
                    drawText(field.displayValue, in: valueRect, font: .monospacedSystemFont(ofSize: 13, weight: .regular), color: field.url == nil ? AppTheme.uiPrimaryText : .systemBlue)
                }
                if isURLField {
                    let editRect = FrontmatterBlockLayout.editRect(for: rowRect)
                    drawPencilIcon(in: editRect, context: context, color: AppTheme.uiSecondaryText)
                }
                let deleteRect = FrontmatterBlockLayout.deleteRect(for: rowRect)
                drawCrossIcon(in: deleteRect, context: context, color: AppTheme.uiSecondaryText)
            } else {
                let isEditingNewRow = editingTarget == .newField
                let placeholderColor = AppTheme.uiMutedText.withAlphaComponent(0.7)
                if !isEditingNewRow {
                    drawSeparatedPlaceholder(
                        keyRect: keyRect,
                        valueRect: valueRect,
                        placeholderColor: placeholderColor,
                        context: context
                    )
                }
                let addRect = FrontmatterBlockLayout.deleteRect(for: rowRect)
                drawPlusIcon(in: addRect, context: context, color: AppTheme.uiSecondaryText)
            }
        }
    }

    private func drawSeparatedPlaceholder(
        keyRect: CGRect,
        valueRect: CGRect,
        placeholderColor: UIColor,
        context: CGContext
    ) {
        drawText("key", in: keyRect, font: .monospacedSystemFont(ofSize: 12, weight: .regular), color: placeholderColor)
        drawText("value", in: valueRect, font: .monospacedSystemFont(ofSize: 13, weight: .regular), color: placeholderColor)
    }

    private func drawCrossIcon(in rect: CGRect, context: CGContext, color: UIColor) {
        let inset = rect.width * 0.28
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.move(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        color.setStroke()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawPlusIcon(in rect: CGRect, context: CGContext, color: UIColor) {
        let inset = rect.width * 0.26
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - inset))
        color.setStroke()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawPencilIcon(in rect: CGRect, context: CGContext, color: UIColor) {
        let inset = rect.width * 0.24
        let body = UIBezierPath()
        // Slanted line representing pencil shaft.
        body.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        body.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        // Underline indicating edit (small horizontal line below).
        body.move(to: CGPoint(x: rect.minX + inset * 0.8, y: rect.maxY - inset * 0.5))
        body.addLine(to: CGPoint(x: rect.maxX - inset * 0.8, y: rect.maxY - inset * 0.5))
        color.setStroke()
        body.lineWidth = 1.4
        body.lineCapStyle = .round
        body.stroke()
    }

    private func titleRect(in rect: CGRect) -> CGRect {
        let leading = rect.minX
            + FrontmatterBlockLayout.horizontalPadding
            + FrontmatterBlockLayout.chevronWidth
            + FrontmatterBlockLayout.iconTextGap
        let trailing = rect.maxX - FrontmatterBlockLayout.horizontalPadding - FrontmatterBlockLayout.countWidth
        return CGRect(x: leading, y: rect.minY, width: max(0, trailing - leading), height: FrontmatterBlockLayout.collapsedHeight)
    }

    private func countRect(in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.maxX - FrontmatterBlockLayout.horizontalPadding - FrontmatterBlockLayout.countWidth,
            y: rect.minY,
            width: FrontmatterBlockLayout.countWidth,
            height: FrontmatterBlockLayout.collapsedHeight
        )
    }

    private func drawChevron(in rect: CGRect, context: CGContext) {
        let centerX = rect.minX + FrontmatterBlockLayout.horizontalPadding + FrontmatterBlockLayout.chevronWidth / 2
        let centerY = rect.minY + FrontmatterBlockLayout.collapsedHeight / 2
        let size: CGFloat = 8
        let path = UIBezierPath()
        if isExpanded {
            path.move(to: CGPoint(x: centerX - size * 0.45, y: centerY - size * 0.2))
            path.addLine(to: CGPoint(x: centerX, y: centerY + size * 0.3))
            path.addLine(to: CGPoint(x: centerX + size * 0.45, y: centerY - size * 0.2))
        } else {
            path.move(to: CGPoint(x: centerX - size * 0.25, y: centerY - size * 0.45))
            path.addLine(to: CGPoint(x: centerX + size * 0.25, y: centerY))
            path.addLine(to: CGPoint(x: centerX - size * 0.25, y: centerY + size * 0.45))
        }
        AppTheme.uiPrimaryText.setStroke()
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle,
            ]
        )
        let textSize = attributed.size()
        let drawRect = CGRect(
            x: rect.minX,
            y: rect.midY - ceil(textSize.height) / 2,
            width: rect.width,
            height: ceil(textSize.height)
        )
        attributed.draw(in: drawRect)
    }
}

struct TextKit2EditorView: UIViewControllerRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?
    var vaultRootURL: URL?
    var onImportImageData: ((Data, String?) throws -> VaultImageAttachment)?
    var pageMentionProvider: ((String) -> [PageMentionDocument])?
    var onOpenDocumentLink: ((String) -> Void)?
    var isFindVisible: Bool = false
    var findQuery: String = ""
    var findNavigationRequest: EditorFindNavigationRequest?
    var onFindStatusChange: ((EditorFindStatus) -> Void)?
    var onCloseFind: (() -> Void)?
    var scrollRestorationID: String?
    var initialContentOffsetY: CGFloat?
    var onContentOffsetYChange: ((CGFloat) -> Void)?

    func makeCoordinator() -> TextKit2EditorCoordinator {
        TextKit2EditorCoordinator(text: $text, onTextChange: onTextChange, autoFocus: autoFocus)
    }

    func makeUIViewController(context: Context) -> TextKit2EditorViewController {
        let vc = TextKit2EditorViewController()
        vc.coordinator = context.coordinator
        vc.vaultRootURL = vaultRootURL
        vc.onImportImageData = onImportImageData
        vc.pageMentionProvider = pageMentionProvider
        vc.onOpenDocumentLink = onOpenDocumentLink
        vc.isFindVisible = isFindVisible
        vc.onCloseFind = onCloseFind
        vc.onContentOffsetYChange = onContentOffsetYChange
        vc.updateFind(
            query: findQuery,
            navigationRequest: findNavigationRequest,
            onStatusChange: onFindStatusChange
        )
        vc.loadText(text)
        vc.restoreInitialContentOffsetIfNeeded(id: scrollRestorationID, offsetY: initialContentOffsetY)
        return vc
    }

    func updateUIViewController(_ vc: TextKit2EditorViewController, context: Context) {
        vc.pageMentionProvider = pageMentionProvider
        vc.vaultRootURL = vaultRootURL
        vc.onImportImageData = onImportImageData
        vc.onOpenDocumentLink = onOpenDocumentLink
        vc.isFindVisible = isFindVisible
        vc.onCloseFind = onCloseFind
        vc.onContentOffsetYChange = onContentOffsetYChange
        vc.updateFind(
            query: findQuery,
            navigationRequest: findNavigationRequest,
            onStatusChange: onFindStatusChange
        )
        if !context.coordinator.isUpdatingText,
           text != context.coordinator.lastPublishedText {
            let currentText = vc.textView.text ?? ""
            if currentText != text,
               !vc.textView.isFirstResponder || currentText.isEmpty {
                vc.loadText(text, preservingVisiblePosition: true)
            }
        }
        vc.restoreInitialContentOffsetIfNeeded(id: scrollRestorationID, offsetY: initialContentOffsetY)
    }
}

final class TextKit2EditorViewController: UIViewController, UITextViewDelegate, UITextFieldDelegate, UIGestureRecognizerDelegate, PHPickerViewControllerDelegate {
    static let parentBottomToolbarClearance: CGFloat = 72
    static let keyboardToolbarReadingGap: CGFloat = 24

    var coordinator: TextKit2EditorCoordinator?
    var vaultRootURL: URL? {
        didSet {
            markdownDelegate.vaultRootURL = vaultRootURL
        }
    }
    var onImportImageData: ((Data, String?) throws -> VaultImageAttachment)?
    var pageMentionProvider: ((String) -> [PageMentionDocument])?
    var onOpenDocumentLink: ((String) -> Void)?
    var isFindVisible = false
    var onCloseFind: (() -> Void)?
    var onContentOffsetYChange: ((CGFloat) -> Void)?
    private(set) var textView: UITextView!
    private let minimumHorizontalTextInset: CGFloat = 16
    private let maximumTextWidth: CGFloat = 600
    private let verticalTextInset: CGFloat = 16
    private let markdownDelegate = MarkdownTextDelegate()
    private var todoMarkerButtons: [Int: TodoMarkerButton] = [:]
    private var pendingText: String?
    private var pendingTextPreservesVisiblePosition = false
    private var pageMentionSuggestionView: UIStackView?
    private var pageMentionSuggestionDocuments: [PageMentionDocument] = []
    private var selectedPageMentionSuggestionIndex = 0
    private var activePageMentionQuery: PageMentionQuery?
    private var pageMentionSheetViewController: PageMentionSheetViewController?
    private var hyperlinkInsertionSheetViewController: HyperlinkInsertionSheetViewController?
    private var pendingPageMentionTriggerLocation: Int?
    private var suppressedPageMentionLocation: Int?
    private var revealedHyperlinkRanges: [NSRange] = []
    private var revealedDividerRanges: [NSRange] = []
    private var hyperlinkRangesAtTapStart: [NSRange] = []
    private weak var hyperlinkTapRecognizer: UITapGestureRecognizer?
    private var isRestylingText = false
    private var isOverlayRefreshScheduled = false
    private var isImageLayoutInvalidationScheduled = false
    private var pendingEditorPublishTask: Task<Void, Never>?
    private var lastOverlayLayoutSize: CGSize = .zero
    private var keyboardObserverTokens: [NSObjectProtocol] = []
    private var appLifecycleObserverTokens: [NSObjectProtocol] = []
    private var keyboardFrameInScreen: CGRect?
    private var lifecycleContentOffset: CGPoint?
    private var currentScrollRestorationID: String?
    private var didRestoreInitialContentOffset = false
    private var loadingImageURLs: Set<URL> = []
    private var cachedRenderableBlocks: [MarkdownRenderableBlock] = []
    private var cachedRenderableBlocksText = ""
    private var cachedCollapsedXMLTagRanges: [NSRange] = []
    private var findQuery = ""
    private var findMatches: [NSRange] = []
    private var selectedFindMatchIndex: Int?
    private var lastFindNavigationRequestID: Int?
    private var onFindStatusChange: ((EditorFindStatus) -> Void)?
    private var lastPublishedFindStatus = EditorFindStatus()
    private var findBackgroundSnapshots: [EditorFindBackgroundSnapshot] = []
    private var findHighlightViews: [UIView] = []
    private var dividerLineViews: [Int: UIView] = [:]
    private var imageOverlayViews: [Int: UIImageView] = [:]
    private var isFrontmatterBlockExpanded = false
    private var frontmatterBlockView: FrontmatterBlockView?
    private var frontmatterHeaderButton: UIButton?
    private var frontmatterValueButtons: [Int: UIButton] = [:]
    private var frontmatterDeleteButtons: [Int: UIButton] = [:]
    private var frontmatterEditButtons: [Int: UIButton] = [:]
    private weak var frontmatterEditingKeyField: UITextField?
    private weak var frontmatterEditingField: UITextField?
    private var frontmatterEditingTarget: FrontmatterEditingTarget?

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
            markdownDelegate.vaultRootURL = vaultRootURL
            markdownDelegate.requestImageLoad = { [weak self] url in
                self?.requestImageLoad(for: url)
            }
        } else {
            logger.warning("TextKit 2 not available — falling back to unstyled editing")
        }

        textView.font = MarkdownTheme.bodyFont
        textView.textColor = MarkdownTheme.bodyColor
        textView.backgroundColor = AppTheme.uiBackground
        textView.textContainerInset = UIEdgeInsets(
            top: editorTopTextInset,
            left: minimumHorizontalTextInset,
            bottom: verticalTextInset,
            right: minimumHorizontalTextInset
        )
        textView.smartDashesType = .no
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
        installHyperlinkTapRecognizer()
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        if let pendingText {
            applyText(pendingText, preservingVisiblePosition: pendingTextPreservesVisiblePosition)
            self.pendingText = nil
            pendingTextPreservesVisiblePosition = false
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startKeyboardObservation()
        startAppLifecycleObservation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopKeyboardObservation()
        rememberCurrentContentOffset()
        stopAppLifecycleObservation()
    }

    deinit {
        pendingEditorPublishTask?.cancel()
        stopKeyboardObservation()
        stopAppLifecycleObservation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let didUpdateReadableWidthInsets = syncReadableWidthInsets()
        updateKeyboardAvoidanceInsets()
        refreshEditorOverlaysAfterLayoutChangeIfNeeded(force: didUpdateReadableWidthInsets)
        refreshFindHighlightOverlays()
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
                modifierFlags: [.command, .shift],
                action: #selector(toggleSelectedHyperlink),
                discoverabilityTitle: "Link"
            ),
            UIKeyCommand(
                input: "f",
                modifierFlags: [.command],
                action: #selector(showFind),
                discoverabilityTitle: "Search in Note"
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

        if isFindVisible {
            commands.append(UIKeyCommand(
                input: UIKeyCommand.inputEscape,
                modifierFlags: [],
                action: #selector(closeFind),
                discoverabilityTitle: "Close Search"
            ))
        }

        return commands
    }

    @objc
    private func showFind() {
        NoteEditorCommands.requestShowFind()
    }

    @objc
    private func closeFind() {
        onCloseFind?()
    }

    func loadText(_ markdown: String, preservingVisiblePosition: Bool = false) {
        guard isViewLoaded, textView != nil else {
            pendingText = markdown
            pendingTextPreservesVisiblePosition = preservingVisiblePosition
            return
        }
        applyText(markdown, preservingVisiblePosition: preservingVisiblePosition)
    }

    private func applyText(_ markdown: String, preservingVisiblePosition: Bool = false) {
        pendingEditorPublishTask?.cancel()
        pendingEditorPublishTask = nil
        let contentOffsetToRestore = preservingVisiblePosition ? textView.contentOffset : nil
        isFrontmatterBlockExpanded = false
        updateFrontmatterMetadata(for: markdown)
        _ = syncReadableWidthInsets()
        coordinator?.beginApplyingEditorText(markdown)
        textView.text = markdown
        coordinator?.finishApplyingEditorText()
        invalidateRenderableBlockCache()
        updateTypingAttributes(documentText: markdown as NSString)
        refreshFindMatches(in: markdown, preferredLocation: textView.selectedRange.location, scrollToSelection: false)
        if coordinator?.autoFocus == true {
            DispatchQueue.main.async { [weak self] in
                guard let tv = self?.textView else { return }
                tv.becomeFirstResponder()
                let end = tv.endOfDocument
                tv.selectedTextRange = tv.textRange(from: end, to: end)
                self?.refreshFindMatches(preferredLocation: tv.selectedRange.location, scrollToSelection: false)
                self?.scheduleEditorOverlayRefresh()
            }
        }
        scheduleEditorOverlayRefresh()
        updatePageMentionSuggestions(in: markdown as NSString)
        if let contentOffsetToRestore {
            restoreContentOffset(contentOffsetToRestore)
        }
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
            makeToolbarButton(
                systemName: "photo",
                accessibilityIdentifier: "insert_image_button",
                accessibilityLabel: "Insert Image",
                action: #selector(insertImageFromPhotoLibrary)
            ),
            makeToolbarButton(
                systemName: "keyboard.chevron.compact.down",
                accessibilityIdentifier: "hide_keyboard_button",
                accessibilityLabel: "Hide Keyboard",
                action: #selector(hideSoftwareKeyboard)
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
    private func hideSoftwareKeyboard() {
        textView.resignFirstResponder()
    }

    @objc
    private func insertImageFromPhotoLibrary() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        picker.view.accessibilityIdentifier = "image_picker"
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }

        let provider = result.itemProvider
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }) else {
            showImageImportError()
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, _ in
            DispatchQueue.main.async {
                guard let self, let data else {
                    self?.showImageImportError()
                    return
                }

                self.importAndInsertImage(
                    data: data,
                    suggestedFilename: self.suggestedFilename(
                        from: provider,
                        typeIdentifier: typeIdentifier
                    )
                )
            }
        }
    }

    private func suggestedFilename(from provider: NSItemProvider, typeIdentifier: String) -> String {
        let trimmedName = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = trimmedName.isEmpty ? "Image" : trimmedName
        guard URL(fileURLWithPath: base).pathExtension.isEmpty,
              let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension else {
            return base
        }
        return "\(base).\(fileExtension)"
    }

    private func importAndInsertImage(data: Data, suggestedFilename: String?) {
        guard let onImportImageData else { return }
        do {
            let attachment = try onImportImageData(data, suggestedFilename)
            insertImageMarkdown(attachment.markdown)
        } catch {
            showImageImportError()
        }
    }

    private func insertImageMarkdown(_ markdown: String) {
        let transform = MarkdownImageInsertion.transform(
            in: textView.text ?? "",
            selection: textView.selectedRange,
            markdown: markdown
        )
        applySelectionTransform(transform)
        textView.becomeFirstResponder()
    }

    private func showImageImportError() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "Image Not Added",
            message: "Noto could not import this image.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
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
        if let transform = BlockEditingCommands.toggledHyperlink(
            in: textView.text ?? "",
            selection: textView.selectedRange
        ) {
            applySelectionTransform(transform)
            return
        }

        guard let draft = BlockEditingCommands.hyperlinkInsertionDraft(
            in: textView.text ?? "",
            selection: textView.selectedRange
        ) else {
            return
        }

        presentHyperlinkInsertionSheet(for: draft)
    }

    private func presentHyperlinkInsertionSheet(for draft: HyperlinkInsertionDraft) {
        guard presentedViewController == nil,
              hyperlinkInsertionSheetViewController == nil else {
            return
        }

        let sheetViewController = HyperlinkInsertionSheetViewController(draft: draft)
        hyperlinkInsertionSheetViewController = sheetViewController
        sheetViewController.onCancel = { [weak self] in
            self?.hyperlinkInsertionSheetViewController = nil
            self?.textView.becomeFirstResponder()
        }
        sheetViewController.onInsert = { [weak self, draft] destination in
            guard let self else { return }
            self.hyperlinkInsertionSheetViewController = nil
            if let transform = BlockEditingCommands.insertedHyperlink(
                in: self.textView.text ?? "",
                draft: draft,
                rawDestination: destination
            ) {
                self.applySelectionTransform(transform)
            }
            self.textView.becomeFirstResponder()
        }

        let navigationController = UINavigationController(rootViewController: sheetViewController)
        if let sheetPresentationController = navigationController.sheetPresentationController {
            sheetPresentationController.detents = [.medium()]
            sheetPresentationController.prefersGrabberVisible = true
            sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(navigationController, animated: true)
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
        updateTypingAttributes(documentText: transform.text as NSString)
        coordinator?.commitAppliedEditorText(transform.text)
        scheduleEditorOverlayRefresh()
    }

    private func scheduleEditorTextPublish() {
        pendingEditorPublishTask?.cancel()
        pendingEditorPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            self.coordinator?.publishEditorText(self.textView.text ?? "")
            self.pendingEditorPublishTask = nil
        }
    }

    private func flushEditorTextToSession(updateBinding: Bool = false) {
        pendingEditorPublishTask?.cancel()
        pendingEditorPublishTask = nil
        coordinator?.publishEditorText(textView.text ?? "", updateBinding: updateBinding)
    }

    private func updatePageMentionSuggestions() {
        updatePageMentionSuggestions(in: textView.textStorage.mutableString)
    }

    private func updatePageMentionSuggestions(in documentText: NSString) {
        guard let pageMentionProvider,
              textView.isFirstResponder,
              let query = PageMentionMarkdown.activeQuery(
                  in: documentText,
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
            stackView.addArrangedSubview(makePageMentionSuggestionRowContainer(for: button))
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
        stackView.accessibilityIdentifier = "page_mention_suggestions"
        stackView.layer.cornerRadius = 10
        stackView.layer.cornerCurve = .continuous
        stackView.layer.borderColor = AppTheme.uiSeparator.cgColor
        stackView.layer.borderWidth = 1
        stackView.clipsToBounds = true
        pageMentionSuggestionView = stackView
        return stackView
    }

    private func makePageMentionSuggestionRowContainer(for button: UIButton) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
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
        for button in pageMentionSuggestionButtons(in: stackView) {
            button.backgroundColor = button.tag == selectedPageMentionSuggestionIndex
                ? AppTheme.uiSeparator.withAlphaComponent(0.75)
                : .clear
        }
    }

    private func pageMentionSuggestionButtons(in stackView: UIStackView) -> [UIButton] {
        stackView.arrangedSubviews.compactMap { arrangedSubview in
            if let button = arrangedSubview as? UIButton {
                return button
            }
            return arrangedSubview.subviews.compactMap { $0 as? UIButton }.first
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

    func updateFind(
        query: String,
        navigationRequest: EditorFindNavigationRequest?,
        onStatusChange: ((EditorFindStatus) -> Void)?
    ) {
        self.onFindStatusChange = onStatusChange

        let normalizedQuery = EditorFindMatcher.normalizedQuery(query)
        let didChangeQuery = normalizedQuery != findQuery
        if didChangeQuery {
            findQuery = normalizedQuery
            refreshFindMatches(
                preferredLocation: textView?.selectedRange.location ?? 0,
                scrollToSelection: !normalizedQuery.isEmpty
            )
        } else if isViewLoaded, textView != nil {
            publishFindStatusIfNeeded()
        }

        guard let navigationRequest,
              navigationRequest.id != lastFindNavigationRequestID else {
            return
        }

        lastFindNavigationRequestID = navigationRequest.id
        navigateFind(to: navigationRequest.direction)
    }

    private func refreshFindMatches(preferredLocation: Int, scrollToSelection: Bool) {
        refreshFindMatches(
            in: textView.text ?? "",
            preferredLocation: preferredLocation,
            scrollToSelection: scrollToSelection
        )
    }

    private func refreshFindMatches(in documentText: String, preferredLocation: Int, scrollToSelection: Bool) {
        guard isViewLoaded, textView != nil else {
            publishFindStatusIfNeeded()
            return
        }

        restoreFindHighlightBackgrounds()
        findMatches = EditorFindMatcher.ranges(in: documentText, query: findQuery)
        selectedFindMatchIndex = EditorFindMatcher.preferredIndex(
            for: findMatches,
            selectionLocation: preferredLocation
        )
        applyFindHighlights()
        publishFindStatusIfNeeded()

        if scrollToSelection {
            scrollToSelectedFindMatch()
        }
    }

    private func navigateFind(to direction: EditorFindNavigationDirection) {
        selectedFindMatchIndex = EditorFindMatcher.navigatedIndex(
            from: selectedFindMatchIndex,
            matchCount: findMatches.count,
            direction: direction
        )
        applyFindHighlights()
        publishFindStatusIfNeeded()
        scrollToSelectedFindMatch()
    }

    private func scrollToSelectedFindMatch() {
        guard let selectedFindMatchIndex,
              selectedFindMatchIndex < findMatches.count else {
            return
        }

        let range = findMatches[selectedFindMatchIndex]
        guard NSMaxRange(range) <= ((textView.text ?? "") as NSString).length else { return }
        textView.selectedRange = range
        textView.scrollRangeToVisible(range)
    }

    private func publishFindStatusIfNeeded() {
        let status = EditorFindStatus(
            matchCount: findMatches.count,
            selectedMatchIndex: selectedFindMatchIndex
        )
        guard status != lastPublishedFindStatus else { return }

        lastPublishedFindStatus = status
        onFindStatusChange?(status)
    }

    private func applyFindHighlights() {
        guard isViewLoaded, textView != nil else {
            return
        }
        let textStorage = textView.textStorage

        restoreFindHighlightBackgrounds()
        guard !findMatches.isEmpty else { return }

        textStorage.beginEditing()
        for (index, range) in findMatches.enumerated() {
            guard range.location >= 0,
                  range.length > 0,
                  NSMaxRange(range) <= textStorage.length else {
                continue
            }

            snapshotFindBackgrounds(in: range, textStorage: textStorage)
            let background = index == selectedFindMatchIndex
                ? EditorFindHighlightPalette.currentMatchBackground
                : EditorFindHighlightPalette.matchBackground
            textStorage.addAttribute(.backgroundColor, value: background, range: range)
        }
        textStorage.endEditing()
        textView.setNeedsDisplay()
        refreshFindHighlightOverlays()
    }

    private func restoreFindHighlightBackgrounds() {
        guard isViewLoaded,
              textView != nil,
              !findBackgroundSnapshots.isEmpty else {
            findBackgroundSnapshots = []
            return
        }
        let textStorage = textView.textStorage

        textStorage.beginEditing()
        for snapshot in findBackgroundSnapshots.reversed() where NSMaxRange(snapshot.range) <= textStorage.length {
            if let value = snapshot.value {
                textStorage.addAttribute(.backgroundColor, value: value, range: snapshot.range)
            } else {
                textStorage.removeAttribute(.backgroundColor, range: snapshot.range)
            }
        }
        textStorage.endEditing()
        findBackgroundSnapshots = []
        textView.setNeedsDisplay()
        clearFindHighlightOverlays()
    }

    private func snapshotFindBackgrounds(in range: NSRange, textStorage: NSTextStorage) {
        textStorage.enumerateAttribute(.backgroundColor, in: range, options: []) { value, subrange, _ in
            findBackgroundSnapshots.append(EditorFindBackgroundSnapshot(range: subrange, value: value))
        }
    }

    private func refreshFindHighlightOverlays() {
        guard isViewLoaded, textView != nil else { return }
        clearFindHighlightOverlays()
        guard !findMatches.isEmpty else { return }

        let textLength = ((textView.text ?? "") as NSString).length
        for (index, range) in findMatches.enumerated() {
            guard range.location >= 0,
                  range.length > 0,
                  NSMaxRange(range) <= textLength,
                  let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length) else {
                continue
            }

            let startRect = textView.caretRect(for: start)
            let endRect = textView.caretRect(for: end)
            guard isFiniteRect(startRect), isFiniteRect(endRect) else { continue }

            let height = max(12, min(startRect.height, 24))
            let width = max(4, endRect.minX - startRect.minX)
            let rect = CGRect(
                x: startRect.minX - 1,
                y: startRect.midY - height / 2,
                width: width + 2,
                height: height
            )

            let isActiveMatch = index == selectedFindMatchIndex
            let highlight = UIView(frame: rect)
            highlight.isUserInteractionEnabled = false
            highlight.layer.cornerRadius = 2
            highlight.layer.cornerCurve = .continuous
            highlight.backgroundColor = isActiveMatch
                ? EditorFindHighlightPalette.currentMatchBackground
                : EditorFindHighlightPalette.matchBackground
            textView.insertSubview(highlight, at: 0)
            findHighlightViews.append(highlight)
        }
    }

    private func clearFindHighlightOverlays() {
        findHighlightViews.forEach { $0.removeFromSuperview() }
        findHighlightViews = []
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
        let textStorageString = textView.textStorage.mutableString
        updateFrontmatterMetadata(for: textStorageString as String)
        _ = syncReadableWidthInsets()
        invalidateRenderableBlockCache()
        if !isRestylingText {
            updateRevealedMarkdownRangesForSelection(restyle: false)
            applyDividerRenderAttributesToTextStorage(in: dividerRefreshRangesForCurrentSelection())
        }
        scheduleEditorTextPublish()
        updateTypingAttributes(documentText: textStorageString)
        if keyboardFrameInScreen != nil {
            scrollSelectionAboveKeyboard()
        }
        scheduleEditorOverlayRefresh()
        updatePageMentionSuggestions(in: textStorageString)
        if !findQuery.isEmpty || !findMatches.isEmpty {
            refreshFindMatches(in: textStorageString as String, preferredLocation: textView.selectedRange.location, scrollToSelection: false)
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if !isRestylingText {
            updateRevealedMarkdownRangesForSelection(restyle: true)
        }
        updateTypingAttributes()
        updatePageMentionSuggestions()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        flushEditorTextToSession(updateBinding: true)
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

    private func setRevealedDividerRanges(_ ranges: [NSRange]) {
        revealedDividerRanges = ranges
        markdownDelegate.revealedDividerRanges = ranges
    }

    private func updateRevealedMarkdownRangesForSelection(restyle: Bool) {
        let text = textView.textStorage.mutableString
        let hyperlinkRanges = hyperlinkRangesOnSelectedLines(in: text, selection: textView.selectedRange)
        let dividerRanges = dividerRangesOnSelectedLines(in: text, selection: textView.selectedRange)
        let previousHyperlinkRanges = revealedHyperlinkRanges
        let previousDividerRanges = revealedDividerRanges
        let changed = !nsRangesEqual(hyperlinkRanges, revealedHyperlinkRanges)
            || !nsRangesEqual(dividerRanges, revealedDividerRanges)
        guard changed else { return }

        setRevealedHyperlinkRanges(hyperlinkRanges)
        setRevealedDividerRanges(dividerRanges)
        if restyle {
            restyleTextPreservingSelection(
                affectedHyperlinkRanges: previousHyperlinkRanges + hyperlinkRanges,
                affectedDividerRanges: previousDividerRanges + dividerRanges
            )
        } else {
            applyDividerRenderAttributesToTextStorage(in: previousDividerRanges + dividerRanges)
            scheduleEditorOverlayRefresh()
        }
    }

    private func hyperlinkRangesOnSelectedLines(in text: NSString, selection: NSRange) -> [NSRange] {
        HyperlinkSelectionRanges.fullRangesOnSelectedLines(in: text, selection: selection)
    }

    private func dividerRangesOnSelectedLines(in text: NSString, selection: NSRange) -> [NSRange] {
        DividerMarkdown.rangesOnSelectedLines(in: text, selection: selection)
    }

    private func nsRangesEqual(_ lhs: [NSRange], _ rhs: [NSRange]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            guard NSEqualRanges(left, right) else { return false }
        }
        return true
    }

    private func restyleTextPreservingSelection(
        affectedHyperlinkRanges: [NSRange]? = nil,
        affectedDividerRanges: [NSRange]? = nil
    ) {
        applyHyperlinkRenderAttributesToTextStorage(in: affectedHyperlinkRanges)
        applyDividerRenderAttributesToTextStorage(in: affectedDividerRanges)
        applyFindHighlights()
        updateTypingAttributes()
        scheduleEditorOverlayRefresh()
    }

    private func applyHyperlinkRenderAttributesToTextStorage(in affectedRanges: [NSRange]? = nil) {
        let textStorage = textView.textStorage
        let matches: [HyperlinkMarkdown.Match]
        if let affectedRanges {
            matches = hyperlinkMatches(in: affectedRanges)
        } else {
            matches = HyperlinkMarkdown.matches(in: textView.text ?? "")
        }

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

    private func hyperlinkMatches(in affectedRanges: [NSRange]) -> [HyperlinkMarkdown.Match] {
        let nsText = textView.textStorage.mutableString
        guard nsText.length > 0 else { return [] }

        var matches: [HyperlinkMarkdown.Match] = []
        var seenLocations: Set<Int> = []
        for range in affectedRanges {
            guard range.location != NSNotFound else { continue }
            let safeLocation = max(0, min(range.location, nsText.length))
            let safeLength = max(0, min(range.length, nsText.length - safeLocation))
            let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: safeLength))
            let lineText = nsText.substring(with: lineRange)
            for match in HyperlinkMarkdown.matches(in: lineText) {
                let documentMatch = HyperlinkMarkdown.Match(
                    fullRange: NSRange(location: lineRange.location + match.fullRange.location, length: match.fullRange.length),
                    titleRange: NSRange(location: lineRange.location + match.titleRange.location, length: match.titleRange.length),
                    urlRange: NSRange(location: lineRange.location + match.urlRange.location, length: match.urlRange.length),
                    title: match.title,
                    urlText: match.urlText
                )
                guard seenLocations.insert(documentMatch.fullRange.location).inserted else { continue }
                matches.append(documentMatch)
            }
        }
        return matches
    }

    private func hyperlinkSyntaxRanges(for match: HyperlinkMarkdown.Match) -> [NSRange] {
        [
            NSRange(location: match.fullRange.location, length: 1),
            NSRange(location: NSMaxRange(match.titleRange), length: 2),
            match.urlRange,
            NSRange(location: NSMaxRange(match.urlRange), length: 1),
        ]
    }

    private func applyDividerRenderAttributesToTextStorage(in affectedRanges: [NSRange]? = nil) {
        let textStorage = textView.textStorage
        let blocks: [MarkdownRenderableBlock]
        if let affectedRanges {
            blocks = renderableBlocks(intersecting: affectedRanges)
        } else {
            blocks = currentRenderableBlocks()
        }
        var styledLocations: Set<Int> = []

        for block in blocks where block.kind == .divider && !block.isCollapsedXMLTagContent {
            guard styledLocations.insert(block.paragraphRange.location).inserted else {
                continue
            }
            guard block.visibleLineRange.length > 0,
                  NSMaxRange(block.visibleLineRange) <= textStorage.length else {
                continue
            }

            let isRevealed = revealedDividerRanges.contains { NSEqualRanges($0, block.visibleLineRange) }
            textStorage.addAttributes([
                .font: MarkdownTheme.bodyFont,
                .foregroundColor: isRevealed ? MarkdownTheme.bodyColor : UIColor.clear,
                .paragraphStyle: MarkdownParagraphStyler.paragraphStyle(
                    for: isRevealed ? .paragraph : .divider,
                    text: block.lineText
                ),
            ], range: block.visibleLineRange)
        }
    }

    private func dividerRefreshRangesForCurrentSelection() -> [NSRange] {
        var ranges = revealedDividerRanges
        if let selectedLineRange = selectedLineRange() {
            ranges.append(selectedLineRange)
        }
        return ranges
    }

    private func installHyperlinkTapRecognizer() {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleHyperlinkTap(_:)))
        recognizer.numberOfTapsRequired = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        textView.addGestureRecognizer(recognizer)
        hyperlinkTapRecognizer = recognizer
    }

    @objc
    private func handleHyperlinkTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let textView = recognizer.view as? UITextView else {
            return
        }

        let location = recognizer.location(in: textView)
        collapseFrontmatterIfTapOutside(point: location)

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

    private func collapseFrontmatterIfTapOutside(point: CGPoint) {
        guard isFrontmatterBlockExpanded,
              let layout = frontmatterControlLayout(),
              !layout.blockRect.contains(point) else {
            return
        }
        finishFrontmatterEditing(commit: true)
        isFrontmatterBlockExpanded = false
        invalidateFrontmatterLayout()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === hyperlinkTapRecognizer {
            hyperlinkRangesAtTapStart = revealedHyperlinkRanges
        }
        return true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        flushEditorTextToSession(updateBinding: true)
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

    private func startAppLifecycleObservation() {
        guard appLifecycleObserverTokens.isEmpty else { return }

        let center = NotificationCenter.default
        appLifecycleObserverTokens.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushEditorTextToSession()
            self?.rememberCurrentContentOffset()
        })
        appLifecycleObserverTokens.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let lifecycleContentOffset else { return }
            restoreContentOffset(lifecycleContentOffset)
        })
    }

    private func stopAppLifecycleObservation() {
        let center = NotificationCenter.default
        appLifecycleObserverTokens.forEach { center.removeObserver($0) }
        appLifecycleObserverTokens.removeAll()
    }

    private func rememberCurrentContentOffset() {
        guard isViewLoaded, textView != nil else { return }
        lifecycleContentOffset = textView.contentOffset
        onContentOffsetYChange?(textView.contentOffset.y)
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
        let bottomInset = Self.editorBottomInset(forKeyboardOverlap: overlap)

        textView.contentInset.bottom = bottomInset
        textView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    static func editorBottomInset(forKeyboardOverlap overlap: CGFloat) -> CGFloat {
        guard overlap > 0 else { return parentBottomToolbarClearance }
        return overlap + keyboardToolbarReadingGap
    }

    private func updateFrontmatterMetadata(for markdown: String) {
        markdownDelegate.frontmatterRange = MarkdownFrontmatter.range(in: markdown)
        markdownDelegate.frontmatterDocument = EditableFrontmatterDocument(markdown: markdown)
    }

    private var frontmatterReservedHeight: CGFloat {
        markdownDelegate.frontmatterDocument == nil ? 0 : FrontmatterBlockLayout.reservedTopInset
    }

    private var editorTopTextInset: CGFloat {
        verticalTextInset + frontmatterReservedHeight
    }

    private func syncReadableWidthInsets() -> Bool {
        guard isViewLoaded, textView != nil else { return false }

        let constrainsToReadableWidth = traitCollection.userInterfaceIdiom == .pad
        let availableWidth = textView.bounds.width
        let horizontalTextInset = ReadableTextColumnLayout.textHorizontalInset(
            for: availableWidth,
            maximumTextWidth: maximumTextWidth,
            minimumHorizontalInset: minimumHorizontalTextInset,
            constrainsToReadableWidth: constrainsToReadableWidth
        )
        let targetTextContainerInset = UIEdgeInsets(
            top: editorTopTextInset,
            left: horizontalTextInset,
            bottom: verticalTextInset,
            right: horizontalTextInset
        )

        var didUpdate = false
        if textView.textContainerInset != targetTextContainerInset {
            textView.textContainerInset = targetTextContainerInset
            didUpdate = true
        }

        return didUpdate
    }

    private func scrollSelectionAboveKeyboard() {
        guard textView.isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.textView != nil else { return }
            self.scrollSelectionToKeyboardReadingBoundary()
        }
    }

    private func scrollSelectionToKeyboardReadingBoundary() {
        guard keyboardFrameInScreen != nil else {
            textView.scrollRangeToVisible(textView.selectedRange)
            return
        }

        textView.layoutIfNeeded()
        let selectedRange = textView.selectedRange
        let documentLength = (textView.text as NSString).length
        let caretLocation = max(0, min(selectedRange.location, documentLength))
        guard let caretPosition = textView.position(from: textView.beginningOfDocument, offset: caretLocation) else {
            textView.scrollRangeToVisible(selectedRange)
            return
        }

        let caretRect = textView.caretRect(for: caretPosition)
        guard isFiniteRect(caretRect) else {
            textView.scrollRangeToVisible(selectedRange)
            return
        }

        let keyboardReadingBoundary = textView.bounds.maxY - textView.adjustedContentInset.bottom
        let isAtDocumentEnd = NSMaxRange(selectedRange) >= documentLength
        let distanceFromBoundary = caretRect.maxY - keyboardReadingBoundary

        guard distanceFromBoundary > 0 || (isAtDocumentEnd && distanceFromBoundary < -1) else { return }

        let targetOffset = CGPoint(
            x: textView.contentOffset.x,
            y: textView.contentOffset.y + distanceFromBoundary
        )
        textView.setContentOffset(clampedContentOffset(targetOffset), animated: false)
    }

    func restoreInitialContentOffsetIfNeeded(id: String?, offsetY: CGFloat?) {
        if id != currentScrollRestorationID {
            currentScrollRestorationID = id
            didRestoreInitialContentOffset = false
        }

        guard !didRestoreInitialContentOffset,
              let offsetY,
              offsetY.isFinite else {
            return
        }

        didRestoreInitialContentOffset = true
        restoreContentOffset(CGPoint(x: 0, y: offsetY))
    }

    private func restoreContentOffset(_ offset: CGPoint) {
        guard isViewLoaded, textView != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.textView != nil else { return }
            self.textView.layoutIfNeeded()
            let clampedOffset = self.clampedContentOffset(offset)
            self.textView.setContentOffset(clampedOffset, animated: false)
            self.lifecycleContentOffset = clampedOffset
        }
    }

    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        let inset = textView.adjustedContentInset
        let minX = -inset.left
        let minY = -inset.top
        let maxX = max(minX, textView.contentSize.width - textView.bounds.width + inset.right)
        let maxY = max(minY, textView.contentSize.height - textView.bounds.height + inset.bottom)

        return CGPoint(
            x: min(max(offset.x, minX), maxX),
            y: min(max(offset.y, minY), maxY)
        )
    }

    /// Sets typing attributes to match the current paragraph's block kind,
    /// so newly typed characters inherit the correct font immediately
    /// (before the content-storage delegate re-styles the paragraph).
    private func updateTypingAttributes(documentText: NSString? = nil) {
        let documentText = documentText ?? textView.textStorage.mutableString
        textView.typingAttributes = MarkdownTypingAttributes.attributes(
            in: documentText,
            selectionLocation: textView.selectedRange.location
        )
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === textView {
            onContentOffsetYChange?(scrollView.contentOffset.y)
        }
        let blocks = visibleRenderableBlocks()
        refreshFrontmatterControls()
        refreshTodoMarkerButtons(in: blocks)
        refreshImageOverlayViews(in: blocks)
        refreshFindHighlightOverlays()
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
        let blocks = visibleRenderableBlocks()
        refreshFrontmatterControls()
        refreshTodoMarkerButtons(in: blocks)
        refreshDividerLineViews(in: blocks)
        refreshImageOverlayViews(in: blocks)
    }

    private func syncCollapsedXMLTagState() {
        markdownDelegate.collapsedXMLTagRanges = []
    }

    private struct FrontmatterControlLayout {
        let document: EditableFrontmatterDocument
        let blockRect: CGRect
    }

    private func frontmatterControlLayout() -> FrontmatterControlLayout? {
        guard let document = markdownDelegate.frontmatterDocument else {
            return nil
        }

        let contentLeading = textView.textContainerInset.left + textView.textContainer.lineFragmentPadding
        let contentTrailing = textView.bounds.width
            - textView.textContainerInset.right
            - textView.textContainer.lineFragmentPadding
        let leading = max(0, contentLeading - FrontmatterBlockLayout.horizontalPadding)
        let trailing = min(textView.bounds.width, contentTrailing + FrontmatterBlockLayout.horizontalPadding)
        let width = max(0, trailing - leading)
        guard width > 0 else { return nil }

        let blockRect = FrontmatterBlockLayout.blockRect(
            point: CGPoint(x: leading, y: verticalTextInset),
            contentWidth: width,
            document: document,
            isExpanded: isFrontmatterBlockExpanded
        )
        return FrontmatterControlLayout(document: document, blockRect: blockRect)
    }

    private func refreshFrontmatterControls() {
        guard let layout = frontmatterControlLayout(),
              layout.blockRect.intersects(textView.bounds.insetBy(dx: -8, dy: -80)) else {
            clearFrontmatterControls()
            return
        }

        let blockView = frontmatterBlockView ?? FrontmatterBlockView()
        blockView.frame = layout.blockRect
        blockView.configure(
            document: layout.document,
            isExpanded: isFrontmatterBlockExpanded,
            editingTarget: frontmatterEditingTarget
        )
        if blockView.superview !== textView {
            textView.addSubview(blockView)
        }
        frontmatterBlockView = blockView

        let headerButton = frontmatterHeaderButton ?? makeFrontmatterHeaderButton()
        headerButton.frame = FrontmatterBlockLayout.headerRect(in: layout.blockRect)
        headerButton.accessibilityIdentifier = "frontmatter_metadata_header"
        headerButton.accessibilityLabel = isFrontmatterBlockExpanded ? "Collapse metadata" : "Expand metadata"
        if headerButton.superview !== textView {
            textView.addSubview(headerButton)
        }
        frontmatterHeaderButton = headerButton

        var activeValueIndexes: Set<Int> = []
        var activeDeleteIndexes: Set<Int> = []
        var activeEditIndexes: Set<Int> = []
        if isFrontmatterBlockExpanded {
            for index in 0..<FrontmatterBlockLayout.rowCount(for: layout.document) {
                activeValueIndexes.insert(index)
                let rowRect = FrontmatterBlockLayout.rowRect(at: index, in: layout.blockRect)
                let isNewRow = index == FrontmatterBlockLayout.newFieldRowIndex(for: layout.document)
                let isURLRow = !isNewRow && layout.document.fields[index].url != nil
                let buttonRect: CGRect
                if isNewRow {
                    buttonRect = FrontmatterBlockLayout.valueRect(for: rowRect, blockWidth: layout.blockRect.width)
                        .insetBy(dx: -4, dy: -5)
                } else {
                    buttonRect = FrontmatterBlockLayout.valueRect(
                        for: rowRect,
                        blockWidth: layout.blockRect.width,
                        hasEditControl: isURLRow
                    ).insetBy(dx: -4, dy: -5)
                }
                let button = frontmatterValueButtons[index] ?? makeFrontmatterValueButton(index: index)
                button.tag = index
                button.frame = buttonRect
                if isNewRow {
                    button.accessibilityIdentifier = "frontmatter_new_value"
                    button.accessibilityLabel = "Add metadata value"
                } else {
                    let field = layout.document.fields[index]
                    button.accessibilityIdentifier = "frontmatter_value_\(field.key)"
                    button.accessibilityLabel = isURLRow
                        ? "Open metadata link \(field.key)"
                        : "Edit metadata value \(field.key)"
                }
                if button.superview !== textView {
                    textView.addSubview(button)
                }
                frontmatterValueButtons[index] = button

                let deleteButton = frontmatterDeleteButtons[index] ?? makeFrontmatterDeleteButton(index: index)
                deleteButton.tag = index
                deleteButton.frame = FrontmatterBlockLayout.deleteRect(for: rowRect).insetBy(dx: -6, dy: -6)
                if isNewRow {
                    deleteButton.accessibilityIdentifier = "frontmatter_new_field_add"
                    deleteButton.accessibilityLabel = "Add metadata field"
                } else {
                    let field = layout.document.fields[index]
                    deleteButton.accessibilityIdentifier = "frontmatter_delete_\(field.key)"
                    deleteButton.accessibilityLabel = "Delete metadata \(field.key)"
                }
                if deleteButton.superview !== textView {
                    textView.addSubview(deleteButton)
                }
                frontmatterDeleteButtons[index] = deleteButton
                activeDeleteIndexes.insert(index)

                if isURLRow {
                    let editButton = frontmatterEditButtons[index] ?? makeFrontmatterEditButton(index: index)
                    editButton.tag = index
                    editButton.frame = FrontmatterBlockLayout.editRect(for: rowRect).insetBy(dx: -6, dy: -6)
                    let field = layout.document.fields[index]
                    editButton.accessibilityIdentifier = "frontmatter_edit_\(field.key)"
                    editButton.accessibilityLabel = "Edit metadata value \(field.key)"
                    if editButton.superview !== textView {
                        textView.addSubview(editButton)
                    }
                    frontmatterEditButtons[index] = editButton
                    activeEditIndexes.insert(index)
                }
            }
        }

        for (index, button) in frontmatterValueButtons where !activeValueIndexes.contains(index) {
            button.removeFromSuperview()
            frontmatterValueButtons.removeValue(forKey: index)
        }
        for (index, button) in frontmatterDeleteButtons where !activeDeleteIndexes.contains(index) {
            button.removeFromSuperview()
            frontmatterDeleteButtons.removeValue(forKey: index)
        }
        for (index, button) in frontmatterEditButtons where !activeEditIndexes.contains(index) {
            button.removeFromSuperview()
            frontmatterEditButtons.removeValue(forKey: index)
        }

        if let editingField = frontmatterEditingField,
           let editingTarget = frontmatterEditingTarget,
           let editingFrame = frontmatterEditingFrame(for: editingTarget, in: layout),
           isFrontmatterBlockExpanded {
            editingField.frame = editingFrame
        }
        if let editingKeyField = frontmatterEditingKeyField,
           let layout = frontmatterControlLayout(),
           let keyFrame = frontmatterNewKeyEditingFrame(in: layout),
           isFrontmatterBlockExpanded {
            editingKeyField.frame = keyFrame
        }
    }

    private func makeFrontmatterHeaderButton() -> UIButton {
        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        button.addTarget(self, action: #selector(toggleFrontmatterBlockExpansion), for: .touchUpInside)
        return button
    }

    private func makeFrontmatterValueButton(index: Int) -> UIButton {
        let button = UIButton(type: .custom)
        button.tag = index
        button.backgroundColor = .clear
        button.addTarget(self, action: #selector(frontmatterValueTapped(_:)), for: .touchUpInside)
        return button
    }

    private func makeFrontmatterDeleteButton(index: Int) -> UIButton {
        let button = UIButton(type: .custom)
        button.tag = index
        button.backgroundColor = .clear
        button.addTarget(self, action: #selector(frontmatterDeleteTapped(_:)), for: .touchUpInside)
        return button
    }

    private func makeFrontmatterEditButton(index: Int) -> UIButton {
        let button = UIButton(type: .custom)
        button.tag = index
        button.backgroundColor = .clear
        button.addTarget(self, action: #selector(frontmatterEditTapped(_:)), for: .touchUpInside)
        return button
    }

    private func clearFrontmatterControls() {
        frontmatterBlockView?.removeFromSuperview()
        frontmatterBlockView = nil
        frontmatterHeaderButton?.removeFromSuperview()
        frontmatterHeaderButton = nil
        frontmatterValueButtons.values.forEach { $0.removeFromSuperview() }
        frontmatterValueButtons.removeAll()
        frontmatterDeleteButtons.values.forEach { $0.removeFromSuperview() }
        frontmatterDeleteButtons.removeAll()
        frontmatterEditButtons.values.forEach { $0.removeFromSuperview() }
        frontmatterEditButtons.removeAll()
        frontmatterEditingKeyField?.removeFromSuperview()
        frontmatterEditingKeyField = nil
        frontmatterEditingField?.removeFromSuperview()
        frontmatterEditingField = nil
        frontmatterEditingTarget = nil
    }

    @objc
    private func toggleFrontmatterBlockExpansion() {
        finishFrontmatterEditing(commit: true)
        isFrontmatterBlockExpanded.toggle()
        invalidateFrontmatterLayout()
    }

    @objc
    private func frontmatterValueTapped(_ sender: UIButton) {
        guard let document = markdownDelegate.frontmatterDocument,
              sender.tag >= 0,
              sender.tag < FrontmatterBlockLayout.rowCount(for: document) else {
            return
        }

        if sender.tag == FrontmatterBlockLayout.newFieldRowIndex(for: document) {
            beginEditingNewFrontmatterField()
            return
        }

        let field = document.fields[sender.tag]
        if let url = field.url {
            UIApplication.shared.open(url)
            return
        }
        beginEditingFrontmatterField(field)
    }

    @objc
    private func frontmatterDeleteTapped(_ sender: UIButton) {
        finishFrontmatterEditing(commit: true)
        guard let document = markdownDelegate.frontmatterDocument,
              sender.tag >= 0,
              sender.tag < FrontmatterBlockLayout.rowCount(for: document) else {
            return
        }

        if sender.tag == FrontmatterBlockLayout.newFieldRowIndex(for: document) {
            beginEditingNewFrontmatterField()
            return
        }

        deleteFrontmatterField(document.fields[sender.tag])
    }

    @objc
    private func frontmatterEditTapped(_ sender: UIButton) {
        guard let document = markdownDelegate.frontmatterDocument,
              sender.tag >= 0,
              sender.tag < document.fields.count else {
            return
        }
        beginEditingFrontmatterField(document.fields[sender.tag])
    }

    private func beginEditingFrontmatterField(_ field: EditableFrontmatterField) {
        guard let layout = frontmatterControlLayout(),
              let valueRect = frontmatterEditingFrame(for: .existingValue(key: field.key), in: layout) else {
            return
        }

        frontmatterEditingField?.removeFromSuperview()
        let textField = makeFrontmatterTextField(frame: valueRect, text: field.value)
        textField.accessibilityIdentifier = "frontmatter_value_editor_\(field.key)"
        textView.addSubview(textField)
        frontmatterEditingField = textField
        frontmatterEditingTarget = .existingValue(key: field.key)
        frontmatterBlockView?.configure(
            document: layout.document,
            isExpanded: isFrontmatterBlockExpanded,
            editingTarget: frontmatterEditingTarget
        )
        textField.becomeFirstResponder()
        textField.selectAll(nil)
    }

    private func beginEditingNewFrontmatterField() {
        guard let layout = frontmatterControlLayout(),
              let keyRect = frontmatterNewKeyEditingFrame(in: layout),
              let valueRect = frontmatterEditingFrame(for: .newField, in: layout) else {
            return
        }

        frontmatterEditingKeyField?.removeFromSuperview()
        frontmatterEditingField?.removeFromSuperview()
        let keyField = makeFrontmatterTextField(frame: keyRect, text: "", placeholder: "key")
        keyField.accessibilityIdentifier = "frontmatter_new_key_editor"
        keyField.returnKeyType = .next
        let valueField = makeFrontmatterTextField(frame: valueRect, text: "", placeholder: "value")
        valueField.accessibilityIdentifier = "frontmatter_new_value_editor"
        valueField.returnKeyType = .done
        textView.addSubview(keyField)
        textView.addSubview(valueField)
        frontmatterEditingKeyField = keyField
        frontmatterEditingField = valueField
        frontmatterBlockView?.configure(
            document: layout.document,
            isExpanded: isFrontmatterBlockExpanded,
            editingTarget: .newField
        )
        frontmatterEditingTarget = .newField
        keyField.becomeFirstResponder()
    }

    private func makeFrontmatterTextField(
        frame: CGRect,
        text: String,
        placeholder: String? = nil
    ) -> PaddedTextField {
        let textField = PaddedTextField(frame: frame)
        textField.text = text
        textField.placeholder = placeholder
        textField.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.textColor = AppTheme.uiPrimaryText
        textField.tintColor = AppTheme.uiPrimaryText
        textField.backgroundColor = FrontmatterBlockLayout.uiFieldBackgroundColor
        textField.layer.cornerRadius = 4
        textField.layer.masksToBounds = true
        textField.borderStyle = .none
        textField.returnKeyType = .done
        textField.delegate = self
        return textField
    }

    private func frontmatterEditingFrame(
        for target: FrontmatterEditingTarget,
        in layout: FrontmatterControlLayout
    ) -> CGRect? {
        let rowIndex: Int
        let hasEditControl: Bool
        switch target {
        case .existingValue(let key):
            guard let index = layout.document.fields.firstIndex(where: { $0.key == key }) else { return nil }
            rowIndex = index
            hasEditControl = layout.document.fields[index].url != nil
        case .newField:
            rowIndex = FrontmatterBlockLayout.newFieldRowIndex(for: layout.document)
            hasEditControl = false
        }

        let rowRect = FrontmatterBlockLayout.rowRect(at: rowIndex, in: layout.blockRect)
        return FrontmatterBlockLayout.valueRect(
            for: rowRect,
            blockWidth: layout.blockRect.width,
            hasEditControl: hasEditControl
        ).insetBy(dx: 0, dy: 4)
    }

    private func frontmatterNewKeyEditingFrame(in layout: FrontmatterControlLayout) -> CGRect? {
        let rowRect = FrontmatterBlockLayout.rowRect(
            at: FrontmatterBlockLayout.newFieldRowIndex(for: layout.document),
            in: layout.blockRect
        )
        return FrontmatterBlockLayout.keyRect(for: rowRect, blockWidth: layout.blockRect.width)
            .insetBy(dx: 0, dy: 4)
    }

    private func finishFrontmatterEditing(commit: Bool) {
        guard let textField = frontmatterEditingField,
              let target = frontmatterEditingTarget else {
            return
        }

        let value = textField.text ?? ""
        let keyValue = frontmatterEditingKeyField?.text ?? ""
        frontmatterEditingKeyField?.removeFromSuperview()
        frontmatterEditingKeyField = nil
        textField.removeFromSuperview()
        frontmatterEditingField = nil
        frontmatterEditingTarget = nil

        guard commit else { return }

        let currentText = textView.text ?? ""
        let updatedText: String
        switch target {
        case .existingValue(let key):
            updatedText = EditableFrontmatterDocument.updatingField(key: key, value: value, in: currentText)
        case .newField:
            guard let parsed = EditableFrontmatterDocument.parsedFieldInput(key: keyValue, value: value) else { return }
            updatedText = EditableFrontmatterDocument.addingField(key: parsed.key, value: parsed.value, in: currentText)
        }
        guard updatedText != currentText else { return }

        let contentOffset = textView.contentOffset
        let selectedRange = textView.selectedRange
        let updatedLength = (updatedText as NSString).length
        let selectionLocation = min(selectedRange.location, updatedLength)
        let selection = NSRange(
            location: selectionLocation,
            length: min(selectedRange.length, max(0, updatedLength - selectionLocation))
        )
        applySelectionTransform(TextSelectionTransform(text: updatedText, selection: selection))
        updateFrontmatterMetadata(for: updatedText)
        invalidateFrontmatterLayout()
        restoreContentOffset(contentOffset)
    }

    private func deleteFrontmatterField(_ field: EditableFrontmatterField) {
        let currentText = textView.text ?? ""
        let updatedText = EditableFrontmatterDocument.deletingField(key: field.key, in: currentText)
        guard updatedText != currentText else { return }

        let contentOffset = textView.contentOffset
        let selectedRange = textView.selectedRange
        let updatedLength = (updatedText as NSString).length
        let selectionLocation = min(selectedRange.location, updatedLength)
        let selection = NSRange(
            location: selectionLocation,
            length: min(selectedRange.length, max(0, updatedLength - selectionLocation))
        )
        applySelectionTransform(TextSelectionTransform(text: updatedText, selection: selection))
        updateFrontmatterMetadata(for: updatedText)
        invalidateFrontmatterLayout()
        restoreContentOffset(contentOffset)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === frontmatterEditingKeyField {
            frontmatterEditingField?.becomeFirstResponder()
            return true
        }
        finishFrontmatterEditing(commit: true)
        textView.becomeFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField === frontmatterEditingField {
            finishFrontmatterEditing(commit: true)
        }
    }

    private func invalidateFrontmatterLayout() {
        _ = syncReadableWidthInsets()
        scheduleEditorOverlayRefresh()
    }

    private func invalidateRenderableBlockCache() {
        cachedRenderableBlocks = []
        cachedRenderableBlocksText = ""
        cachedCollapsedXMLTagRanges = []
    }

    private func currentRenderableBlocks() -> [MarkdownRenderableBlock] {
        let text = textView.textStorage.mutableString
        let collapsedXMLTagRanges = markdownDelegate.collapsedXMLTagRanges

        if text as String == cachedRenderableBlocksText,
           collapsedXMLTagRanges == cachedCollapsedXMLTagRanges {
            return cachedRenderableBlocks
        }

        let blocks = MarkdownSemanticAnalyzer.renderableBlocks(
            in: text,
            collapsedXMLTagRanges: collapsedXMLTagRanges
        )
        cachedRenderableBlocks = blocks
        cachedRenderableBlocksText = text as String
        cachedCollapsedXMLTagRanges = collapsedXMLTagRanges
        return blocks
    }

    private func renderableBlocks(intersecting ranges: [NSRange]) -> [MarkdownRenderableBlock] {
        let text = textView.textStorage.mutableString
        let collapsedXMLTagRanges = markdownDelegate.collapsedXMLTagRanges
        var blocks: [MarkdownRenderableBlock] = []
        var seenLocations: Set<Int> = []

        for range in ranges {
            for block in MarkdownSemanticAnalyzer.renderableBlocks(
                in: text,
                collapsedXMLTagRanges: collapsedXMLTagRanges,
                intersecting: range
            ) where seenLocations.insert(block.paragraphRange.location).inserted {
                blocks.append(block)
            }
        }

        return blocks
    }

    private func visibleRenderableBlocks() -> [MarkdownRenderableBlock] {
        guard let visibleTextRange = visibleTextRange() else {
            return currentRenderableBlocks()
        }
        return renderableBlocks(intersecting: [visibleTextRange])
    }

    private func selectedLineRange() -> NSRange? {
        let nsText = textView.textStorage.mutableString
        guard nsText.length > 0, textView.selectedRange.location != NSNotFound else { return nil }

        let safeLocation = max(0, min(textView.selectedRange.location, nsText.length))
        let safeLength = max(0, min(textView.selectedRange.length, nsText.length - safeLocation))
        return nsText.lineRange(for: NSRange(location: safeLocation, length: safeLength))
    }

    private func visibleTextRange() -> NSRange? {
        let expandedBounds = textView.bounds.insetBy(dx: 0, dy: -120)
        let leadingX = textView.textContainerInset.left + textView.textContainer.lineFragmentPadding
        guard let startPosition = textView.closestPosition(to: CGPoint(x: leadingX, y: expandedBounds.minY)),
              let endPosition = textView.closestPosition(to: CGPoint(x: leadingX, y: expandedBounds.maxY)) else {
            return nil
        }

        let start = textView.offset(from: textView.beginningOfDocument, to: startPosition)
        let end = textView.offset(from: textView.beginningOfDocument, to: endPosition)
        let nsText = textView.textStorage.mutableString
        guard nsText.length > 0 else { return nil }

        let lowerBound = max(0, min(start, end, nsText.length))
        let upperBound = max(0, min(max(start, end), nsText.length))
        return nsText.lineRange(for: NSRange(location: lowerBound, length: upperBound - lowerBound))
    }

    private func requestImageLoad(for url: URL) {
        guard loadingImageURLs.insert(url).inserted else { return }

        MarkdownImageLoader.load(url: url) { [weak self] image in
            guard let self else { return }
            self.loadingImageURLs.remove(url)
            if image != nil {
                self.scheduleImageLayoutInvalidation()
            }
        }
    }

    private func scheduleImageLayoutInvalidation() {
        guard !isImageLayoutInvalidationScheduled else { return }
        isImageLayoutInvalidationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isImageLayoutInvalidationScheduled = false
            self.invalidateImageLayouts()
        }
    }

    private func invalidateImageLayouts() {
        guard isViewLoaded,
              let textView,
              let textLayoutManager = textView.textLayoutManager else {
            return
        }
        textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
        refreshImageOverlayViews()
    }

    private func refreshImageOverlayViews() {
        guard isViewLoaded, textView != nil else { return }
        refreshImageOverlayViews(in: visibleRenderableBlocks())
    }

    private func refreshImageOverlayViews(in blocks: [MarkdownRenderableBlock]) {
        guard isViewLoaded, textView != nil else { return }
        let visibleRect = textView.bounds.insetBy(dx: -8, dy: -200)
        var activeLocations: Set<Int> = []

        for block in blocks {
            guard case .imageLink(let imageLink) = block.kind,
                  !block.isCollapsedXMLTagContent,
                  let rect = imageOverlayRect(for: block),
                  rect.intersects(visibleRect) else {
                continue
            }

            activeLocations.insert(block.paragraphRange.location)

            let view = imageOverlayViews[block.paragraphRange.location] ?? makeImageOverlayView()
            view.frame = rect.integral
            applyImage(to: view, imageLink: imageLink, displayRect: rect)
            if view.superview !== textView {
                textView.addSubview(view)
            }
            imageOverlayViews[block.paragraphRange.location] = view
        }

        for (location, view) in imageOverlayViews where !activeLocations.contains(location) {
            view.removeFromSuperview()
            imageOverlayViews.removeValue(forKey: location)
        }
    }

    private func makeImageOverlayView() -> UIImageView {
        let view = UIImageView(frame: .zero)
        view.layer.cornerRadius = MarkdownVisualSpec.imagePreviewCornerRadius
        view.layer.masksToBounds = true
        view.backgroundColor = AppTheme.uiCodeBackground
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        return view
    }

    private func applyImage(to view: UIImageView, imageLink: MarkdownImageLink, displayRect: CGRect) {
        guard let url = imageLink.url else {
            view.image = nil
            return
        }

        let scale = UIScreen.main.scale
        let maxPixel = ceil(max(displayRect.width, displayRect.height) * scale)
        if let displayImage = MarkdownImageLoader.cachedDisplayImage(for: url, maxPixelSize: maxPixel) {
            if view.image !== displayImage {
                view.image = displayImage
            }
        } else {
            view.image = nil
        }
    }

    private func imageOverlayRect(for block: MarkdownRenderableBlock) -> CGRect? {
        guard let position = textView.position(
            from: textView.beginningOfDocument,
            offset: block.visibleLineRange.location
        ) else {
            return nil
        }

        let caretRect = textView.caretRect(for: position)
        guard isFiniteRect(caretRect) else { return nil }

        let leading = textView.textContainerInset.left + textView.textContainer.lineFragmentPadding
        let trailing = textView.bounds.width
            - textView.textContainerInset.right
            - textView.textContainer.lineFragmentPadding
        let width = max(0, trailing - leading)
        guard width > 0 else { return nil }

        let verticalPadding = MarkdownVisualSpec.imagePreviewVerticalPadding
        let totalHeight: CGFloat
        if let url = imageLink(in: block)?.url,
           let imageSize = MarkdownImageDimensionCache.cachedSize(for: url),
           imageSize.width > 0 {
            totalHeight = width * (imageSize.height / imageSize.width)
        } else {
            totalHeight = max(0, MarkdownVisualSpec.imagePreviewReservedHeight - verticalPadding * 2)
        }

        return CGRect(
            x: leading,
            y: caretRect.minY + verticalPadding,
            width: width,
            height: totalHeight
        )
    }

    private func imageLink(in block: MarkdownRenderableBlock) -> MarkdownImageLink? {
        if case .imageLink(let link) = block.kind {
            return link
        }
        return nil
    }

    private func refreshTodoMarkerButtons() {
        guard isViewLoaded, textView != nil else { return }
        refreshTodoMarkerButtons(in: visibleRenderableBlocks())
    }

    private func refreshTodoMarkerButtons(in blocks: [MarkdownRenderableBlock]) {
        guard isViewLoaded, textView != nil else { return }
        let visibleRect = textView.bounds.insetBy(dx: -8, dy: -80)
        var activeLocations: Set<Int> = []

        for block in blocks {
            guard case .todo(let checked, _) = block.kind,
                  !block.isCollapsedXMLTagContent,
                  let overlayLayout = todoMarkerOverlayLayout(for: block),
                  overlayLayout.hitRect.intersects(visibleRect) else {
                continue
            }

            activeLocations.insert(block.paragraphRange.location)

            let button = todoMarkerButtons[block.paragraphRange.location] ?? makeTodoMarkerButton()
            button.paragraphLocation = block.paragraphRange.location
            button.isChecked = checked
            button.accessibilityIdentifier = "todo_checkbox_\(block.paragraphRange.location)"
            button.accessibilityLabel = checked ? "Checked todo" : "Unchecked todo"
            button.accessibilityValue = checked ? "Checked" : "Unchecked"
            button.frame = overlayLayout.hitRect.integral
            button.markerRectInBounds = overlayLayout.markerRect.offsetBy(
                dx: -overlayLayout.hitRect.minX,
                dy: -overlayLayout.hitRect.minY
            )
            if button.superview !== textView {
                textView.addSubview(button)
            }
            todoMarkerButtons[block.paragraphRange.location] = button
        }

        for (location, button) in todoMarkerButtons where !activeLocations.contains(location) {
            button.removeFromSuperview()
            todoMarkerButtons.removeValue(forKey: location)
        }
    }

    private func makeTodoMarkerButton() -> TodoMarkerButton {
        let button = TodoMarkerButton(frame: .zero)
        button.addTarget(self, action: #selector(handleTodoMarkerButtonTap(_:)), for: .touchUpInside)
        return button
    }

    private func refreshDividerLineViews() {
        guard isViewLoaded, textView != nil else { return }
        refreshDividerLineViews(in: visibleRenderableBlocks())
    }

    private func refreshDividerLineViews(in blocks: [MarkdownRenderableBlock]) {
        guard isViewLoaded, textView != nil else { return }
        let visibleRect = textView.bounds.insetBy(dx: -8, dy: -80)
        var activeLocations: Set<Int> = []

        for block in blocks {
            guard block.kind == .divider,
                  !block.isCollapsedXMLTagContent,
                  !revealedDividerRanges.contains(where: { NSEqualRanges($0, block.visibleLineRange) }),
                  let rect = dividerLineRect(for: block),
                  rect.intersects(visibleRect) else {
                continue
            }

            activeLocations.insert(block.paragraphRange.location)

            let lineView = dividerLineViews[block.paragraphRange.location] ?? makeDividerLineView()
            lineView.frame = rect.integral
            if lineView.superview !== textView {
                textView.addSubview(lineView)
            }
            dividerLineViews[block.paragraphRange.location] = lineView
        }

        for (location, lineView) in dividerLineViews where !activeLocations.contains(location) {
            lineView.removeFromSuperview()
            dividerLineViews.removeValue(forKey: location)
        }
    }

    private func makeDividerLineView() -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = AppTheme.uiMutedText.withAlphaComponent(0.45)
        view.layer.cornerRadius = MarkdownVisualSpec.dividerLineHeight / 2
        return view
    }

    private func dividerLineRect(for block: MarkdownRenderableBlock) -> CGRect? {
        guard let position = textView.position(
            from: textView.beginningOfDocument,
            offset: block.visibleLineRange.location
        ) else {
            return nil
        }

        let caretRect = textView.caretRect(for: position)
        guard isFiniteRect(caretRect) else { return nil }

        let leading = textView.textContainerInset.left + textView.textContainer.lineFragmentPadding
        let trailing = textView.bounds.width
            - textView.textContainerInset.right
            - textView.textContainer.lineFragmentPadding
        let width = max(0, trailing - leading)
        let y = caretRect.midY - MarkdownVisualSpec.dividerLineHeight / 2
        return CGRect(
            x: leading,
            y: y,
            width: width,
            height: MarkdownVisualSpec.dividerLineHeight
        )
    }

    @objc
    private func handleTodoMarkerButtonTap(_ sender: TodoMarkerButton) {
        toggleTodoCheckbox(atParagraphLocation: sender.paragraphLocation)
    }

    @discardableResult
    func toggleTodoMarker(atTextViewPoint point: CGPoint) -> Bool {
        syncCollapsedXMLTagState()
        let blocks = currentRenderableBlocks()

        for block in blocks where !block.isCollapsedXMLTagContent {
            guard case .todo = block.kind,
                  let overlayLayout = todoMarkerOverlayLayout(for: block),
                  overlayLayout.hitRect.insetBy(dx: -4, dy: -4).contains(point) else {
                continue
            }

            toggleTodoCheckbox(atParagraphLocation: block.paragraphRange.location)
            return true
        }

        return false
    }

    func todoMarkerHitRect(forParagraphLocation paragraphLocation: Int) -> CGRect? {
        syncCollapsedXMLTagState()
        guard let block = currentRenderableBlocks().first(where: { $0.paragraphRange.location == paragraphLocation }),
              !block.isCollapsedXMLTagContent,
              case .todo = block.kind else {
            return nil
        }

        return todoMarkerOverlayLayout(for: block)?.hitRect
    }

    private func todoMarkerOverlayLayout(for block: MarkdownRenderableBlock) -> (markerRect: CGRect, hitRect: CGRect)? {
        let prefixLength = block.kind.prefixLength(in: block.lineText)
        let contentLocation = block.paragraphRange.location + prefixLength
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
        let hitRect = CGRect(
            x: hitLeading,
            y: markerRect.minY,
            width: hitTrailing - hitLeading,
            height: markerRect.height
        )
        return (markerRect, hitRect)
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

private final class HyperlinkInsertionPopoverViewController: NSViewController, NSTextFieldDelegate {
    var onCancel: (() -> Void)?
    var onInsert: ((String) -> Void)?

    private let draft: HyperlinkInsertionDraft
    private let destinationField = NSTextField()
    private let insertButton = NSButton(title: HyperlinkInsertionStrings.insert, target: nil, action: nil)

    init(draft: HyperlinkInsertionDraft) {
        self.draft = draft
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 158))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        let titleLabel = NSTextField(labelWithString: HyperlinkInsertionStrings.title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = AppTheme.nsPrimaryText

        let labelField = NSTextField(labelWithString: draft.label)
        labelField.font = .systemFont(ofSize: 13)
        labelField.textColor = AppTheme.nsMutedText
        labelField.lineBreakMode = .byTruncatingMiddle

        destinationField.placeholderString = HyperlinkInsertionStrings.destinationPlaceholder
        destinationField.font = .systemFont(ofSize: 13)
        destinationField.delegate = self
        destinationField.target = self
        destinationField.action = #selector(insert)
        destinationField.setAccessibilityIdentifier("hyperlink_destination_field")

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .centerY

        let cancelButton = NSButton(title: HyperlinkInsertionStrings.cancel, target: self, action: #selector(cancel))
        insertButton.target = self
        insertButton.action = #selector(insert)
        insertButton.keyEquivalent = "\r"

        buttonStack.addArrangedSubview(NSView())
        buttonStack.addArrangedSubview(cancelButton)
        buttonStack.addArrangedSubview(insertButton)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(labelField)
        stackView.addArrangedSubview(destinationField)
        stackView.addArrangedSubview(buttonStack)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            destinationField.heightAnchor.constraint(equalToConstant: 28),
        ])

        updateInsertButton()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(destinationField)
    }

    func controlTextDidChange(_ obj: Notification) {
        updateInsertButton()
    }

    private func updateInsertButton() {
        insertButton.isEnabled = HyperlinkMarkdown.target(from: destinationField.stringValue) != nil
    }

    @objc
    private func cancel() {
        onCancel?()
    }

    @objc
    private func insert() {
        let destination = destinationField.stringValue
        guard HyperlinkMarkdown.target(from: destination) != nil else { return }
        onInsert?(destination)
    }
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    private func centeredRect(forBounds rect: NSRect) -> NSRect {
        var titleRect = super.titleRect(forBounds: rect)
        let minimumHeight = self.cellSize(forBounds: rect).height
        titleRect.origin.y += (titleRect.height - minimumHeight) / 2
        titleRect.size.height = minimumHeight
        return titleRect
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(forBounds: rect)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: centeredRect(forBounds: cellFrame), in: controlView)
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: centeredRect(forBounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: centeredRect(forBounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}

private final class FrontmatterBlockView: NSView {
    var document: EditableFrontmatterDocument?
    var isExpanded = true
    var editingTarget: FrontmatterEditingTarget?

    override var isFlipped: Bool { true }

    func configure(
        document: EditableFrontmatterDocument,
        isExpanded: Bool,
        editingTarget: FrontmatterEditingTarget?
    ) {
        self.document = document
        self.isExpanded = isExpanded
        self.editingTarget = editingTarget
        needsDisplay = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = FrontmatterBlockLayout.nsSurfaceColor.cgColor
        layer?.cornerRadius = FrontmatterBlockLayout.cornerRadius
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let document else {
            return
        }

        let blockRect = bounds.integral
        let path = CGPath(
            roundedRect: blockRect,
            cornerWidth: FrontmatterBlockLayout.cornerRadius,
            cornerHeight: FrontmatterBlockLayout.cornerRadius,
            transform: nil
        )
        context.addPath(path)
        context.setFillColor(FrontmatterBlockLayout.nsSurfaceColor.cgColor)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(AppTheme.nsSeparator.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1)
        context.strokePath()

        drawChevron(in: blockRect, context: context)
        drawText("Metadata", in: titleRect(in: blockRect), font: .systemFont(ofSize: 12, weight: .semibold), color: AppTheme.nsPrimaryText)
        drawText(
            "\(document.fields.count)",
            in: countRect(in: blockRect),
            font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            color: AppTheme.nsMutedText,
            alignment: .right
        )

        guard isExpanded else { return }
        for index in 0..<FrontmatterBlockLayout.rowCount(for: document) {
            let rowRect = FrontmatterBlockLayout.rowRect(at: index, in: blockRect)
            let keyRect = FrontmatterBlockLayout.keyRect(for: rowRect, blockWidth: blockRect.width)
            let isExistingField = index < document.fields.count
            let isURLField = isExistingField && document.fields[index].url != nil
            let valueRect = FrontmatterBlockLayout.valueRect(
                for: rowRect,
                blockWidth: blockRect.width,
                hasEditControl: isURLField
            )

            context.move(to: CGPoint(x: rowRect.minX, y: rowRect.minY))
            context.addLine(to: CGPoint(x: blockRect.maxX - FrontmatterBlockLayout.horizontalPadding, y: rowRect.minY))
            context.setStrokeColor(AppTheme.nsSeparator.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(1)
            context.strokePath()

            if isExistingField {
                let field = document.fields[index]
                let isEditingThisRow = editingTarget == .existingValue(key: field.key)
                drawText(field.key, in: keyRect, font: .monospacedSystemFont(ofSize: 12, weight: .regular), color: AppTheme.nsMutedText)
                if !isEditingThisRow {
                    drawText(field.displayValue, in: valueRect, font: .monospacedSystemFont(ofSize: 13, weight: .regular), color: field.url == nil ? AppTheme.nsPrimaryText : .linkColor)
                }
                if isURLField {
                    let editRect = FrontmatterBlockLayout.editRect(for: rowRect)
                    drawPencilIcon(in: editRect, context: context, color: AppTheme.nsSecondaryText)
                }
                let deleteRect = FrontmatterBlockLayout.deleteRect(for: rowRect)
                drawCrossIcon(in: deleteRect, context: context, color: AppTheme.nsSecondaryText)
            } else {
                let isEditingNewRow = editingTarget == .newField
                let placeholderColor = AppTheme.nsMutedText.withAlphaComponent(0.7)
                if !isEditingNewRow {
                    drawSeparatedPlaceholder(
                        keyRect: keyRect,
                        valueRect: valueRect,
                        placeholderColor: placeholderColor,
                        context: context
                    )
                }
                let addRect = FrontmatterBlockLayout.deleteRect(for: rowRect)
                drawPlusIcon(in: addRect, context: context, color: AppTheme.nsSecondaryText)
            }
        }
    }

    private func drawSeparatedPlaceholder(
        keyRect: CGRect,
        valueRect: CGRect,
        placeholderColor: NSColor,
        context: CGContext
    ) {
        drawText("key", in: keyRect, font: .monospacedSystemFont(ofSize: 12, weight: .regular), color: placeholderColor)
        drawText("value", in: valueRect, font: .monospacedSystemFont(ofSize: 13, weight: .regular), color: placeholderColor)
    }

    private func drawCrossIcon(in rect: CGRect, context: CGContext, color: NSColor) {
        let inset = rect.width * 0.28
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.move(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.6)
        context.setLineCap(.round)
        context.strokePath()
    }

    private func drawPlusIcon(in rect: CGRect, context: CGContext, color: NSColor) {
        let inset = rect.width * 0.26
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - inset))
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.6)
        context.setLineCap(.round)
        context.strokePath()
    }

    private func drawPencilIcon(in rect: CGRect, context: CGContext, color: NSColor) {
        let inset = rect.width * 0.24
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        path.move(to: CGPoint(x: rect.minX + inset * 0.8, y: rect.maxY - inset * 0.5))
        path.addLine(to: CGPoint(x: rect.maxX - inset * 0.8, y: rect.maxY - inset * 0.5))
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.4)
        context.setLineCap(.round)
        context.strokePath()
    }

    private func titleRect(in rect: CGRect) -> CGRect {
        let leading = rect.minX
            + FrontmatterBlockLayout.horizontalPadding
            + FrontmatterBlockLayout.chevronWidth
            + FrontmatterBlockLayout.iconTextGap
        let trailing = rect.maxX - FrontmatterBlockLayout.horizontalPadding - FrontmatterBlockLayout.countWidth
        return CGRect(x: leading, y: rect.minY, width: max(0, trailing - leading), height: FrontmatterBlockLayout.collapsedHeight)
    }

    private func countRect(in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.maxX - FrontmatterBlockLayout.horizontalPadding - FrontmatterBlockLayout.countWidth,
            y: rect.minY,
            width: FrontmatterBlockLayout.countWidth,
            height: FrontmatterBlockLayout.collapsedHeight
        )
    }

    private func drawChevron(in rect: CGRect, context: CGContext) {
        let centerX = rect.minX + FrontmatterBlockLayout.horizontalPadding + FrontmatterBlockLayout.chevronWidth / 2
        let centerY = rect.minY + FrontmatterBlockLayout.collapsedHeight / 2
        let size: CGFloat = 8
        let path = CGMutablePath()
        if isExpanded {
            path.move(to: CGPoint(x: centerX - size * 0.45, y: centerY - size * 0.2))
            path.addLine(to: CGPoint(x: centerX, y: centerY + size * 0.3))
            path.addLine(to: CGPoint(x: centerX + size * 0.45, y: centerY - size * 0.2))
        } else {
            path.move(to: CGPoint(x: centerX - size * 0.25, y: centerY - size * 0.45))
            path.addLine(to: CGPoint(x: centerX + size * 0.25, y: centerY))
            path.addLine(to: CGPoint(x: centerX - size * 0.25, y: centerY + size * 0.45))
        }
        context.addPath(path)
        context.setStrokeColor(AppTheme.nsPrimaryText.cgColor)
        context.setLineWidth(1.7)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle,
            ]
        )
        let textSize = attributed.size()
        attributed.draw(in: CGRect(
            x: rect.minX,
            y: rect.midY - ceil(textSize.height) / 2,
            width: rect.width,
            height: ceil(textSize.height)
        ))
    }
}

private final class HyperlinkOpeningTextView: NSTextView {
    var openHyperlinkTarget: ((HyperlinkMarkdown.Target) -> Void)?
    var openHyperlinkTargetInNewWindow: ((HyperlinkMarkdown.Target) -> Void)?
    var shouldOpenHyperlinkAtIndex: ((Int) -> Bool)?
    var toggleTodoMarkerAtPoint: ((NSPoint) -> Bool)?
    var handleFrontmatterClickAtPoint: ((NSPoint) -> Bool)?
    var importImageFiles: (([URL], Int) -> Bool)?
    private var hyperlinkTrackingArea: NSTrackingArea?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if handleFrontmatterClickAtPoint?(point) == true {
            return
        }

        if toggleTodoMarkerAtPoint?(point) == true {
            return
        }

        if event.modifierFlags.contains(.command),
           let target = vaultDocumentHyperlinkTarget(at: point) {
            openHyperlinkTargetInNewWindow?(target)
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hyperlinkTrackingArea {
            removeTrackingArea(hyperlinkTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hyperlinkTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        updateHyperlinkCursor(at: point)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        let point = convert(event.locationInWindow, from: nil)
        updateHyperlinkCursor(at: point)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !imageFileURLs(from: sender.draggingPasteboard).isEmpty {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = imageFileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else {
            return super.performDragOperation(sender)
        }

        let point = convert(sender.draggingLocation, from: nil)
        let characterIndex = characterIndexForInsertion(at: point)
        return importImageFiles?(urls, characterIndex) ?? false
    }

    private func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        return urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
    }

    private func updateHyperlinkCursor(at point: NSPoint) {
        let characterIndex = characterIndexForInsertion(at: point)
        if shouldOpenHyperlinkAtIndex?(characterIndex) != false,
           HyperlinkMarkdown.target(at: characterIndex, in: string) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    private func vaultDocumentHyperlinkTarget(at point: NSPoint) -> HyperlinkMarkdown.Target? {
        let characterIndex = characterIndexForInsertion(at: point)
        guard shouldOpenHyperlinkAtIndex?(characterIndex) != false,
              let target = HyperlinkMarkdown.target(at: characterIndex, in: string),
              case .vaultDocument = target else {
            return nil
        }
        return target
    }
}

private final class FindHighlightOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct TextKit2EditorView: NSViewControllerRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?
    var vaultRootURL: URL?
    var onImportImageFile: ((URL) throws -> VaultImageAttachment)?
    var pageMentionProvider: ((String) -> [PageMentionDocument])?
    var onOpenDocumentLink: ((String) -> Void)?
    var onOpenDocumentLinkInNewWindow: ((String) -> Void)?
    var isFindVisible: Bool = false
    var findQuery: String = ""
    var findNavigationRequest: EditorFindNavigationRequest?
    var onFindStatusChange: ((EditorFindStatus) -> Void)?
    var onCloseFind: (() -> Void)?
    var onContentOffsetYChange: ((CGFloat) -> Void)?

    func makeCoordinator() -> TextKit2EditorCoordinator {
        TextKit2EditorCoordinator(text: $text, onTextChange: onTextChange, autoFocus: autoFocus)
    }

    func makeNSViewController(context: Context) -> TextKit2EditorViewController {
        let vc = TextKit2EditorViewController()
        vc.coordinator = context.coordinator
        vc.vaultRootURL = vaultRootURL
        vc.onImportImageFile = onImportImageFile
        vc.pageMentionProvider = pageMentionProvider
        vc.onOpenDocumentLink = onOpenDocumentLink
        vc.onOpenDocumentLinkInNewWindow = onOpenDocumentLinkInNewWindow
        vc.isFindVisible = isFindVisible
        vc.onCloseFind = onCloseFind
        vc.onContentOffsetYChange = onContentOffsetYChange
        vc.updateFind(
            query: findQuery,
            navigationRequest: findNavigationRequest,
            onStatusChange: onFindStatusChange
        )
        vc.loadText(text)
        return vc
    }

    func updateNSViewController(_ vc: TextKit2EditorViewController, context: Context) {
        vc.pageMentionProvider = pageMentionProvider
        vc.vaultRootURL = vaultRootURL
        vc.onImportImageFile = onImportImageFile
        vc.onOpenDocumentLink = onOpenDocumentLink
        vc.onOpenDocumentLinkInNewWindow = onOpenDocumentLinkInNewWindow
        vc.isFindVisible = isFindVisible
        vc.onCloseFind = onCloseFind
        vc.onContentOffsetYChange = onContentOffsetYChange
        vc.updateFind(
            query: findQuery,
            navigationRequest: findNavigationRequest,
            onStatusChange: onFindStatusChange
        )
        guard !context.coordinator.isUpdatingText else { return }
        guard text != context.coordinator.lastPublishedText else { return }
        let isFirstResponder = vc.textView.window?.firstResponder === vc.textView
        let currentText = vc.textView.string
        if currentText != text, !isFirstResponder || currentText.isEmpty {
            vc.loadText(text)
        }
    }
}

final class TextKit2EditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate, NSTextFieldDelegate, NSPopoverDelegate {
    var coordinator: TextKit2EditorCoordinator?
    var vaultRootURL: URL? {
        didSet {
            markdownDelegate.vaultRootURL = vaultRootURL
        }
    }
    var onImportImageFile: ((URL) throws -> VaultImageAttachment)?
    var pageMentionProvider: ((String) -> [PageMentionDocument])?
    var onOpenDocumentLink: ((String) -> Void)?
    var onOpenDocumentLinkInNewWindow: ((String) -> Void)?
    var isFindVisible = false
    var onCloseFind: (() -> Void)?
    var onContentOffsetYChange: ((CGFloat) -> Void)?
    private(set) var textView: NSTextView!
    private let scrollView = NSScrollView()
    private let markdownDelegate = MarkdownTextDelegate()
    private var pendingText: String?
    private var pageMentionSuggestionView: NSStackView?
    private var pageMentionSuggestionDocuments: [PageMentionDocument] = []
    private var selectedPageMentionSuggestionIndex = 0
    private var activePageMentionQuery: PageMentionQuery?
    private var strikethroughObserver: NSObjectProtocol?
    private var boldObserver: NSObjectProtocol?
    private var italicObserver: NSObjectProtocol?
    private var hyperlinkObserver: NSObjectProtocol?
    private var hyperlinkInsertionPopover: NSPopover?
    private var scrollBoundsObserver: NSObjectProtocol?
    private var revealedHyperlinkRanges: [NSRange] = []
    private var revealedDividerRanges: [NSRange] = []
    private var isRestylingText = false
    private var isOverlayRefreshScheduled = false
    private var isImageLayoutInvalidationScheduled = false
    private var lastOverlayLayoutSize: NSSize = .zero
    private let minimumHorizontalTextInset: CGFloat = 48
    private let maximumTextWidth: CGFloat = 600
    private let verticalTextInset: CGFloat = 16
    static let bottomScrollPadding: CGFloat = 48
    private var loadingImageURLs: Set<URL> = []
    private var findQuery = ""
    private var findMatches: [NSRange] = []
    private var selectedFindMatchIndex: Int?
    private var lastFindNavigationRequestID: Int?
    private var onFindStatusChange: ((EditorFindStatus) -> Void)?
    private var lastPublishedFindStatus = EditorFindStatus()
    private var findHighlightViews: [NSView] = []
    private var dividerLineViews: [Int: NSView] = [:]
    private var imageOverlayViews: [Int: NSImageView] = [:]
    private var isFrontmatterBlockExpanded = false
    private var frontmatterBlockView: FrontmatterBlockView?
    private weak var frontmatterEditingKeyField: NSTextField?
    private weak var frontmatterEditingField: NSTextField?
    private var frontmatterEditingTarget: FrontmatterEditingTarget?

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
        markdownDelegate.vaultRootURL = vaultRootURL
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
        textView.textContainerInset = NSSize(
            width: minimumHorizontalTextInset,
            height: editorTopTextInset
        )
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
        (textView as? HyperlinkOpeningTextView)?.openHyperlinkTargetInNewWindow = { [weak self] target in
            guard case .vaultDocument(let relativePath) = target else { return }
            self?.onOpenDocumentLinkInNewWindow?(relativePath)
        }
        (textView as? HyperlinkOpeningTextView)?.shouldOpenHyperlinkAtIndex = { [weak self] characterIndex in
            guard let self else { return true }
            return !self.revealedHyperlinkRanges.contains { NSLocationInRange(characterIndex, $0) }
        }
        (textView as? HyperlinkOpeningTextView)?.toggleTodoMarkerAtPoint = { [weak self] point in
            self?.toggleTodoMarker(atTextViewPoint: point) ?? false
        }
        (textView as? HyperlinkOpeningTextView)?.handleFrontmatterClickAtPoint = { [weak self] point in
            self?.handleFrontmatterClick(atTextViewPoint: point) ?? false
        }
        (textView as? HyperlinkOpeningTextView)?.importImageFiles = { [weak self] urls, characterIndex in
            self?.importAndInsertImages(fileURLs: urls, characterIndex: characterIndex) ?? false
        }
        textView.registerForDraggedTypes([.fileURL])

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: Self.bottomScrollPadding,
            right: 0
        )
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
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
        ) { [weak self] notification in
            guard self?.handlesWindowScopedCommand(notification) == true else { return }
            self?.handleStrikethroughCommand()
        }

        boldObserver = NotificationCenter.default.addObserver(
            forName: NoteEditorCommands.toggleBold,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard self?.handlesWindowScopedCommand(notification) == true else { return }
            self?.handleBoldCommand()
        }

        italicObserver = NotificationCenter.default.addObserver(
            forName: NoteEditorCommands.toggleItalic,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard self?.handlesWindowScopedCommand(notification) == true else { return }
            self?.handleItalicCommand()
        }

        hyperlinkObserver = NotificationCenter.default.addObserver(
            forName: NoteEditorCommands.toggleHyperlink,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard self?.handlesWindowScopedCommand(notification) == true else { return }
            self?.handleHyperlinkCommand()
        }

        scrollBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.publishContentOffsetY()
            self?.refreshEditorOverlays()
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

        let horizontalInset = ReadableTextColumnLayout.textHorizontalInset(
            for: visibleWidth,
            maximumTextWidth: maximumTextWidth,
            minimumHorizontalInset: minimumHorizontalTextInset,
            constrainsToReadableWidth: true
        )
        let targetInset = NSSize(
            width: horizontalInset,
            height: editorTopTextInset
        )
        guard textView.textContainerInset != targetInset else { return false }

        textView.textContainerInset = targetInset
        return true
    }

    private func updateFrontmatterMetadata(for markdown: String) {
        markdownDelegate.frontmatterRange = MarkdownFrontmatter.range(in: markdown)
        markdownDelegate.frontmatterDocument = EditableFrontmatterDocument(markdown: markdown)
    }

    private var frontmatterReservedHeight: CGFloat {
        markdownDelegate.frontmatterDocument == nil ? 0 : FrontmatterBlockLayout.reservedTopInset
    }

    private var editorTopTextInset: CGFloat {
        verticalTextInset + frontmatterReservedHeight
    }

    private func publishContentOffsetY() {
        onContentOffsetYChange?(scrollView.contentView.bounds.origin.y)
    }

    func loadText(_ markdown: String) {
        guard isViewLoaded, textView != nil else {
            pendingText = markdown
            return
        }
        applyText(markdown)
    }

    private func applyText(_ markdown: String) {
        isFrontmatterBlockExpanded = false
        updateFrontmatterMetadata(for: markdown)
        _ = syncTextContainerInsets()
        coordinator?.beginApplyingEditorText(markdown)
        textView.string = markdown
        coordinator?.finishApplyingEditorText()
        updateTypingAttributes()
        refreshFindMatches(preferredLocation: textView.selectedRange().location, scrollToSelection: false)
        if coordinator?.autoFocus == true {
            DispatchQueue.main.async { [weak self] in
                guard let tv = self?.textView else { return }
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: tv.string.count, length: 0))
                self?.refreshFindMatches(preferredLocation: tv.selectedRange().location, scrollToSelection: false)
                self?.scheduleEditorOverlayRefresh()
            }
        }
        scheduleEditorOverlayRefresh()
        updatePageMentionSuggestions()
    }

    func updateFind(
        query: String,
        navigationRequest: EditorFindNavigationRequest?,
        onStatusChange: ((EditorFindStatus) -> Void)?
    ) {
        self.onFindStatusChange = onStatusChange

        let normalizedQuery = EditorFindMatcher.normalizedQuery(query)
        let didChangeQuery = normalizedQuery != findQuery
        if didChangeQuery {
            findQuery = normalizedQuery
            refreshFindMatches(
                preferredLocation: textView?.selectedRange().location ?? 0,
                scrollToSelection: !normalizedQuery.isEmpty
            )
        } else if isViewLoaded, textView != nil {
            publishFindStatusIfNeeded()
        }

        guard let navigationRequest,
              navigationRequest.id != lastFindNavigationRequestID else {
            return
        }

        lastFindNavigationRequestID = navigationRequest.id
        navigateFind(to: navigationRequest.direction)
    }

    private func refreshFindMatches(preferredLocation: Int, scrollToSelection: Bool) {
        guard isViewLoaded, textView != nil else {
            publishFindStatusIfNeeded()
            return
        }

        restoreFindHighlightBackgrounds()
        findMatches = EditorFindMatcher.ranges(in: textView.string, query: findQuery)
        selectedFindMatchIndex = EditorFindMatcher.preferredIndex(
            for: findMatches,
            selectionLocation: preferredLocation
        )
        applyFindHighlights()
        publishFindStatusIfNeeded()

        if scrollToSelection {
            scrollToSelectedFindMatch()
        }
    }

    private func navigateFind(to direction: EditorFindNavigationDirection) {
        selectedFindMatchIndex = EditorFindMatcher.navigatedIndex(
            from: selectedFindMatchIndex,
            matchCount: findMatches.count,
            direction: direction
        )
        applyFindHighlights()
        publishFindStatusIfNeeded()
        scrollToSelectedFindMatch()
    }

    private func scrollToSelectedFindMatch() {
        guard let selectedFindMatchIndex,
              selectedFindMatchIndex < findMatches.count else {
            return
        }

        let range = findMatches[selectedFindMatchIndex]
        guard NSMaxRange(range) <= (textView.string as NSString).length else { return }
        textView.scrollRangeToVisible(range)
        refreshFindHighlightOverlays()
        scheduleEditorOverlayRefresh()
    }

    private func publishFindStatusIfNeeded() {
        let status = EditorFindStatus(
            matchCount: findMatches.count,
            selectedMatchIndex: selectedFindMatchIndex
        )
        guard status != lastPublishedFindStatus else { return }

        lastPublishedFindStatus = status
        onFindStatusChange?(status)
    }

    private func applyFindHighlights() {
        guard isViewLoaded, textView != nil else {
            return
        }

        restoreFindHighlightBackgrounds()
        guard !findMatches.isEmpty else { return }
        textView.needsDisplay = true
        refreshFindHighlightOverlays()
    }

    private func restoreFindHighlightBackgrounds() {
        clearFindHighlightOverlays()

        guard isViewLoaded, textView != nil else {
            return
        }
        textView.needsDisplay = true
    }

    private func refreshFindHighlightOverlays() {
        guard isViewLoaded, textView != nil else { return }
        clearFindHighlightOverlays()
        guard !findMatches.isEmpty else { return }

        let textLength = (textView.string as NSString).length
        for (index, range) in findMatches.enumerated() {
            guard range.location >= 0,
                  range.length > 0,
                  NSMaxRange(range) <= textLength else {
                continue
            }

            guard let highlightRect = textViewRectForFindRange(range) else { continue }
            let isActiveMatch = index == selectedFindMatchIndex
            let highlight = FindHighlightOverlayView(frame: highlightRect)
            highlight.wantsLayer = true
            highlight.layer?.cornerRadius = 2
            highlight.layer?.cornerCurve = .continuous
            highlight.layer?.backgroundColor = (isActiveMatch
                ? EditorFindHighlightPalette.currentMatchBackground
                : EditorFindHighlightPalette.matchBackground
            ).cgColor
            textView.addSubview(highlight)
            findHighlightViews.append(highlight)
        }
    }

    private func textViewRectForFindRange(_ range: NSRange) -> NSRect? {
        guard let window = textView.window else { return nil }

        let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
        guard !screenRect.isNull, isFiniteRect(screenRect) else { return nil }

        let windowRect = window.convertFromScreen(screenRect)
        let localRect = textView.convert(windowRect, from: nil)
        let highlightRect = NSRect(
            x: localRect.minX - 1,
            y: localRect.minY - 1,
            width: max(4, localRect.width + 2),
            height: max(12, localRect.height + 2)
        )
        guard isFiniteRect(highlightRect) else { return nil }
        return highlightRect
    }

    private func clearFindHighlightOverlays() {
        findHighlightViews.forEach { $0.removeFromSuperview() }
        findHighlightViews = []
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        DebugTrace.record("mac textDidChange")
        updateFrontmatterMetadata(for: textView.string)
        _ = syncTextContainerInsets()
        if !isRestylingText {
            updateRevealedMarkdownRangesForSelection(restyle: false)
            applyDividerRenderAttributesToTextStorage()
        }
        flushTextToBinding()
        updateTypingAttributes()
        scheduleEditorOverlayRefresh()
        updatePageMentionSuggestions()
        refreshFindMatches(preferredLocation: textView.selectedRange().location, scrollToSelection: false)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if !isRestylingText {
            updateRevealedMarkdownRangesForSelection(restyle: true)
        }
        updateTypingAttributes()
        updatePageMentionSuggestions()
    }

    func textDidEndEditing(_ notification: Notification) {
        DebugTrace.record("mac textDidEndEditing")
        flushTextToBinding(updateBinding: true)
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

    private func flushTextToBinding(updateBinding: Bool = false) {
        DebugTrace.record("mac flushTextToBinding \(DebugTrace.textSummary(textView.textStorage?.string ?? textView.string))")
        coordinator?.publishEditorText(textView.textStorage?.string ?? textView.string, updateBinding: updateBinding)
    }

    private func handlesWindowScopedCommand(_ notification: Notification) -> Bool {
        NotoCommandTarget.matches(notification, window: textView.window)
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
        if let transform = BlockEditingCommands.toggledHyperlink(
            in: textView.string,
            selection: textView.selectedRange()
        ) {
            applySelectionTransform(transform)
            return
        }

        guard let draft = BlockEditingCommands.hyperlinkInsertionDraft(
            in: textView.string,
            selection: textView.selectedRange()
        ) else {
            return
        }

        showHyperlinkInsertionPopover(for: draft)
    }

    private func showHyperlinkInsertionPopover(for draft: HyperlinkInsertionDraft) {
        hyperlinkInsertionPopover?.close()

        let contentViewController = HyperlinkInsertionPopoverViewController(draft: draft)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = contentViewController
        popover.delegate = self
        hyperlinkInsertionPopover = popover

        contentViewController.onCancel = { [weak self, weak popover] in
            popover?.close()
            self?.hyperlinkInsertionPopover = nil
            self?.textView.window?.makeFirstResponder(self?.textView)
        }
        contentViewController.onInsert = { [weak self, weak popover, draft] destination in
            guard let self else { return }
            if let transform = BlockEditingCommands.insertedHyperlink(
                in: self.textView.string,
                draft: draft,
                rawDestination: destination
            ) {
                self.applySelectionTransform(transform)
            }
            popover?.close()
            self.hyperlinkInsertionPopover = nil
            self.textView.window?.makeFirstResponder(self.textView)
        }

        let anchorRect = hyperlinkPopoverAnchorRect(for: draft.range)
        popover.show(relativeTo: anchorRect, of: textView, preferredEdge: .maxY)
    }

    private func hyperlinkPopoverAnchorRect(for range: NSRange) -> NSRect {
        guard let window = textView.window else {
            return textView.visibleRect
        }

        let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
        guard !screenRect.isNull, isFiniteRect(screenRect) else {
            return textView.visibleRect
        }

        let windowRect = window.convertFromScreen(screenRect)
        let localRect = textView.convert(windowRect, from: nil)
        guard isFiniteRect(localRect), localRect.width > 0, localRect.height > 0 else {
            return textView.visibleRect
        }
        return localRect
    }

    func popoverDidClose(_ notification: Notification) {
        hyperlinkInsertionPopover = nil
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

    private func importAndInsertImages(fileURLs: [URL], characterIndex: Int) -> Bool {
        guard let onImportImageFile else { return false }

        var markdownLines: [String] = []
        for fileURL in fileURLs {
            do {
                let attachment = try onImportImageFile(fileURL)
                markdownLines.append(attachment.markdown)
            } catch {
                logger.error("Failed to import dropped image \(fileURL.lastPathComponent): \(error)")
            }
        }

        guard !markdownLines.isEmpty else { return false }
        let markdown = markdownLines.joined(separator: "\n")
        let safeLocation = max(0, min(characterIndex, (textView.string as NSString).length))
        let transform = MarkdownImageInsertion.transform(
            in: textView.string,
            selection: NSRange(location: safeLocation, length: 0),
            markdown: markdown
        )
        applySelectionTransform(transform)
        textView.window?.makeFirstResponder(textView)
        return true
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
            let rowView = PageMentionSuggestionRowView(document: document, index: index)
            rowView.button.target = self
            rowView.button.action = #selector(pageMentionSuggestionClicked(_:))
            stackView.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(
                equalTo: stackView.widthAnchor,
                constant: -(stackView.edgeInsets.left + stackView.edgeInsets.right)
            ).isActive = true
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
        stackView.setAccessibilityIdentifier("page_mention_suggestions")
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
        let width = min(max(360, view.bounds.width * 0.45), view.bounds.width - horizontalMargin * 2)
        let height = pageMentionSuggestionPopoverHeight(for: stackView)
        let x = min(max(horizontalMargin, caretRect.minX), max(horizontalMargin, view.bounds.width - width - horizontalMargin))
        var y = caretRect.minY - height - 6
        if y < 8 {
            y = caretRect.maxY + 6
        }
        stackView.frame = NSRect(x: x, y: y, width: width, height: height)
    }

    private func pageMentionSuggestionPopoverHeight(for stackView: NSStackView) -> CGFloat {
        let rowCount = max(1, min(pageMentionSuggestionDocuments.count, 5))
        let rowHeight: CGFloat = 44
        let contentHeight = CGFloat(rowCount) * rowHeight
        let spacingHeight = CGFloat(max(rowCount - 1, 0)) * stackView.spacing
        return stackView.edgeInsets.top + contentHeight + spacingHeight + stackView.edgeInsets.bottom
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
        for rowView in pageMentionSuggestionRows(in: stackView) {
            rowView.backgroundView.layer?.backgroundColor = rowView.button.tag == selectedPageMentionSuggestionIndex
                ? AppTheme.nsSeparator.withAlphaComponent(0.75).cgColor
                : NSColor.clear.cgColor
        }
    }

    private func pageMentionSuggestionButtons(in stackView: NSStackView) -> [NSButton] {
        pageMentionSuggestionRows(in: stackView).map(\.button)
    }

    private func pageMentionSuggestionRows(in stackView: NSStackView) -> [PageMentionSuggestionRowView] {
        stackView.arrangedSubviews.compactMap { arrangedSubview in
            arrangedSubview as? PageMentionSuggestionRowView
        }
    }

    private final class PageMentionSuggestionRowView: NSView {
        let backgroundView = NSView()
        let button = NSButton(title: "", target: nil, action: nil)

        init(document: PageMentionDocument, index: Int) {
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            wantsLayer = true

            let titleLabel = NSTextField(labelWithString: document.title)
            titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            titleLabel.textColor = AppTheme.nsPrimaryText
            titleLabel.alignment = .left
            titleLabel.lineBreakMode = .byTruncatingTail

            let subtitleLabel = NSTextField(labelWithString: document.relativePath)
            subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            subtitleLabel.textColor = AppTheme.nsMutedText
            subtitleLabel.alignment = .left
            subtitleLabel.lineBreakMode = .byTruncatingTail

            let textStack = NSStackView(views: [titleLabel, subtitleLabel])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 2
            textStack.translatesAutoresizingMaskIntoConstraints = false

            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.wantsLayer = true
            backgroundView.layer?.cornerRadius = 6
            backgroundView.layer?.cornerCurve = .continuous
            addSubview(backgroundView)
            backgroundView.addSubview(textStack)

            button.tag = index
            button.isBordered = false
            button.title = ""
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setAccessibilityIdentifier("page_mention_suggestion_\(index)")
            button.setAccessibilityLabel("Mention \(document.title), \(document.relativePath)")
            backgroundView.addSubview(button)

            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 44),
                backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
                backgroundView.topAnchor.constraint(equalTo: topAnchor),
                backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

                textStack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 12),
                textStack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -12),
                textStack.topAnchor.constraint(greaterThanOrEqualTo: backgroundView.topAnchor, constant: 6),
                textStack.bottomAnchor.constraint(lessThanOrEqualTo: backgroundView.bottomAnchor, constant: -6),
                textStack.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),

                button.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
                button.topAnchor.constraint(equalTo: backgroundView.topAnchor),
                button.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
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

        if commandSelector == #selector(NSResponder.cancelOperation(_:)),
           isFindVisible {
            onCloseFind?()
            return true
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

    private func setRevealedDividerRanges(_ ranges: [NSRange]) {
        revealedDividerRanges = ranges
        markdownDelegate.revealedDividerRanges = ranges
    }

    private func updateRevealedMarkdownRangesForSelection(restyle: Bool) {
        let hyperlinkRanges = hyperlinkRangesOnSelectedLines(in: textView.string, selection: textView.selectedRange())
        let dividerRanges = dividerRangesOnSelectedLines(in: textView.string, selection: textView.selectedRange())
        let changed = !nsRangesEqual(hyperlinkRanges, revealedHyperlinkRanges)
            || !nsRangesEqual(dividerRanges, revealedDividerRanges)
        guard changed else { return }

        setRevealedHyperlinkRanges(hyperlinkRanges)
        setRevealedDividerRanges(dividerRanges)
        if restyle {
            restyleTextPreservingSelection()
        } else {
            applyDividerRenderAttributesToTextStorage()
            scheduleEditorOverlayRefresh()
        }
    }

    private func hyperlinkRangesOnSelectedLines(in text: String, selection: NSRange) -> [NSRange] {
        HyperlinkSelectionRanges.fullRangesOnSelectedLines(in: text, selection: selection)
    }

    private func dividerRangesOnSelectedLines(in text: String, selection: NSRange) -> [NSRange] {
        DividerMarkdown.rangesOnSelectedLines(in: text, selection: selection)
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
        applyDividerRenderAttributesToTextStorage()
        applyFindHighlights()
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

    private func applyDividerRenderAttributesToTextStorage() {
        guard let textStorage = textView.textStorage else { return }
        let blocks = MarkdownSemanticAnalyzer.renderableBlocks(
            in: textView.string,
            collapsedXMLTagRanges: markdownDelegate.collapsedXMLTagRanges
        )

        for block in blocks where block.kind == .divider && !block.isCollapsedXMLTagContent {
            guard block.visibleLineRange.length > 0,
                  NSMaxRange(block.visibleLineRange) <= textStorage.length else {
                continue
            }

            let isRevealed = revealedDividerRanges.contains { NSEqualRanges($0, block.visibleLineRange) }
            textStorage.addAttributes([
                .font: MarkdownTheme.bodyFont,
                .foregroundColor: isRevealed ? MarkdownTheme.bodyColor : NSColor.clear,
                .paragraphStyle: MarkdownParagraphStyler.paragraphStyle(
                    for: isRevealed ? .paragraph : .divider,
                    text: block.lineText
                ),
            ], range: block.visibleLineRange)
        }
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
        refreshFrontmatterBlockView()
        refreshFrontmatterEditingFieldFrame()
        refreshDividerLineViews()
        refreshImageOverlayViews()
        refreshFindHighlightOverlays()
    }

    private func syncCollapsedXMLTagState() {
        markdownDelegate.collapsedXMLTagRanges = []
    }

    private struct FrontmatterControlLayout {
        let document: EditableFrontmatterDocument
        let blockRect: NSRect
    }

    private func frontmatterControlLayout() -> FrontmatterControlLayout? {
        guard let document = markdownDelegate.frontmatterDocument else {
            return nil
        }

        let inset = textView.textContainerInset.width
        let padding = textView.textContainer?.lineFragmentPadding ?? 0
        let contentLeading = inset + padding
        let contentTrailing = textView.bounds.width - inset - padding
        let leading = max(0, contentLeading - FrontmatterBlockLayout.horizontalPadding)
        let trailing = min(textView.bounds.width, contentTrailing + FrontmatterBlockLayout.horizontalPadding)
        let width = max(0, trailing - leading)
        guard width > 0 else { return nil }

        let blockRect = FrontmatterBlockLayout.blockRect(
            point: CGPoint(x: leading, y: verticalTextInset),
            contentWidth: width,
            document: document,
            isExpanded: isFrontmatterBlockExpanded
        )
        return FrontmatterControlLayout(document: document, blockRect: blockRect)
    }

    private func handleFrontmatterClick(atTextViewPoint point: NSPoint) -> Bool {
        finishFrontmatterEditing(commit: true)
        guard let layout = frontmatterControlLayout(),
              layout.blockRect.contains(point) else {
            if isFrontmatterBlockExpanded {
                isFrontmatterBlockExpanded = false
                invalidateFrontmatterLayout()
            }
            return false
        }

        if FrontmatterBlockLayout.headerRect(in: layout.blockRect).contains(point) {
            toggleFrontmatterBlockExpansion()
            return true
        }

        guard let rowIndex = FrontmatterBlockLayout.rowIndex(
            at: point,
            in: layout.blockRect,
            document: layout.document,
            isExpanded: isFrontmatterBlockExpanded
        ) else {
            return true
        }

        let rowRect = FrontmatterBlockLayout.rowRect(at: rowIndex, in: layout.blockRect)

        if rowIndex == FrontmatterBlockLayout.newFieldRowIndex(for: layout.document) {
            beginEditingNewFrontmatterField()
            return true
        }

        let field = layout.document.fields[rowIndex]
        if FrontmatterBlockLayout.deleteRect(for: rowRect).insetBy(dx: -6, dy: -6).contains(point) {
            deleteFrontmatterField(field)
            return true
        }

        let isURLField = field.url != nil
        if isURLField,
           FrontmatterBlockLayout.editRect(for: rowRect).insetBy(dx: -6, dy: -6).contains(point) {
            beginEditingFrontmatterField(field)
            return true
        }

        let valueRect = FrontmatterBlockLayout.valueRect(
            for: rowRect,
            blockWidth: layout.blockRect.width,
            hasEditControl: isURLField
        ).insetBy(dx: -4, dy: -5)
        guard valueRect.contains(point) else { return true }

        if let url = field.url {
            NSWorkspace.shared.open(url)
            return true
        }
        beginEditingFrontmatterField(field)
        return true
    }

    private func toggleFrontmatterBlockExpansion() {
        isFrontmatterBlockExpanded.toggle()
        invalidateFrontmatterLayout()
    }

    private func refreshFrontmatterBlockView() {
        guard let layout = frontmatterControlLayout(),
              layout.blockRect.intersects(textView.visibleRect.insetBy(dx: -8, dy: -80)) else {
            frontmatterBlockView?.removeFromSuperview()
            frontmatterBlockView = nil
            return
        }

        let blockView = frontmatterBlockView ?? FrontmatterBlockView()
        blockView.frame = layout.blockRect
        blockView.configure(
            document: layout.document,
            isExpanded: isFrontmatterBlockExpanded,
            editingTarget: frontmatterEditingTarget
        )
        if blockView.superview !== textView {
            textView.addSubview(blockView, positioned: .above, relativeTo: nil)
        }
        frontmatterBlockView = blockView
    }

    private func beginEditingFrontmatterField(_ field: EditableFrontmatterField) {
        guard let layout = frontmatterControlLayout(),
              let valueRect = frontmatterEditingFrame(for: .existingValue(key: field.key), in: layout) else {
            return
        }

        frontmatterEditingKeyField?.removeFromSuperview()
        frontmatterEditingKeyField = nil
        frontmatterEditingField?.removeFromSuperview()
        let textField = makeFrontmatterTextField(
            frame: valueRect,
            string: field.value,
            placeholder: nil
        )
        textField.setAccessibilityIdentifier("frontmatter_value_editor_\(field.key)")
        textView.addSubview(textField)
        frontmatterEditingField = textField
        frontmatterEditingTarget = .existingValue(key: field.key)
        frontmatterBlockView?.configure(
            document: layout.document,
            isExpanded: isFrontmatterBlockExpanded,
            editingTarget: frontmatterEditingTarget
        )
        textView.window?.makeFirstResponder(textField)
        textField.currentEditor()?.selectAll(nil)
    }

    private func beginEditingNewFrontmatterField() {
        guard let layout = frontmatterControlLayout(),
              let keyRect = frontmatterNewKeyEditingFrame(in: layout),
              let valueRect = frontmatterEditingFrame(for: .newField, in: layout) else {
            return
        }

        frontmatterEditingKeyField?.removeFromSuperview()
        frontmatterEditingField?.removeFromSuperview()
        let keyField = makeFrontmatterTextField(frame: keyRect, string: "", placeholder: "key")
        keyField.setAccessibilityIdentifier("frontmatter_new_key_editor")
        let valueField = makeFrontmatterTextField(frame: valueRect, string: "", placeholder: "value")
        valueField.setAccessibilityIdentifier("frontmatter_new_value_editor")
        textView.addSubview(keyField)
        textView.addSubview(valueField)
        frontmatterEditingKeyField = keyField
        frontmatterEditingField = valueField
        frontmatterEditingTarget = .newField
        frontmatterBlockView?.configure(
            document: layout.document,
            isExpanded: isFrontmatterBlockExpanded,
            editingTarget: .newField
        )
        textView.window?.makeFirstResponder(keyField)
    }

    private func makeFrontmatterTextField(
        frame: CGRect,
        string: String,
        placeholder: String?
    ) -> NSTextField {
        let textField = NSTextField(frame: frame)
        let cell = VerticallyCenteredTextFieldCell(textCell: string)
        cell.isEditable = true
        cell.isSelectable = true
        cell.isBordered = false
        cell.drawsBackground = true
        cell.backgroundColor = FrontmatterBlockLayout.nsFieldBackgroundColor
        cell.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        cell.textColor = AppTheme.nsPrimaryText
        cell.usesSingleLineMode = true
        cell.lineBreakMode = .byTruncatingTail
        cell.wraps = false
        cell.isScrollable = true
        cell.focusRingType = .none
        if let placeholder {
            cell.placeholderString = placeholder
        }
        textField.cell = cell
        textField.stringValue = string
        textField.delegate = self
        textField.wantsLayer = true
        textField.layer?.cornerRadius = 4
        textField.layer?.masksToBounds = true
        return textField
    }

    private func frontmatterEditingFrame(
        for target: FrontmatterEditingTarget,
        in layout: FrontmatterControlLayout
    ) -> CGRect? {
        let rowIndex: Int
        let hasEditControl: Bool
        switch target {
        case .existingValue(let key):
            guard let index = layout.document.fields.firstIndex(where: { $0.key == key }) else { return nil }
            rowIndex = index
            hasEditControl = layout.document.fields[index].url != nil
        case .newField:
            rowIndex = FrontmatterBlockLayout.newFieldRowIndex(for: layout.document)
            hasEditControl = false
        }

        let rowRect = FrontmatterBlockLayout.rowRect(at: rowIndex, in: layout.blockRect)
        return FrontmatterBlockLayout.valueRect(
            for: rowRect,
            blockWidth: layout.blockRect.width,
            hasEditControl: hasEditControl
        ).insetBy(dx: 0, dy: 6)
    }

    private func frontmatterNewKeyEditingFrame(in layout: FrontmatterControlLayout) -> CGRect? {
        let rowRect = FrontmatterBlockLayout.rowRect(
            at: FrontmatterBlockLayout.newFieldRowIndex(for: layout.document),
            in: layout.blockRect
        )
        return FrontmatterBlockLayout.keyRect(for: rowRect, blockWidth: layout.blockRect.width)
            .insetBy(dx: 0, dy: 6)
    }

    private func finishFrontmatterEditing(commit: Bool) {
        guard let textField = frontmatterEditingField,
              let target = frontmatterEditingTarget else {
            return
        }

        let value = textField.stringValue
        let keyValue = frontmatterEditingKeyField?.stringValue ?? ""
        frontmatterEditingKeyField?.removeFromSuperview()
        frontmatterEditingKeyField = nil
        textField.removeFromSuperview()
        frontmatterEditingField = nil
        frontmatterEditingTarget = nil

        guard commit else { return }

        let updatedText: String
        switch target {
        case .existingValue(let key):
            updatedText = EditableFrontmatterDocument.updatingField(key: key, value: value, in: textView.string)
        case .newField:
            guard let parsed = EditableFrontmatterDocument.parsedFieldInput(key: keyValue, value: value) else { return }
            updatedText = EditableFrontmatterDocument.addingField(key: parsed.key, value: parsed.value, in: textView.string)
        }
        guard updatedText != textView.string else { return }

        let selectedRange = textView.selectedRange()
        let updatedLength = (updatedText as NSString).length
        let selectionLocation = min(selectedRange.location, updatedLength)
        let selection = NSRange(
            location: selectionLocation,
            length: min(selectedRange.length, max(0, updatedLength - selectionLocation))
        )
        applySelectionTransform(TextSelectionTransform(text: updatedText, selection: selection))
        updateFrontmatterMetadata(for: updatedText)
        invalidateFrontmatterLayout()
    }

    private func deleteFrontmatterField(_ field: EditableFrontmatterField) {
        let currentText = textView.string
        let updatedText = EditableFrontmatterDocument.deletingField(key: field.key, in: currentText)
        guard updatedText != currentText else { return }

        let selectedRange = textView.selectedRange()
        let updatedLength = (updatedText as NSString).length
        let selectionLocation = min(selectedRange.location, updatedLength)
        let selection = NSRange(
            location: selectionLocation,
            length: min(selectedRange.length, max(0, updatedLength - selectionLocation))
        )
        applySelectionTransform(TextSelectionTransform(text: updatedText, selection: selection))
        updateFrontmatterMetadata(for: updatedText)
        invalidateFrontmatterLayout()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let endingField = obj.object as? NSTextField
        guard endingField === frontmatterEditingField || endingField === frontmatterEditingKeyField else { return }

        // If user tabbed/shifted between key and value fields, keep editing alive.
        if let movement = obj.userInfo?["NSTextMovement"] as? Int,
           movement == NSTextMovement.tab.rawValue,
           endingField === frontmatterEditingKeyField,
           let valueField = frontmatterEditingField {
            textView.window?.makeFirstResponder(valueField)
            return
        }

        finishFrontmatterEditing(commit: true)
    }

    private func refreshFrontmatterEditingFieldFrame() {
        guard let editingField = frontmatterEditingField,
              let editingTarget = frontmatterEditingTarget,
              let layout = frontmatterControlLayout(),
              let editingFrame = frontmatterEditingFrame(for: editingTarget, in: layout),
              isFrontmatterBlockExpanded else {
            return
        }

        editingField.frame = editingFrame
        if let keyField = frontmatterEditingKeyField,
           let keyFrame = frontmatterNewKeyEditingFrame(in: layout) {
            keyField.frame = keyFrame
        }
    }

    private func invalidateFrontmatterLayout() {
        _ = syncTextContainerInsets()
        textView.needsDisplay = true
        scheduleEditorOverlayRefresh()
    }

    private func requestImageLoad(for url: URL) {
        guard loadingImageURLs.insert(url).inserted else { return }

        MarkdownImageLoader.load(url: url) { [weak self] image in
            guard let self else { return }
            self.loadingImageURLs.remove(url)
            if image != nil {
                self.scheduleImageLayoutInvalidation()
            }
        }
    }

    private func scheduleImageLayoutInvalidation() {
        guard !isImageLayoutInvalidationScheduled else { return }
        isImageLayoutInvalidationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isImageLayoutInvalidationScheduled = false
            self.invalidateImageLayouts()
        }
    }

    private func invalidateImageLayouts() {
        guard isViewLoaded,
              let textView,
              let textLayoutManager = textView.textLayoutManager else {
            return
        }
        textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
        textView.needsDisplay = true
        refreshImageOverlayViews()
    }

    private func refreshImageOverlayViews() {
        guard isViewLoaded, textView != nil else { return }
        clearImageOverlayViews()
        textView.needsDisplay = true
    }

    private func clearImageOverlayViews() {
        for (_, view) in imageOverlayViews {
            view.removeFromSuperview()
        }
        imageOverlayViews.removeAll()
    }

    private func refreshDividerLineViews() {
        guard isViewLoaded, textView != nil else { return }

        let blocks = MarkdownSemanticAnalyzer.renderableBlocks(
            in: textView.string,
            collapsedXMLTagRanges: markdownDelegate.collapsedXMLTagRanges
        )
        let visibleRect = textView.visibleRect.insetBy(dx: -8, dy: -80)
        var activeLocations: Set<Int> = []

        for block in blocks {
            guard block.kind == .divider,
                  !block.isCollapsedXMLTagContent,
                  !revealedDividerRanges.contains(where: { NSEqualRanges($0, block.visibleLineRange) }),
                  let rect = dividerLineRect(for: block),
                  rect.intersects(visibleRect) else {
                continue
            }

            activeLocations.insert(block.paragraphRange.location)

            let lineView = dividerLineViews[block.paragraphRange.location] ?? makeDividerLineView()
            lineView.frame = rect.integral
            if lineView.superview !== textView {
                textView.addSubview(lineView)
            }
            dividerLineViews[block.paragraphRange.location] = lineView
        }

        for (location, lineView) in dividerLineViews where !activeLocations.contains(location) {
            lineView.removeFromSuperview()
            dividerLineViews.removeValue(forKey: location)
        }
    }

    private func makeDividerLineView() -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = AppTheme.nsMutedText.withAlphaComponent(0.45).cgColor
        view.layer?.cornerRadius = MarkdownVisualSpec.dividerLineHeight / 2
        return view
    }

    private func dividerLineRect(for block: MarkdownRenderableBlock) -> NSRect? {
        let screenRect = textView.firstRect(
            forCharacterRange: NSRange(location: block.visibleLineRange.location, length: 0),
            actualRange: nil
        )
        guard let window = textView.window,
              isFiniteRect(screenRect) else {
            return nil
        }

        let windowRect = window.convertFromScreen(screenRect)
        let caretRect = textView.convert(windowRect, from: nil)
        guard isFiniteRect(caretRect) else { return nil }

        let inset = textView.textContainerInset.width
        let padding = textView.textContainer?.lineFragmentPadding ?? 0
        let leading = inset + padding
        let trailing = textView.bounds.width - inset - padding
        let y = caretRect.midY - MarkdownVisualSpec.dividerLineHeight / 2
        return NSRect(
            x: leading,
            y: y,
            width: max(0, trailing - leading),
            height: MarkdownVisualSpec.dividerLineHeight
        )
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
        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
        }
    }
}

#endif
