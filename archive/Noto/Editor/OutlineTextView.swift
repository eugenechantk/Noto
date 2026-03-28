//
//  OutlineTextView.swift
//  Noto
//
//  Custom UITextView for the outline editor. Handles:
//  - User interaction (typing, selection)
//  - Keyboard toolbar (indent, outdent, dismiss)
//  - Delegates editing events to OutlineTextViewDelegate
//  - Caret position management
//
//  Follows Simple-Notes: the text view is its own UITextViewDelegate,
//  calls processRichFormatting() on the storage after each edit,
//  then notifies its delegate.
//

import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "OutlineTextView")

// MARK: - Delegate Protocol

protocol OutlineTextViewDelegate: AnyObject {
    func outlineTextViewDidBeginEditing(_ textView: OutlineTextView)
    func outlineTextViewDidEndEditing(_ textView: OutlineTextView)
    func outlineTextViewDidChange(_ textView: OutlineTextView)
}

// MARK: - OutlineTextView

final class OutlineTextView: UITextView, UITextViewDelegate {

    weak var outlineDelegate: OutlineTextViewDelegate?

    private var outlineStorage: OutlineTextStorage {
        textStorage as! OutlineTextStorage
    }

    // MARK: - Setup

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        self.delegate = self
        self.font = outlineStorage.bodyFont
        self.textColor = .label
        self.isEditable = true
        self.isSelectable = true
        self.autocorrectionType = .no
        self.autocapitalizationType = .sentences
        self.spellCheckingType = .no
        self.typingAttributes = outlineStorage.bodyStyle

        setUpToolbar()
    }

    // MARK: - Keyboard Toolbar

    private func setUpToolbar() {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()

        let appearance = UIToolbarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1.0)
                : .white
        }
        toolbar.standardAppearance = appearance
        toolbar.scrollEdgeAppearance = appearance

        let indentButton = UIBarButtonItem(
            image: UIImage(systemName: "increase.indent"),
            style: .plain, target: self, action: #selector(indentTapped)
        )
        let outdentButton = UIBarButtonItem(
            image: UIImage(systemName: "decrease.indent"),
            style: .plain, target: self, action: #selector(outdentTapped)
        )
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .plain, target: self, action: #selector(dismissTapped)
        )

        toolbar.items = [outdentButton, indentButton, flex, doneButton]
        self.inputAccessoryView = toolbar
    }

    @objc private func indentTapped() {
        outlineStorage.indentLine(at: selectedRange.location)
        outlineDelegate?.outlineTextViewDidChange(self)
    }

    @objc private func outdentTapped() {
        outlineStorage.outdentLine(at: selectedRange.location)
        outlineDelegate?.outlineTextViewDidChange(self)
    }

    @objc private func dismissTapped() {
        resignFirstResponder()
    }

    // MARK: - Key Commands (hardware keyboard)

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(indentTapped)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdentTapped))
        ]
    }

    // MARK: - Load Content

    func loadContent(_ text: String) {
        outlineStorage.load(text: text)
        typingAttributes = outlineStorage.bodyStyle
    }

    // MARK: - Get Deformatted Content

    func deformattedContent() -> String {
        outlineStorage.deformatted()
    }

    // MARK: - UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        outlineDelegate?.outlineTextViewDidBeginEditing(self)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        outlineDelegate?.outlineTextViewDidEndEditing(self)
    }

    func textViewDidChange(_ textView: UITextView) {
        // This is the key Simple-Notes pattern:
        // formatting happens HERE, not in processEditing().
        outlineStorage.processRichFormatting()

        // Reset typing attributes to match current line's depth
        resetTypingAttributes()

        outlineDelegate?.outlineTextViewDidChange(self)
    }

    // MARK: - Typing Attributes

    private func resetTypingAttributes() {
        typingAttributes = outlineStorage.bodyStyle
    }
}
