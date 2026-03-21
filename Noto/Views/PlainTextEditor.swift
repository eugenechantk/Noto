//
//  PlainTextEditor.swift
//  Noto
//
//  Minimal UITextView wrapper for plain text editing.
//  No custom NSTextStorage, no formatting, no overlays.
//  Just a clean UITextView with a @Binding.
//

import SwiftUI
import UIKit

struct PlainTextEditor: UIViewRepresentable {
    @Binding var text: String
    var onEndEditing: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .sentences
        textView.spellCheckingType = .no
        textView.accessibilityIdentifier = "plainTextEditor"

        textView.text = text
        context.coordinator.textView = textView

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard uiView.text != text else { return }

        if context.coordinator.isEditing {
            // During editing, only reload for structural changes (line count mismatch)
            let currentLines = uiView.text.components(separatedBy: "\n").count
            let bindingLines = text.components(separatedBy: "\n").count
            guard currentLines != bindingLines else { return }
        }

        uiView.text = text
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: PlainTextEditor
        var textView: UITextView?
        var isEditing = false

        init(_ parent: PlainTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            parent.onEndEditing?()
        }

        func textViewDidChange(_ textView: UITextView) {
            if parent.text != textView.text {
                parent.text = textView.text
            }
        }
    }
}
