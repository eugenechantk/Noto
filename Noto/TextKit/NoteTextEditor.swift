//
//  NoteTextEditor.swift
//  Noto
//
//  UIViewRepresentable wrapper that bridges NoteTextView (UIKit TextKit stack)
//  into SwiftUI.
//

import SwiftUI
import UIKit

struct NoteTextEditor: UIViewRepresentable {
    @Binding var text: String
    var nodeViewMode: Bool = false
    var onBeginEditing: (() -> Void)?
    var onEndEditing: (() -> Void)?
    var onReorderLine: ((_ source: Int, _ destination: Int) -> Void)?
    var onDoubleTapLine: ((_ lineIndex: Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> NoteTextView {
        let coordinator = context.coordinator

        // Build TextKit 1 stack: NoteTextStorage → NSLayoutManager → NSTextContainer → NoteTextView
        let textStorage = NoteTextStorage()
        textStorage.nodeViewMode = nodeViewMode

        let textContainerSize = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(size: textContainerSize)
        textContainer.widthTracksTextView = true

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let noteTextView = NoteTextView(frame: .zero, textContainer: textContainer)
        noteTextView.noteTextViewDelegate = coordinator
        noteTextView.isEditable = true
        noteTextView.isScrollEnabled = true
        noteTextView.backgroundColor = .clear
        noteTextView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        noteTextView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        noteTextView.accessibilityIdentifier = "noteTextView"

        // Enable double-tap navigation if callback is set
        if onDoubleTapLine != nil {
            noteTextView.enableDoubleTapNavigation = true
        }

        // Load initial content
        noteTextView.loadNote(text)

        coordinator.noteTextView = noteTextView
        coordinator.textStorage = textStorage

        return noteTextView
    }

    func updateUIView(_ uiView: NoteTextView, context: Context) {
        let coordinator = context.coordinator
        guard let textStorage = coordinator.textStorage else { return }
        let noteTextView = uiView

        let currentDeformatted = textStorage.deformatted()
        guard currentDeformatted != text else { return }

        if coordinator.isEditing {
            // During editing, only force-reload for structural changes
            // (e.g., a line was removed due to reparenting on the home screen).
            // This preserves cursor position for normal typing while ensuring
            // the text view stays in sync with model-driven line removals.
            let currentLineCount = currentDeformatted.components(separatedBy: "\n").count
            let bindingLineCount = text.components(separatedBy: "\n").count
            guard currentLineCount != bindingLineCount else { return }
        }

        noteTextView.loadNote(text)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NoteTextViewDelegate {
        var parent: NoteTextEditor
        var noteTextView: NoteTextView?
        var textStorage: NoteTextStorage?
        var isEditing = false

        init(_ parent: NoteTextEditor) {
            self.parent = parent
        }

        func noteTextViewDidBeginEditing(_ noteTextView: NoteTextView) {
            isEditing = true
            parent.onBeginEditing?()
        }

        func noteTextViewDidEndEditing(_ noteTextView: NoteTextView) {
            isEditing = false

            // If the binding was changed programmatically during editing
            // (e.g., reparenting removed a line), reload from the binding
            // instead of pushing stale UITextView text back to the binding.
            if let textStorage = textStorage {
                let deformatted = textStorage.deformatted()
                if parent.text != deformatted {
                    noteTextView.loadNote(parent.text)
                }
            }

            parent.onEndEditing?()
        }

        func noteTextViewDidChange(_ noteTextView: NoteTextView) {
            syncText()
        }

        func noteTextView(_ noteTextView: NoteTextView, moveLineAt sourceIndex: Int, toLineAt destinationIndex: Int) {
            parent.onReorderLine?(sourceIndex, destinationIndex)
            // Force reload since isEditing blocks updateUIView
            noteTextView.loadNote(parent.text)
        }

        func noteTextView(_ noteTextView: NoteTextView, didDoubleTapLineAt lineIndex: Int) {
            parent.onDoubleTapLine?(lineIndex)
        }

        private func syncText() {
            guard let textStorage = textStorage else { return }
            let deformatted = textStorage.deformatted()
            if parent.text != deformatted {
                parent.text = deformatted
            }
        }
    }
}
