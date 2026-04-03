import SwiftUI
import os.log

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "TextKit2Editor")

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
        if stripped.hasPrefix("- [x] ") || stripped == "- [x]" {
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
        case .todo(let checked, _):
            let marker = checked ? "- [x] " : "- [ ] "
            return indentCount + (stripped.hasPrefix(marker) ? marker.count : 0)
        case .bullet:
            return indentCount + (stripped.hasPrefix("- ") || stripped.hasPrefix("* ") || stripped.hasPrefix("• ") ? 2 : 0)
        case .orderedList(let number, _):
            let marker = "\(number). "
            return indentCount + (stripped.hasPrefix(marker) ? marker.count : 0)
        case .frontmatter, .paragraph: return 0
        }
    }
}

// MARK: - MarkdownTheme

/// Centralized font and color constants for markdown rendering.
private enum MarkdownTheme {
    static let bodyFont = PlatformFont.systemFont(ofSize: 17, weight: .regular)
    static let h1Font = PlatformFont.systemFont(ofSize: 28, weight: .bold)
    static let h2Font = PlatformFont.systemFont(ofSize: 22, weight: .bold)
    static let h3Font = PlatformFont.systemFont(ofSize: 18, weight: .semibold)
    static let codeFont = PlatformFont.monospacedSystemFont(ofSize: 16, weight: .regular)

    #if os(iOS)
    static let bodyColor: PlatformColor = .label
    static let prefixColor: PlatformColor = .tertiaryLabel
    static let checkedColor: PlatformColor = .secondaryLabel
    static let codeColor: PlatformColor = .secondaryLabel
    static let codeBgColor: PlatformColor = .secondarySystemFill
    #elseif os(macOS)
    static let bodyColor: PlatformColor = .labelColor
    static let prefixColor: PlatformColor = .tertiaryLabelColor
    static let checkedColor: PlatformColor = .secondaryLabelColor
    static let codeColor: PlatformColor = .secondaryLabelColor
    static let codeBgColor: PlatformColor = .quaternaryLabelColor
    #endif

    static func font(for kind: MarkdownBlockKind) -> PlatformFont {
        switch kind {
        case .heading(1): return h1Font
        case .heading(2): return h2Font
        case .heading(3): return h3Font
        default: return bodyFont
        }
    }
}

// MARK: - MarkdownParagraphStyler

/// Builds an NSAttributedString for a single markdown paragraph.
/// Called by the NSTextContentStorageDelegate — only the changed paragraph
/// gets re-styled, not the entire document.
private enum MarkdownParagraphStyler {
    static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    static let italicRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
    static let codeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)

    static func style(text: String, kind: MarkdownBlockKind) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributed.length)
        guard fullRange.length > 0 else {
            attributed.addAttributes([.font: MarkdownTheme.bodyFont, .foregroundColor: MarkdownTheme.bodyColor], range: fullRange)
            return attributed
        }

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 4

        switch kind {
        case .heading(let level):
            let font = MarkdownTheme.font(for: kind)
            let spacing: CGFloat = level == 1 ? 16 : level == 2 ? 12 : 8
            paraStyle.paragraphSpacingBefore = spacing
            paraStyle.paragraphSpacing = spacing * 0.4
            attributed.addAttributes([
                .font: font,
                .foregroundColor: MarkdownTheme.bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)

        case .todo(let checked, let indent):
            let indentPt = CGFloat(indent) * 16
            paraStyle.firstLineHeadIndent = indentPt
            paraStyle.headIndent = indentPt + 24
            paraStyle.paragraphSpacingBefore = 4
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

        case .bullet(let indent):
            let indentPt = CGFloat(indent) * 16
            paraStyle.firstLineHeadIndent = indentPt
            paraStyle.headIndent = indentPt + 16
            paraStyle.paragraphSpacingBefore = 4
            attributed.addAttributes([
                .font: MarkdownTheme.bodyFont,
                .foregroundColor: MarkdownTheme.bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)

        case .orderedList(_, let indent):
            let indentPt = CGFloat(indent) * 16
            paraStyle.firstLineHeadIndent = indentPt
            paraStyle.headIndent = indentPt + 24
            paraStyle.paragraphSpacingBefore = 4
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
            paraStyle.paragraphSpacingBefore = 6
            attributed.addAttributes([
                .font: MarkdownTheme.bodyFont,
                .foregroundColor: MarkdownTheme.bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
        }

        // Dim prefix characters
        let pfxLen = kind.prefixLength(in: text)
        if pfxLen > 0 && pfxLen <= fullRange.length {
            attributed.addAttribute(.foregroundColor, value: MarkdownTheme.prefixColor,
                                    range: NSRange(location: 0, length: pfxLen))
        }

        // Inline formatting
        applyInlineStyles(to: attributed, baseFont: MarkdownTheme.font(for: kind))

        return attributed
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

        // Code: `text`
        codeRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let r = match?.range else { return }
            attributed.addAttribute(.font, value: MarkdownTheme.codeFont, range: r)
            attributed.addAttribute(.foregroundColor, value: MarkdownTheme.codeColor, range: r)
            attributed.addAttribute(.backgroundColor, value: MarkdownTheme.codeBgColor, range: r)
        }
    }
}

// MARK: - MarkdownParagraph

/// Custom NSTextParagraph carrying markdown block-kind metadata.
/// Returned by the NSTextContentStorageDelegate so that the
/// NSTextLayoutManagerDelegate can read the kind when creating fragments.
final class MarkdownParagraph: NSTextParagraph {
    let blockKind: MarkdownBlockKind

    init(attributedString: NSAttributedString, blockKind: MarkdownBlockKind) {
        self.blockKind = blockKind
        super.init(attributedString: attributedString)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - MarkdownLayoutFragment

/// Custom NSTextLayoutFragment that carries block-kind metadata and
/// can draw per-block accessories (e.g., heading separator lines).
final class MarkdownLayoutFragment: NSTextLayoutFragment {
    let blockKind: MarkdownBlockKind

    init(textElement: NSTextElement, range: NSTextRange?, blockKind: MarkdownBlockKind) {
        self.blockKind = blockKind
        super.init(textElement: textElement, range: range)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(at point: CGPoint, in context: CGContext) {
        // Draw a subtle background behind frontmatter lines
        if case .frontmatter = blockKind {
            context.saveGState()
            context.setFillColor(MarkdownTheme.codeBgColor.cgColor)
            let bg = CGRect(x: point.x, y: point.y,
                            width: renderingSurfaceBounds.width,
                            height: renderingSurfaceBounds.height)
            context.fill(bg)
            context.restoreGState()
        }

        super.draw(at: point, in: context)

        // Draw a thin separator under H1 headings
        if case .heading(1) = blockKind {
            context.saveGState()
            context.setStrokeColor(MarkdownTheme.prefixColor.cgColor)
            context.setLineWidth(0.5)
            let y = point.y + renderingSurfaceBounds.height - 1
            context.move(to: CGPoint(x: point.x, y: y))
            context.addLine(to: CGPoint(x: point.x + renderingSurfaceBounds.width, y: y))
            context.strokePath()
            context.restoreGState()
        }
    }
}

// MARK: - MarkdownTextDelegate

/// The heart of the TextKit 2 integration.
///
/// - **NSTextContentStorageDelegate**: Intercepts paragraph creation.
///   For each paragraph the content storage builds, we return a styled
///   `MarkdownParagraph` with the correct fonts, colors, and indentation.
///   Only the *changed* paragraph is re-styled — not the whole document.
///
/// - **NSTextLayoutManagerDelegate**: Intercepts layout-fragment creation.
///   For each paragraph being laid out, we return a `MarkdownLayoutFragment`
///   that can draw custom accessories (heading separators, frontmatter bg).
///   Only *visible* fragments are created — off-screen content is skipped.
final class MarkdownTextDelegate: NSObject, NSTextContentStorageDelegate, NSTextLayoutManagerDelegate {

    // MARK: NSTextContentStorageDelegate

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
        if isFrontmatter(at: range.location, in: textStorage.string) {
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
            ]
            result.append(NSAttributedString(string: "\n", attributes: nlAttrs))
        }

        return MarkdownParagraph(attributedString: result, blockKind: kind)
    }

    // MARK: NSTextLayoutManagerDelegate

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let kind = (textElement as? MarkdownParagraph)?.blockKind ?? .paragraph
        return MarkdownLayoutFragment(
            textElement: textElement,
            range: textElement.elementRange,
            blockKind: kind
        )
    }

    // MARK: Frontmatter Detection

    /// Returns true if the character at `position` falls within a YAML
    /// frontmatter block (the region between the opening `---\n` and
    /// the closing `\n---`).
    private func isFrontmatter(at position: Int, in fullText: String) -> Bool {
        guard fullText.hasPrefix("---\n") || fullText.hasPrefix("---\r\n") else { return false }
        let searchStart = fullText.index(fullText.startIndex, offsetBy: min(4, fullText.count))
        guard searchStart < fullText.endIndex,
              let closeRange = fullText.range(of: "\n---", range: searchStart..<fullText.endIndex) else {
            return false
        }
        let fmEnd = fullText.distance(from: fullText.startIndex, to: closeRange.upperBound)
        return position < fmEnd
    }
}

// MARK: - Shared Coordinator

final class TextKit2EditorCoordinator {
    @Binding var text: String
    var onTextChange: ((String) -> Void)?
    var isUpdatingText = false
    let autoFocus: Bool

    init(text: Binding<String>, onTextChange: ((String) -> Void)?, autoFocus: Bool) {
        _text = text
        self.onTextChange = onTextChange
        self.autoFocus = autoFocus
    }

    func textDidChange(_ newText: String) {
        isUpdatingText = true
        text = newText
        isUpdatingText = false
        onTextChange?(newText)
    }
}

// ╔══════════════════════════════════════════════════════════════╗
// ║  iOS — UITextView (TextKit 2 by default on iOS 16+)        ║
// ╚══════════════════════════════════════════════════════════════╝

#if os(iOS)

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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

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
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
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
    }

    func loadText(_ markdown: String) {
        textView.text = markdown
        if coordinator?.autoFocus == true {
            DispatchQueue.main.async { [weak self] in
                guard let tv = self?.textView else { return }
                tv.becomeFirstResponder()
                if let end = tv.endOfDocument {
                    tv.selectedTextRange = tv.textRange(from: end, to: end)
                }
            }
        }
    }

    // MARK: UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        coordinator?.textDidChange(textView.text ?? "")
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        updateTypingAttributes()
    }

    /// Sets typing attributes to match the current paragraph's block kind,
    /// so newly typed characters inherit the correct font immediately
    /// (before the content-storage delegate re-styles the paragraph).
    private func updateTypingAttributes() {
        let text = textView.text ?? ""
        let cursor = textView.selectedRange.location
        let nsText = text as NSString
        guard cursor <= nsText.length else { return }
        let paraRange = nsText.paragraphRange(for: NSRange(location: cursor, length: 0))
        var paraText = nsText.substring(with: paraRange)
        if paraText.hasSuffix("\n") { paraText = String(paraText.dropLast()) }
        let kind = MarkdownBlockKind.detect(from: paraText)
        textView.typingAttributes = [
            .font: MarkdownTheme.font(for: kind),
            .foregroundColor: MarkdownTheme.bodyColor,
        ]
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

final class TextKit2EditorViewController: NSViewController, NSTextViewDelegate {
    var coordinator: TextKit2EditorCoordinator?
    private(set) var textView: NSTextView!
    private let scrollView = NSScrollView()
    private let markdownDelegate = MarkdownTextDelegate()

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

        // Set our delegates on the stack
        contentStorage.delegate = markdownDelegate
        layoutManager.delegate = markdownDelegate

        // Create NSTextView backed by the TextKit 2 container
        textView = NSTextView(frame: .zero, textContainer: container)
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
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = self
        textView.accessibilityIdentifier = "note_editor"

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
    }

    func loadText(_ markdown: String) {
        textView.string = markdown
        if coordinator?.autoFocus == true {
            DispatchQueue.main.async { [weak self] in
                guard let tv = self?.textView else { return }
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: tv.string.count, length: 0))
            }
        }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        coordinator?.textDidChange(textView.string)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateTypingAttributes()
    }

    private func updateTypingAttributes() {
        let text = textView.string
        let cursor = textView.selectedRange().location
        let nsText = text as NSString
        guard cursor <= nsText.length else { return }
        let paraRange = nsText.paragraphRange(for: NSRange(location: cursor, length: 0))
        var paraText = nsText.substring(with: paraRange)
        if paraText.hasSuffix("\n") { paraText = String(paraText.dropLast()) }
        let kind = MarkdownBlockKind.detect(from: paraText)
        textView.typingAttributes = [
            .font: MarkdownTheme.font(for: kind),
            .foregroundColor: MarkdownTheme.bodyColor,
        ]
    }
}

#endif
