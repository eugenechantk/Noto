//
//  OutlineEditor.swift
//  Noto
//
//  UIViewRepresentable that wires the TextKit 1 stack and bridges
//  OutlineTextView into SwiftUI. The Coordinator implements the
//  delegate and syncs changes back through the @Binding.
//
//  TextKit 1 stack:
//    OutlineTextStorage → NSLayoutManager → NSTextContainer → OutlineTextView
//

import SwiftUI
import UIKit

struct OutlineEditor: UIViewRepresentable {
    @Binding var text: String
    var onEndEditing: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> OutlineTextView {
        // Build TextKit 1 stack
        let storage = OutlineTextStorage()

        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let textView = OutlineTextView(frame: .zero, textContainer: container)
        textView.outlineDelegate = context.coordinator
        textView.isScrollEnabled = true
        textView.backgroundColor = UIColor.clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        textView.autoresizingMask = [UIView.AutoresizingMask.flexibleWidth, UIView.AutoresizingMask.flexibleHeight]
        textView.accessibilityIdentifier = "outlineEditor"

        // Load initial content
        textView.loadContent(text)

        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ uiView: OutlineTextView, context: Context) {
        let current = uiView.deformattedContent()
        guard current != text else { return }

        if context.coordinator.isEditing {
            // During editing, only reload for structural changes (line count mismatch)
            let currentLines = current.components(separatedBy: "\n").count
            let bindingLines = text.components(separatedBy: "\n").count
            guard currentLines != bindingLines else { return }
        }

        uiView.loadContent(text)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, OutlineTextViewDelegate {
        var parent: OutlineEditor
        var textView: OutlineTextView?
        var isEditing = false

        init(_ parent: OutlineEditor) {
            self.parent = parent
        }

        func outlineTextViewDidBeginEditing(_ textView: OutlineTextView) {
            isEditing = true
        }

        func outlineTextViewDidEndEditing(_ textView: OutlineTextView) {
            isEditing = false

            // Reload from binding if it diverged during editing
            let deformatted = textView.deformattedContent()
            if parent.text != deformatted {
                textView.loadContent(parent.text)
            }

            parent.onEndEditing?()
        }

        func outlineTextViewDidChange(_ textView: OutlineTextView) {
            let deformatted = textView.deformattedContent()
            if parent.text != deformatted {
                parent.text = deformatted
            }
        }
    }
}
