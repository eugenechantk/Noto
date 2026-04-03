#if os(macOS)
import AppKit
import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "TextKit2EditorView")

// MARK: - SwiftUI Bridge

struct TextKit2EditorView: NSViewControllerRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange, autoFocus: autoFocus)
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

    final class Coordinator {
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
}

// MARK: - View Controller

final class TextKit2EditorViewController: NSViewController {
    var coordinator: TextKit2EditorView.Coordinator?
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

        // Set max width so text wraps
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
        let attributed = MarkdownStylerMac.style(markdown: markdown)
        textView.textStorage?.setAttributedString(attributed)
        if coordinator?.autoFocus == true {
            DispatchQueue.main.async { [weak self] in
                guard let tv = self?.textView else { return }
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: tv.string.count, length: 0))
            }
        }
    }
}

// MARK: - NSTextViewDelegate

extension TextKit2EditorViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        let plain = textView.string
        let selectedRange = textView.selectedRange()
        let styled = MarkdownStylerMac.style(markdown: plain)
        textView.textStorage?.setAttributedString(styled)
        if selectedRange.location + selectedRange.length <= styled.length {
            textView.setSelectedRange(selectedRange)
        }
        coordinator?.textDidChange(plain)
    }
}

// MARK: - MarkdownStylerMac

enum MarkdownStylerMac {
    // MARK: Fonts

    private static let bodyFont = NSFont.systemFont(ofSize: 17, weight: .regular)
    private static let h1Font = NSFont.systemFont(ofSize: 28, weight: .bold)
    private static let h2Font = NSFont.systemFont(ofSize: 22, weight: .bold)
    private static let h3Font = NSFont.systemFont(ofSize: 18, weight: .semibold)
    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)

    // MARK: Colors

    private static let prefixColor = NSColor.tertiaryLabelColor
    private static let bodyColor = NSColor.labelColor
    private static let checkedColor = NSColor.secondaryLabelColor

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
            let font: NSFont
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
            return attributed

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

    private static func applyInlineStyles(to attributed: NSMutableAttributedString, baseFont: NSFont) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let string = attributed.string

        boldRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let matchRange = match?.range else { return }
            let boldFont = NSFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
            attributed.addAttribute(.font, value: boldFont, range: matchRange)
            attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: matchRange.location, length: 2))
            attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: matchRange.location + matchRange.length - 2, length: 2))
        }

        italicRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let matchRange = match?.range else { return }
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.italic)
            let italicFont = NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
            attributed.addAttribute(.font, value: italicFont, range: matchRange)
            attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: matchRange.location, length: 1))
            attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: matchRange.location + matchRange.length - 1, length: 1))
        }

        codeRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let matchRange = match?.range else { return }
            attributed.addAttribute(.font, value: codeFont, range: matchRange)
            attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: matchRange)
            attributed.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: matchRange)
        }
    }

    // MARK: Private — Helpers

    private static func fontForBlockType(_ blockType: BlockType) -> NSFont {
        switch blockType {
        case .heading(1): return h1Font
        case .heading(2): return h2Font
        case .heading(3): return h3Font
        default: return bodyFont
        }
    }

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

#endif
