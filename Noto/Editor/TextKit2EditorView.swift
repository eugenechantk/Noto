import SwiftUI
import os.log

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "TextKit2EditorView")

// MARK: - Platform Aliases

#if os(iOS)
private typealias PlatformFont = UIFont
private typealias PlatformColor = UIColor
#elseif os(macOS)
private typealias PlatformFont = NSFont
private typealias PlatformColor = NSColor
#endif

// MARK: - MarkdownStyler (Cross-Platform)

/// Styles a plain markdown string into an NSAttributedString.
/// Applies block-level styles (headings, lists, todos) per paragraph
/// and inline styles (bold, italic, code) within each paragraph.
enum MarkdownStyler {
    // MARK: Fonts

    private static let bodyFont = PlatformFont.systemFont(ofSize: 17, weight: .regular)
    private static let h1Font = PlatformFont.systemFont(ofSize: 28, weight: .bold)
    private static let h2Font = PlatformFont.systemFont(ofSize: 22, weight: .bold)
    private static let h3Font = PlatformFont.systemFont(ofSize: 18, weight: .semibold)
    private static let codeFont = PlatformFont.monospacedSystemFont(ofSize: 16, weight: .regular)

    // MARK: Colors

    #if os(iOS)
    private static let prefixColor = UIColor.tertiaryLabel
    private static let bodyColor = UIColor.label
    private static let checkedColor = UIColor.secondaryLabel
    private static let codeColor = UIColor.secondaryLabel
    private static let codeBgColor = UIColor.secondarySystemFill
    #elseif os(macOS)
    private static let prefixColor = NSColor.tertiaryLabelColor
    private static let bodyColor = NSColor.labelColor
    private static let checkedColor = NSColor.secondaryLabelColor
    private static let codeColor = NSColor.secondaryLabelColor
    private static let codeBgColor = NSColor.quaternaryLabelColor
    #endif

    // MARK: Inline Regexes

    private static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let italicRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
    private static let codeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)

    // MARK: Public

    static func style(markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        for (i, line) in lines.enumerated() {
            let lineStr = String(line)
            let styled = styleLine(lineStr)
            result.append(styled)
            if i < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    // MARK: Private — Line Styling

    private static func styleLine(_ line: String) -> NSAttributedString {
        let blockType = BlockType.detect(from: line)
        let attributed = NSMutableAttributedString(string: line)
        let fullRange = NSRange(location: 0, length: attributed.length)

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 4

        switch blockType {
        case .heading(let level):
            let font: PlatformFont
            var spacing: CGFloat = 0
            switch level {
            case 1:
                font = h1Font
                spacing = 16
            case 2:
                font = h2Font
                spacing = 12
            default:
                font = h3Font
                spacing = 8
            }
            paraStyle.paragraphSpacingBefore = spacing
            paraStyle.paragraphSpacing = spacing * 0.4
            attributed.addAttributes([
                .font: font,
                .foregroundColor: bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
            let prefixLen = prefixLength(for: line, blockType: blockType)
            if prefixLen > 0 {
                attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: 0, length: prefixLen))
            }

        case .todo(let checked, let indent):
            let indentPt = CGFloat(indent) * 16
            paraStyle.firstLineHeadIndent = indentPt
            paraStyle.headIndent = indentPt + 24
            paraStyle.paragraphSpacingBefore = 4
            attributed.addAttributes([
                .font: bodyFont,
                .foregroundColor: checked ? checkedColor : bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
            if checked {
                let prefixLen = prefixLength(for: line, blockType: blockType)
                let contentRange = NSRange(location: prefixLen, length: max(0, attributed.length - prefixLen))
                attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            }
            let prefixLen = prefixLength(for: line, blockType: blockType)
            if prefixLen > 0 {
                attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: 0, length: prefixLen))
            }

        case .bullet(let indent):
            let indentPt = CGFloat(indent) * 16
            paraStyle.firstLineHeadIndent = indentPt
            paraStyle.headIndent = indentPt + 16
            paraStyle.paragraphSpacingBefore = 4
            attributed.addAttributes([
                .font: bodyFont,
                .foregroundColor: bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
            let prefixLen = prefixLength(for: line, blockType: blockType)
            if prefixLen > 0 {
                attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: 0, length: prefixLen))
            }

        case .orderedList(_, let indent):
            let indentPt = CGFloat(indent) * 16
            paraStyle.firstLineHeadIndent = indentPt
            paraStyle.headIndent = indentPt + 24
            paraStyle.paragraphSpacingBefore = 4
            attributed.addAttributes([
                .font: bodyFont,
                .foregroundColor: bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
            let prefixLen = prefixLength(for: line, blockType: blockType)
            if prefixLen > 0 {
                attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: 0, length: prefixLen))
            }

        case .frontmatter:
            paraStyle.paragraphSpacingBefore = 0
            attributed.addAttributes([
                .font: codeFont,
                .foregroundColor: prefixColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
            return attributed // No inline formatting for frontmatter

        case .paragraph:
            paraStyle.paragraphSpacingBefore = 6
            attributed.addAttributes([
                .font: bodyFont,
                .foregroundColor: bodyColor,
                .paragraphStyle: paraStyle,
            ], range: fullRange)
        }

        applyInlineStyles(to: attributed, baseFont: fontForBlockType(blockType))
        return attributed
    }

    // MARK: Private — Inline Styles

    private static func applyInlineStyles(to attributed: NSMutableAttributedString, baseFont: PlatformFont) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let string = attributed.string

        // Bold: **text**
        boldRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let matchRange = match?.range else { return }
            let boldFont = PlatformFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
            attributed.addAttribute(.font, value: boldFont, range: matchRange)
            attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: matchRange.location, length: 2))
            attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: matchRange.location + matchRange.length - 2, length: 2))
        }

        // Italic: *text*
        italicRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let matchRange = match?.range else { return }
            #if os(iOS)
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? baseFont.fontDescriptor
            let italicFont = PlatformFont(descriptor: descriptor, size: baseFont.pointSize)
            #elseif os(macOS)
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.italic)
            let italicFont = PlatformFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
            #endif
            attributed.addAttribute(.font, value: italicFont, range: matchRange)
            attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: matchRange.location, length: 1))
            attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: matchRange.location + matchRange.length - 1, length: 1))
        }

        // Code: `text`
        codeRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let matchRange = match?.range else { return }
            attributed.addAttribute(.font, value: codeFont, range: matchRange)
            attributed.addAttribute(.foregroundColor, value: codeColor, range: matchRange)
            attributed.addAttribute(.backgroundColor, value: codeBgColor, range: matchRange)
        }
    }

    // MARK: Private — Helpers

    private static func fontForBlockType(_ blockType: BlockType) -> PlatformFont {
        switch blockType {
        case .heading(1): return h1Font
        case .heading(2): return h2Font
        case .heading(3): return h3Font
        default: return bodyFont
        }
    }

    /// Calculates the prefix length (including leading indent spaces) for dimming.
    private static func prefixLength(for line: String, blockType: BlockType) -> Int {
        let indentCount = line.prefix(while: { $0 == " " }).count
        let stripped = String(line.dropFirst(indentCount))

        switch blockType {
        case .heading(let level):
            return level + 1
        case .todo(let checked, _):
            let marker = checked ? "- [x] " : "- [ ] "
            return indentCount + (stripped.hasPrefix(marker) ? marker.count : 0)
        case .bullet(_):
            if stripped.hasPrefix("- ") || stripped.hasPrefix("* ") || stripped.hasPrefix("• ") {
                return indentCount + 2
            }
            return indentCount
        case .orderedList(let number, _):
            let marker = "\(number). "
            return indentCount + (stripped.hasPrefix(marker) ? marker.count : 0)
        case .frontmatter, .paragraph:
            return 0
        }
    }
}

// MARK: - Shared Coordinator

/// Coordinator shared between iOS and macOS representable wrappers.
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

// MARK: - iOS Implementation

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
        if vc.textView.text != text {
            vc.loadText(text)
        }
    }
}

final class TextKit2EditorViewController: UIViewController, UITextViewDelegate {
    var coordinator: TextKit2EditorCoordinator?
    let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .label
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
        textView.attributedText = MarkdownStyler.style(markdown: markdown)
        if coordinator?.autoFocus == true {
            DispatchQueue.main.async { [weak self] in
                self?.textView.becomeFirstResponder()
                if let end = self?.textView.endOfDocument {
                    self?.textView.selectedTextRange = self?.textView.textRange(from: end, to: end)
                }
            }
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        let plain = textView.text ?? ""
        let selectedRange = textView.selectedRange
        textView.attributedText = MarkdownStyler.style(markdown: plain)
        if selectedRange.location + selectedRange.length <= (textView.attributedText?.length ?? 0) {
            textView.selectedRange = selectedRange
        }
        coordinator?.textDidChange(plain)
    }
}

#endif

// MARK: - macOS Implementation

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
    let scrollView = NSScrollView()
    let textView = NSTextView()

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = self
        textView.accessibilityIdentifier = "note_editor"
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func loadText(_ markdown: String) {
        textView.textStorage?.setAttributedString(MarkdownStyler.style(markdown: markdown))
        if coordinator?.autoFocus == true {
            DispatchQueue.main.async { [weak self] in
                guard let tv = self?.textView else { return }
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: tv.string.count, length: 0))
            }
        }
    }

    func textDidChange(_ notification: Notification) {
        let plain = textView.string
        let selectedRange = textView.selectedRange()
        textView.textStorage?.setAttributedString(MarkdownStyler.style(markdown: plain))
        if selectedRange.location + selectedRange.length <= (textView.textStorage?.length ?? 0) {
            textView.setSelectedRange(selectedRange)
        }
        coordinator?.textDidChange(plain)
    }
}

#endif
