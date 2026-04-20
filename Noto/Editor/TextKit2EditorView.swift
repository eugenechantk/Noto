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

    static func requestToggleStrikethrough() {
        NotificationCenter.default.post(name: toggleStrikethrough, object: nil)
    }
}

// MARK: - Platform Aliases

#if os(iOS)
private typealias PlatformFont = UIFont
private typealias PlatformColor = UIColor
#elseif os(macOS)
private typealias PlatformFont = NSFont
private typealias PlatformColor = NSColor
#endif

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

    static func detect(from text: String) -> MarkdownBlockKind {
        let indentCount = text.prefix(while: { $0 == " " }).count
        let indent = indentCount / 2
        let stripped = String(text.dropFirst(indentCount))

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
        case .frontmatter, .paragraph: return 0
        }
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
    static let todoTextStartOffset: CGFloat = 28
    static let todoControlSize: CGFloat = 28
    static let todoSymbolSize: CGFloat = 18
    static let todoControlLeadingInset: CGFloat = 2
    static let todoControlImageLeadingInset: CGFloat = 5

    static func listLeadingOffset(for indentLevel: Int) -> CGFloat {
        listBaseIndent + CGFloat(indentLevel) * listIndentStep
    }

    static func font(for kind: MarkdownBlockKind) -> Font {
        switch kind {
        case .heading(1): return h1Font
        case .heading(2): return h2Font
        case .heading(3): return h3Font
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
    #elseif os(macOS)
    static let bodyColor: PlatformColor = AppTheme.nsPrimaryText
    static let prefixColor: PlatformColor = AppTheme.nsMutedText
    static let checkedColor: PlatformColor = AppTheme.nsSecondaryText
    static let codeColor: PlatformColor = AppTheme.nsSecondaryText
    static let codeBgColor: PlatformColor = AppTheme.nsCodeBackground
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

    static func style(text: String, kind: MarkdownBlockKind) -> NSAttributedString {
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

        case .paragraph:
            attributed.addAttributes([
                .font: MarkdownTheme.bodyFont,
                .foregroundColor: MarkdownTheme.bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
        }

        // Dim prefix characters. Todo prefixes stay in the backing markdown but
        // are hidden because an interactive circle is overlaid in their place.
        let pfxLen = kind.prefixLength(in: text)
        if pfxLen > 0 && pfxLen <= fullRange.length {
            let prefixColor: PlatformColor
            if case .todo = kind {
                prefixColor = .clear
                attributed.addAttribute(
                    .font,
                    value: PlatformFont.systemFont(ofSize: MarkdownTheme.todoPrefixVisualWidth, weight: .regular),
                    range: NSRange(location: 0, length: pfxLen)
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

        return attributed
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
                    .foregroundColor: MarkdownTheme.checkedColor,
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

// MARK: - MarkdownTextDelegate

/// The heart of the TextKit 2 integration.
///
/// Implements **NSTextContentStorageDelegate** to intercept paragraph creation.
/// For each paragraph the content storage builds, we return a styled
/// `MarkdownParagraph` with the correct fonts, colors, and indentation.
/// Only the *changed* paragraph is re-styled — not the whole document.
final class MarkdownTextDelegate: NSObject, NSTextContentStorageDelegate, NSTextLayoutManagerDelegate {

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
        if MarkdownFrontmatter.contains(position: range.location, in: textStorage.string) {
            kind = .frontmatter
        } else {
            kind = MarkdownBlockKind.detect(from: text)
        }

        // Style the visible text
        let styled = MarkdownParagraphStyler.style(text: text, kind: kind)

        // Re-append the trailing newline so the paragraph's character count
        // matches the backing-store range that TextKit expects.
        let result = NSMutableAttributedString(attributedString: styled)
        if original.hasSuffix("\n") {
            let nlAttrs: [NSAttributedString.Key: Any] = [
                .font: MarkdownTheme.font(for: kind),
                .foregroundColor: MarkdownTheme.bodyColor,
                .paragraphStyle: MarkdownParagraphStyler.paragraphStyle(for: kind, text: text),
            ]
            result.append(NSAttributedString(string: "\n", attributes: nlAttrs))
        }

        return MarkdownParagraph(attributedString: result, blockKind: kind)
    }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        guard let paragraph = textElement as? MarkdownParagraph,
              paragraph.blockKind == .frontmatter else {
            return NSTextLayoutFragment(textElement: textElement, range: nil)
        }

        return HiddenFrontmatterLayoutFragment(textElement: textElement, range: nil)
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

struct TextKit2EditorView: UIViewControllerRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> TextKit2EditorCoordinator {
        TextKit2EditorCoordinator(text: $text, onTextChange: onTextChange, autoFocus: autoFocus)
    }

    func makeUIViewController(context: Context) -> TextKit2EditorViewController {
        let vc = TextKit2EditorViewController()
        vc.coordinator = context.coordinator
        vc.loadText(text)
        return vc
    }

    func updateUIViewController(_ vc: TextKit2EditorViewController, context: Context) {
        guard !context.coordinator.isUpdatingText else { return }
        guard !vc.textView.isFirstResponder else { return }
        let currentText = vc.textView.text ?? ""
        if currentText != text {
            vc.loadText(text)
        }
    }
}

final class TextKit2EditorViewController: UIViewController, UITextViewDelegate {
    var coordinator: TextKit2EditorCoordinator?
    private(set) var textView: UITextView!
    private let markdownDelegate = MarkdownTextDelegate()
    private var pendingText: String?
    private var todoCheckboxButtons: [UIButton] = []

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
        textView.translatesAutoresizingMaskIntoConstraints = false
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshTodoCheckboxes()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
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
        ]
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
                self?.refreshTodoCheckboxes()
            }
        }
        scheduleTodoCheckboxRefresh()
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
        button.addTarget(self, action: action, for: .primaryActionTriggered)
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
        scheduleTodoCheckboxRefresh()
    }

    // MARK: UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
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
        coordinator?.publishEditorText(textView.text ?? "")
        scheduleTodoCheckboxRefresh()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        updateTypingAttributes()
        scheduleTodoCheckboxRefresh()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        coordinator?.publishEditorText(textView.text ?? "")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        coordinator?.publishEditorText(textView.text ?? "")
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
        refreshTodoCheckboxes()
    }

    private func scheduleTodoCheckboxRefresh() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshTodoCheckboxes()
        }
    }

    private func refreshTodoCheckboxes() {
        guard isViewLoaded, textView != nil else { return }

        todoCheckboxButtons.forEach { $0.removeFromSuperview() }
        todoCheckboxButtons.removeAll()

        let nsText = (textView.text ?? "") as NSString
        guard nsText.length > 0 else { return }

        textView.layoutIfNeeded()

        var paragraphLocation = 0
        while paragraphLocation < nsText.length {
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: paragraphLocation, length: 0))
            let lineRange = MarkdownLineRanges.visibleLineRange(from: paragraphRange, in: nsText)
            let lineText = nsText.substring(with: lineRange)
            let kind = MarkdownBlockKind.detect(from: lineText)

            if case .todo(let checked, let indent) = kind {
                addTodoCheckbox(
                    checked: checked,
                    indent: indent,
                    paragraphLocation: paragraphRange.location,
                    lineText: lineText
                )
            }

            let nextLocation = NSMaxRange(paragraphRange)
            guard nextLocation > paragraphLocation else { break }
            paragraphLocation = nextLocation
        }
    }

    private func addTodoCheckbox(
        checked: Bool,
        indent: Int,
        paragraphLocation: Int,
        lineText: String
    ) {
        let prefixLength = MarkdownBlockKind.detect(from: lineText).prefixLength(in: lineText)
        let contentLocation = paragraphLocation + prefixLength
        guard let contentPosition = textView.position(from: textView.beginningOfDocument, offset: contentLocation) else {
            return
        }

        let caretRect = textView.caretRect(for: contentPosition)
        guard !caretRect.isNull,
              caretRect.origin.x.isFinite,
              caretRect.origin.y.isFinite,
              caretRect.size.width.isFinite,
              caretRect.size.height.isFinite else {
            return
        }

        let buttonSize = MarkdownVisualSpec.todoControlSize
        let symbolSize = MarkdownVisualSpec.todoSymbolSize
        let contentLeading = caretRect.minX
        let indentLeading = textView.textContainerInset.left + MarkdownTheme.listLeadingOffset(for: indent)
        let buttonLeading = max(0, indentLeading - MarkdownVisualSpec.todoControlLeadingInset)
        let buttonWidth = max(buttonSize, contentLeading - buttonLeading - 2)
        let centerY = caretRect.midY

        let button = UIButton(type: .system)
        let imageName = checked ? "checkmark.circle.fill" : "circle"
        let config = UIImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)
        button.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
        button.tintColor = checked ? AppTheme.uiSecondaryText : AppTheme.uiMutedText
        button.backgroundColor = textView.backgroundColor ?? AppTheme.uiBackground
        button.contentHorizontalAlignment = .left
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: MarkdownVisualSpec.todoControlImageLeadingInset, bottom: 0, right: 0)
        button.tag = paragraphLocation
        button.accessibilityIdentifier = "todo_checkbox_\(paragraphLocation)"
        button.accessibilityLabel = checked ? "Mark todo incomplete" : "Mark todo complete"
        button.frame = CGRect(
            x: buttonLeading,
            y: centerY - buttonSize / 2,
            width: buttonWidth,
            height: buttonSize
        )
        button.addTarget(self, action: #selector(todoCheckboxTapped(_:)), for: .touchUpInside)

        textView.addSubview(button)
        todoCheckboxButtons.append(button)
    }

    @objc
    private func todoCheckboxTapped(_ sender: UIButton) {
        toggleTodoCheckbox(atParagraphLocation: sender.tag)
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

struct TextKit2EditorView: NSViewControllerRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> TextKit2EditorCoordinator {
        TextKit2EditorCoordinator(text: $text, onTextChange: onTextChange, autoFocus: autoFocus)
    }

    func makeNSViewController(context: Context) -> TextKit2EditorViewController {
        let vc = TextKit2EditorViewController()
        vc.coordinator = context.coordinator
        vc.loadText(text)
        return vc
    }

    func updateNSViewController(_ vc: TextKit2EditorViewController, context: Context) {
        guard !context.coordinator.isUpdatingText else { return }
        guard vc.textView.window?.firstResponder !== vc.textView else { return }
        if vc.textView.string != text {
            vc.loadText(text)
        }
    }
}

final class TextKit2EditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate {
    var coordinator: TextKit2EditorCoordinator?
    private(set) var textView: NSTextView!
    private let scrollView = NSScrollView()
    private let markdownDelegate = MarkdownTextDelegate()
    private var pendingText: String?
    private var todoCheckboxButtons: [NSButton] = []
    private var strikethroughObserver: NSObjectProtocol?

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

        // Create NSTextView backed by the TextKit 2 container
        textView = NSTextView(frame: .zero, textContainer: container)
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
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.setAccessibilityIdentifier("note_editor")

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
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        refreshTodoCheckboxes()
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
                self?.refreshTodoCheckboxes()
            }
        }
        scheduleTodoCheckboxRefresh()
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        DebugTrace.record("mac textDidChange")
        flushTextToBinding()
        scheduleTodoCheckboxRefresh()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateTypingAttributes()
        scheduleTodoCheckboxRefresh()
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
        scheduleTodoCheckboxRefresh()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            handleIndentCommand()
            return true
        }

        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            handleOutdentCommand()
            return true
        }

        return false
    }

    private func scheduleTodoCheckboxRefresh() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshTodoCheckboxes()
        }
    }

    private func refreshTodoCheckboxes() {
        guard isViewLoaded, textView != nil else { return }

        todoCheckboxButtons.forEach { $0.removeFromSuperview() }
        todoCheckboxButtons.removeAll()

        let nsText = textView.string as NSString
        guard nsText.length > 0 else { return }

        textView.layoutSubtreeIfNeeded()

        var paragraphLocation = 0
        while paragraphLocation < nsText.length {
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: paragraphLocation, length: 0))
            let lineRange = MarkdownLineRanges.visibleLineRange(from: paragraphRange, in: nsText)
            let lineText = nsText.substring(with: lineRange)
            let kind = MarkdownBlockKind.detect(from: lineText)

            if case .todo(let checked, let indent) = kind {
                addTodoCheckbox(
                    checked: checked,
                    indent: indent,
                    paragraphLocation: paragraphRange.location,
                    lineText: lineText
                )
            }

            let nextLocation = NSMaxRange(paragraphRange)
            guard nextLocation > paragraphLocation else { break }
            paragraphLocation = nextLocation
        }
    }

    private func addTodoCheckbox(
        checked: Bool,
        indent: Int,
        paragraphLocation: Int,
        lineText: String
    ) {
        let prefixLength = MarkdownBlockKind.detect(from: lineText).prefixLength(in: lineText)
        let contentLocation = paragraphLocation + prefixLength
        let screenRect = textView.firstRect(
            forCharacterRange: NSRange(location: contentLocation, length: 0),
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

        let buttonSize = MarkdownVisualSpec.todoControlSize
        let symbolSize = MarkdownVisualSpec.todoSymbolSize
        let contentLeading = caretRect.minX
        let indentLeading = textView.textContainerInset.width + MarkdownTheme.listLeadingOffset(for: indent)
        let buttonLeading = max(0, indentLeading - MarkdownVisualSpec.todoControlLeadingInset)
        let buttonWidth = max(buttonSize, contentLeading - buttonLeading - 2)
        let centerY = caretRect.midY

        let button = NSButton()
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.bezelStyle = .shadowlessSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(
            systemSymbolName: checked ? "checkmark.circle.fill" : "circle",
            accessibilityDescription: nil
        )
        button.contentTintColor = checked ? AppTheme.nsSecondaryText : AppTheme.nsMutedText
        button.target = self
        button.action = #selector(todoCheckboxTapped(_:))
        button.tag = paragraphLocation
        button.setAccessibilityIdentifier("todo_checkbox_\(paragraphLocation)")
        button.setAccessibilityLabel(checked ? "Mark todo incomplete" : "Mark todo complete")
        button.wantsLayer = true
        button.layer?.backgroundColor = (textView.backgroundColor ?? AppTheme.nsBackground).cgColor
        button.imageScaling = .scaleProportionallyDown
        button.frame = NSRect(
            x: buttonLeading,
            y: centerY - buttonSize / 2,
            width: buttonWidth,
            height: buttonSize
        )

        textView.addSubview(button)
        todoCheckboxButtons.append(button)
    }

    @objc
    private func todoCheckboxTapped(_ sender: NSButton) {
        toggleTodoCheckbox(atParagraphLocation: sender.tag)
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
    }
}

#endif
