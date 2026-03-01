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

        // Only reload if the binding changed externally (not from user editing)
        if !coordinator.isEditing {
            let currentDeformatted = textStorage.deformatted()
            if currentDeformatted != text {
                noteTextView.loadNote(text)
            }
        }
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
            syncText()
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
