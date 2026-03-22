import SwiftUI
import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "MarkdownEditorView")

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

        let textView = UITextView(frame: .zero, textContainer: container)
        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 40, right: 12)
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.keyboardDismissMode = .interactive
        textView.delegate = context.coordinator

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
        // Only update if the source of truth changed externally
        if textStorage.markdownContent() != text {
            let selectedRange = textView.selectedRange
            textStorage.load(markdown: text)
            // Restore cursor if valid
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

        init(text: Binding<String>, onTextChange: ((String) -> Void)?) {
            _text = text
            self.onTextChange = onTextChange
            super.init()
            observeKeyboard()
        }

        deinit {
            keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
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

            // Block any edit that would modify the protected zone
            if range.location < protectedEnd {
                // Allow typing at the end of "# " (appending to title)
                if range.location == protectedEnd && range.length == 0 {
                    return true
                }
                // Block deletions or replacements into protected zone
                return false
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

        func textViewDidChange(_ textView: UITextView) {
            guard let content = textStorage?.markdownContent() else { return }
            self.text = content
            onTextChange?(content)
        }
    }
}
