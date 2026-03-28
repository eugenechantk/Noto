import SwiftUI
import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "MarkdownEditorView")

/// UITextView subclass that fixes caret height to match the text line height,
/// excluding paragraph spacing that would otherwise make the caret too tall.
private class NotoTextView: UITextView {
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)

        let charOffset = self.offset(from: beginningOfDocument, to: position)
        let storage = self.textStorage
        guard charOffset >= 0, charOffset < storage.length else {
            return rect
        }

        let attrs = storage.attributes(at: min(charOffset, storage.length - 1), effectiveRange: nil)
        guard let font = attrs[.font] as? UIFont else { return rect }

        let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
        let lineSpacing = paragraphStyle?.lineSpacing ?? 0
        let targetHeight = font.lineHeight + lineSpacing

        if rect.size.height > targetHeight {
            let spacingBefore = paragraphStyle?.paragraphSpacingBefore ?? 0

            // Only offset by spacingBefore on the first line of the paragraph.
            // On wrapped lines (second line of a heading, etc.), the spacing
            // is not present, so shifting down would misalign the caret.
            let nsText = (storage.string as NSString)
            let paraRange = nsText.paragraphRange(for: NSRange(location: charOffset, length: 0))
            let isFirstLine = (charOffset == paraRange.location) || isOnFirstVisualLine(charOffset: charOffset, paragraphStart: paraRange.location)

            if isFirstLine {
                rect.origin.y += spacingBefore
            }
            rect.size.height = targetHeight
        }

        return rect
    }

    /// Checks if charOffset is on the first visual (rendered) line of a paragraph.
    private func isOnFirstVisualLine(charOffset: Int, paragraphStart: Int) -> Bool {
        guard let layoutManager = self.layoutManager as? NSLayoutManager else { return true }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: charOffset)
        let paraGlyphIndex = layoutManager.glyphIndexForCharacter(at: paragraphStart)
        var lineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
        return NSLocationInRange(paraGlyphIndex, lineRange)
    }
}

/// Transparent input accessory view that floats over content.
/// Passes through touches outside the pill so the text view remains interactive.
private class TransparentAccessoryView: UIView {
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // Remove the opaque background UIKit adds to inputAccessoryView's parent
        superview?.backgroundColor = .clear
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep parent transparent after any layout pass
        superview?.backgroundColor = .clear
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Only intercept touches that land on a button; pass through the rest
        let hit = super.hitTest(point, with: event)
        return hit == self ? nil : hit
    }
}

/// SwiftUI wrapper around a UITextView with MarkdownTextStorage for live markdown rendering.
struct MarkdownEditorView: UIViewRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange)
    }

    func makeUIView(context: Context) -> UITextView {
        // Build TextKit 1 stack
        let textStorage = MarkdownTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NotoTextView(frame: .zero, textContainer: container)
        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 40, right: 12)
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.keyboardDismissMode = .interactive
        textView.accessibilityIdentifier = "note_editor"
        textView.delegate = context.coordinator
        textView.inputAccessoryView = context.coordinator.makeKeyboardToolbar(for: textView)

        // Load initial content
        textStorage.load(markdown: text)

        context.coordinator.textStorage = textStorage
        context.coordinator.textView = textView

        // Auto-focus for new notes — place cursor at end of content
        if autoFocus {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
                let endPosition = textStorage.length
                textView.selectedRange = NSRange(location: endPosition, length: 0)
            }
        }

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard let textStorage = context.coordinator.textStorage else { return }
        // Only update if the source of truth changed externally (not from our own save).
        // Skip if the coordinator is the source of the change.
        guard !context.coordinator.isUpdatingText else { return }
        if textStorage.markdownContent() != text {
            let selectedRange = textView.selectedRange
            textStorage.load(markdown: text)
            if selectedRange.location + selectedRange.length <= textStorage.length {
                textView.selectedRange = selectedRange
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var onTextChange: ((String) -> Void)?
        weak var textStorage: MarkdownTextStorage?
        weak var textView: UITextView?
        private var keyboardObservers: [Any] = []
        private var saveWorkItem: DispatchWorkItem?
        /// Guards against re-entrant updateUIView calls when we set the text binding.
        var isUpdatingText = false

        init(text: Binding<String>, onTextChange: ((String) -> Void)?) {
            _text = text
            self.onTextChange = onTextChange
            super.init()
            observeKeyboard()
        }

        deinit {
            keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
            saveWorkItem?.cancel()
        }

        private func observeKeyboard() {
            let show = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil, queue: .main
            ) { [weak self] notification in
                self?.handleKeyboardChange(notification)
            }
            let hide = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.textView?.contentInset.bottom = 0
                self?.textView?.verticalScrollIndicatorInsets.bottom = 0
            }
            keyboardObservers = [show, hide]
        }

        private func handleKeyboardChange(_ notification: Notification) {
            guard let textView,
                  let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let window = textView.window else { return }

            let textViewFrame = textView.convert(textView.bounds, to: window)
            let overlap = textViewFrame.maxY - endFrame.origin.y
            let bottomInset = max(overlap, 0)

            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            UIView.animate(withDuration: duration) {
                textView.contentInset.bottom = bottomInset
                textView.verticalScrollIndicatorInsets.bottom = bottomInset
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let fullText = textView.text ?? ""

            // Find the protected zone: frontmatter + "# " prefix
            let protectedEnd = Self.protectedRangeEnd(in: fullText)

            // Block edits in the protected zone
            if range.location < protectedEnd {
                return false
            }

            // Auto-continue bullet/ordered lists on Enter
            if text == "\n" {
                let nsText = fullText as NSString
                let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
                let line = nsText.substring(with: lineRange)

                // Match bullet: optional leading spaces + (- or * or •) + space
                if let match = line.range(of: #"^(\s*[*\-•] )"#, options: .regularExpression) {
                    let prefix = String(line[match])

                    // If the line is ONLY the bullet prefix (empty bullet), remove it instead of continuing
                    let content = String(line[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if content.isEmpty {
                        // Delete the empty bullet line content, leave just the newline
                        let prefixNSRange = NSRange(location: lineRange.location, length: prefix.count)
                        textView.selectedRange = prefixNSRange
                        textView.insertText("")
                        return false
                    }

                    // Insert newline + same prefix
                    textView.insertText("\n" + prefix)
                    return false
                }

                // Match ordered list: optional leading spaces + digits + ". "
                if let match = line.range(of: #"^(\s*)\d+\. "#, options: .regularExpression) {
                    let leadingSpaces = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                    // Extract the number and increment it
                    let stripped = line.drop(while: { $0 == " " || $0 == "\t" })
                    if let dotIndex = stripped.firstIndex(of: ".") {
                        let numStr = String(stripped[stripped.startIndex..<dotIndex])
                        if let num = Int(numStr) {
                            let prefix = "\(leadingSpaces)\(num + 1). "

                            // If empty ordered list item, remove it
                            let content = String(line[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if content.isEmpty {
                                let matchLen = line.distance(from: line.startIndex, to: match.upperBound)
                                let prefixNSRange = NSRange(location: lineRange.location, length: matchLen)
                                textView.selectedRange = prefixNSRange
                                textView.insertText("")
                                return false
                            }

                            textView.insertText("\n" + prefix)
                            return false
                        }
                    }
                }
            }

            return true
        }

        /// Returns the character index after the frontmatter + "# " prefix.
        /// Everything before this index is protected from editing.
        private static func protectedRangeEnd(in text: String) -> Int {
            var offset = 0

            // Skip frontmatter
            if text.hasPrefix("---") {
                if let closeRange = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
                    offset = text.distance(from: text.startIndex, to: closeRange.upperBound)
                } else if let closeRange = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
                    offset = text.distance(from: text.startIndex, to: closeRange.upperBound)
                    // Skip trailing newline if present
                    let remaining = text[closeRange.upperBound...]
                    if remaining.hasPrefix("\n") {
                        offset += 1
                    }
                }
            }

            // Skip leading newlines after frontmatter
            let afterFM = text.dropFirst(offset)
            for ch in afterFM {
                if ch == "\n" { offset += 1 } else { break }
            }

            // Protect "# " prefix
            let remaining = text.dropFirst(offset)
            if remaining.hasPrefix("# ") {
                offset += 2
            } else if remaining.hasPrefix("#") {
                offset += 1
            }

            return offset
        }

        // MARK: - Keyboard Toolbar

        func makeKeyboardToolbar(for textView: UITextView) -> UIView {
            let pillHeight: CGFloat = 40
            let bottomMargin: CGFloat = 8
            let barHeight: CGFloat = pillHeight + bottomMargin
            let pillPadding: CGFloat = 12
            let buttonSize: CGFloat = 36
            let buttonSpacing: CGFloat = 4

            let wrapper = TransparentAccessoryView(frame: CGRect(x: 0, y: 0, width: 400, height: barHeight))
            wrapper.backgroundColor = .clear
            wrapper.autoresizingMask = .flexibleWidth

            // Compact pill — Liquid Glass effect
            let glassEffect = UIGlassEffect()
            glassEffect.isInteractive = true
            let pill = UIVisualEffectView(effect: glassEffect)
            pill.layer.cornerRadius = pillHeight / 2
            pill.clipsToBounds = true
            pill.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(pill)

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)

            let outdentButton = UIButton(type: .system)
            outdentButton.setImage(UIImage(systemName: "decrease.indent", withConfiguration: symbolConfig), for: .normal)
            outdentButton.tintColor = .white
            outdentButton.addTarget(self, action: #selector(outdentTapped), for: .touchUpInside)
            outdentButton.accessibilityLabel = "Outdent"
            outdentButton.accessibilityIdentifier = "outdentButton"

            let indentButton = UIButton(type: .system)
            indentButton.setImage(UIImage(systemName: "increase.indent", withConfiguration: symbolConfig), for: .normal)
            indentButton.tintColor = .white
            indentButton.addTarget(self, action: #selector(indentTapped), for: .touchUpInside)
            indentButton.accessibilityLabel = "Indent"
            indentButton.accessibilityIdentifier = "indentButton"

            let stack = UIStackView(arrangedSubviews: [outdentButton, indentButton])
            stack.axis = .horizontal
            stack.spacing = buttonSpacing
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false
            pill.contentView.addSubview(stack)

            NSLayoutConstraint.activate([
                // Pill anchored to trailing edge with bottom margin
                pill.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -12),
                pill.topAnchor.constraint(equalTo: wrapper.topAnchor),
                pill.heightAnchor.constraint(equalToConstant: pillHeight),

                // Stack inside pill contentView with horizontal padding
                stack.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor, constant: pillPadding),
                stack.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor, constant: -pillPadding),
                stack.centerYAnchor.constraint(equalTo: pill.contentView.centerYAnchor),

                outdentButton.widthAnchor.constraint(equalToConstant: buttonSize),
                outdentButton.heightAnchor.constraint(equalToConstant: buttonSize),
                indentButton.widthAnchor.constraint(equalToConstant: buttonSize),
                indentButton.heightAnchor.constraint(equalToConstant: buttonSize),
            ])

            return wrapper
        }

        @objc private func indentTapped() {
            guard let textView else { return }
            let nsText = textView.text as NSString
            let cursorPos = textView.selectedRange.location
            guard cursorPos <= nsText.length else { return }

            let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
            // Insert 2 spaces at the start of the line
            let insertRange = NSRange(location: lineRange.location, length: 0)
            textView.selectedRange = insertRange
            textView.insertText("  ")
            // Restore cursor position (shifted right by 2)
            textView.selectedRange = NSRange(location: cursorPos + 2, length: 0)
        }

        @objc private func outdentTapped() {
            guard let textView else { return }
            let nsText = textView.text as NSString
            let cursorPos = textView.selectedRange.location
            guard cursorPos <= nsText.length else { return }

            let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
            let line = nsText.substring(with: lineRange)

            // Count leading spaces (remove up to 2)
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let spacesToRemove = min(leadingSpaces, 2)
            guard spacesToRemove > 0 else { return }

            let removeRange = NSRange(location: lineRange.location, length: spacesToRemove)
            textView.selectedRange = removeRange
            textView.insertText("")
            // Restore cursor position (shifted left, clamped to line start)
            let newCursor = max(cursorPos - spacesToRemove, lineRange.location)
            textView.selectedRange = NSRange(location: newCursor, length: 0)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let fullText = textView.text ?? ""
            let protectedEnd = Self.protectedRangeEnd(in: fullText)
            let selection = textView.selectedRange

            // Clamp cursor/selection to stay at or after the protected zone
            if selection.location < protectedEnd {
                let newLocation = protectedEnd
                let newLength = max(0, selection.length - (protectedEnd - selection.location))
                textView.selectedRange = NSRange(location: newLocation, length: newLength)
            }

            // Update active line so heading prefix shows/hides based on cursor position
            let nsText = fullText as NSString
            let cursorPos = textView.selectedRange.location
            if cursorPos <= nsText.length {
                let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
                textStorage?.setActiveLine(lineRange)
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let content = textStorage?.markdownContent() else { return }
            isUpdatingText = true
            self.text = content
            isUpdatingText = false
            onTextChange?(content)
        }

        /// Flushes any pending debounced save immediately. Call before navigating away.
        func flushPendingSave() {
            saveWorkItem?.cancel()
            guard let content = textStorage?.markdownContent() else { return }
            isUpdatingText = true
            self.text = content
            isUpdatingText = false
            onTextChange?(content)
        }
    }
}
