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

        init(text: Binding<String>, onTextChange: ((String) -> Void)?) {
            _text = text
            self.onTextChange = onTextChange
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let content = textStorage?.markdownContent() else { return }
            text = content
            onTextChange?(content)
        }
    }
}
