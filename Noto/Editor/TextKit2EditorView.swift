#if os(iOS)
import SwiftUI
import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "TextKit2EditorView")

// MARK: - SwiftUI Bridge

struct TextKit2EditorView: UIViewControllerRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange, autoFocus: autoFocus)
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

final class TextKit2EditorViewController: UIViewController {
    var coordinator: TextKit2EditorView.Coordinator?
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
        let attributed = MarkdownStyler.style(markdown: markdown)
        textView.attributedText = attributed
        if coordinator?.autoFocus == true {
            DispatchQueue.main.async { [weak self] in
                self?.textView.becomeFirstResponder()
                if let end = self?.textView.endOfDocument {
                    self?.textView.selectedTextRange = self?.textView.textRange(from: end, to: end)
                }
            }
        }
    }
}

// MARK: - UITextViewDelegate

extension TextKit2EditorViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        let plain = textView.text ?? ""
        // Re-style the full document, preserving cursor position
        let selectedRange = textView.selectedRange
        let styled = MarkdownStyler.style(markdown: plain)
        textView.attributedText = styled
        // Restore selection
        if selectedRange.location + selectedRange.length <= styled.length {
            textView.selectedRange = selectedRange
        }
        coordinator?.textDidChange(plain)
    }
}

// MARK: - MarkdownStyler

/// Styles a plain markdown string into an NSAttributedString.
/// Applies block-level styles (headings, lists, todos) per paragraph
/// and inline styles (bold, italic, code) within each paragraph.
enum MarkdownStyler {
    // MARK: Fonts

    private static let bodyFont = UIFont.systemFont(ofSize: 17, weight: .regular)
    private static let h1Font = UIFont.systemFont(ofSize: 28, weight: .bold)
    private static let h2Font = UIFont.systemFont(ofSize: 22, weight: .bold)
    private static let h3Font = UIFont.systemFont(ofSize: 18, weight: .semibold)
    private static let codeFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)

    // MARK: Colors

    private static let prefixColor = UIColor.tertiaryLabel
    private static let bodyColor = UIColor.label
    private static let checkedColor = UIColor.secondaryLabel

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

        // Base paragraph style
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 4

        switch blockType {
        case .heading(let level):
            let font: UIFont
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
            // Dim the prefix (e.g., "## ")
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
            // Dim the prefix "- [ ] " or "- [x] "
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

        // Apply inline formatting (bold, italic, code)
        applyInlineStyles(to: attributed, baseFont: fontForBlockType(blockType))

        return attributed
    }

    // MARK: Private — Inline Styles

    private static func applyInlineStyles(to attributed: NSMutableAttributedString, baseFont: UIFont) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let string = attributed.string

        // Bold: **text**
        boldRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let matchRange = match?.range else { return }
            let boldFont = UIFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
            attributed.addAttribute(.font, value: boldFont, range: matchRange)
            // Dim delimiters
            attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: matchRange.location, length: 2))
            attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: matchRange.location + matchRange.length - 2, length: 2))
        }

        // Italic: *text*
        italicRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let matchRange = match?.range else { return }
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? baseFont.fontDescriptor
            let italicFont = UIFont(descriptor: descriptor, size: baseFont.pointSize)
            attributed.addAttribute(.font, value: italicFont, range: matchRange)
            // Dim delimiters
            attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: matchRange.location, length: 1))
            attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: matchRange.location + matchRange.length - 1, length: 1))
        }

        // Code: `text`
        codeRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let matchRange = match?.range else { return }
            attributed.addAttribute(.font, value: codeFont, range: matchRange)
            attributed.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: matchRange)
            attributed.addAttribute(.backgroundColor, value: UIColor.secondarySystemFill, range: matchRange)
        }
    }

    // MARK: Private — Helpers

    private static func fontForBlockType(_ blockType: BlockType) -> UIFont {
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
            // "# ", "## ", "### "
            return level + 1
        case .todo(let checked, _):
            // "  - [ ] " or "  - [x] "
            let marker = checked ? "- [x] " : "- [ ] "
            return indentCount + (stripped.hasPrefix(marker) ? marker.count : 0)
        case .bullet(_):
            // "  - " or "  * " or "  • "
            if stripped.hasPrefix("- ") || stripped.hasPrefix("* ") || stripped.hasPrefix("• ") {
                return indentCount + 2
            }
            return indentCount
        case .orderedList(let number, _):
            // "  1. "
            let marker = "\(number). "
            return indentCount + (stripped.hasPrefix(marker) ? marker.count : 0)
        case .frontmatter, .paragraph:
            return 0
        }
    }
}

#endif
