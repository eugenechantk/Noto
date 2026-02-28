//
//  NoteTextView.swift
//  Noto
//
//  Based on Simple Notes by Paulo Mattos.
//  Custom UITextView subclass for showing & editing notes with rich formatting.
//

import UIKit

protocol NoteTextViewDelegate: AnyObject {
    func noteTextViewDidBeginEditing(_ noteTextView: NoteTextView)
    func noteTextViewDidEndEditing(_ noteTextView: NoteTextView)
    func noteTextViewDidChange(_ noteTextView: NoteTextView)
}

/// Custom `UITextView` subclass for showing & editing a given note.
final class NoteTextView: UITextView, UITextViewDelegate, UITextPasteDelegate {

    private var noteTextStorage: NoteTextStorage {
        return textStorage as! NoteTextStorage
    }

    // MARK: - View Initializers

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setUpNoteTextView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setUpNoteTextView()
    }

    private func setUpNoteTextView() {
        self.delegate = self
        self.pasteDelegate = self
        self.spellCheckingType = .no
        self.autocorrectionType = .no
        self.autocapitalizationType = .sentences
        self.font = noteTextStorage.bodyFont
        self.textColor = .label
        self.isEditable = true
        self.isSelectable = true

        resetTypingAttributes()
        setUpInputAccessoryBar()
        registerForKeyboardNotifications()
    }

    private func setUpInputAccessoryBar() {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()

        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .plain,
            target: self,
            action: #selector(dismissKeyboardTapped)
        )
        toolbar.items = [flexSpace, doneButton]
        self.inputAccessoryView = toolbar
    }

    @objc private func dismissKeyboardTapped() {
        resignFirstResponder()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func resetTypingAttributes() {
        typingAttributes = noteTextStorage.bodyStyle
    }

    func loadNote(_ contents: String) {
        noteTextStorage.load(note: contents)
        layoutCheckmarkViews()
    }

    /// Returns the deformatted markdown-ish string.
    func deformattedContents() -> String {
        return noteTextStorage.deformatted()
    }

    // MARK: - Delegate

    weak var noteTextViewDelegate: NoteTextViewDelegate?

    // MARK: - Fixes Copy & Paste Bug

    func textPasteConfigurationSupporting(
        _ textPasteConfigurationSupporting: UITextPasteConfigurationSupporting,
        shouldAnimatePasteOf attributedString: NSAttributedString,
        to textRange: UITextRange) -> Bool {
        return false
    }

    // MARK: - Editing Flow

    func textViewDidBeginEditing(_ textView: UITextView) {
        oldSelectedRange = selectedRange
        noteTextViewDelegate?.noteTextViewDidBeginEditing(self)
    }

    func textViewDidEndEditing(_ noteView: UITextView) {
        noteTextViewDelegate?.noteTextViewDidEndEditing(self)
    }

    func textViewDidChange(_ noteView: UITextView) {
        let formattedText = noteTextStorage.processRichFormatting()
        if let caretRange = formattedText?.caretRange {
            fixCaretPosition(in: caretRange)
        }
        resetTypingAttributes()
        layoutCheckmarkViews()
        noteTextViewDelegate?.noteTextViewDidChange(self)
    }

    private func fixCaretPosition(in caretRange: NSRange) {
        let caretRange = noteTextStorage.lineRange(for: caretRange.location)
        guard let caret = noteTextStorage.attribute(.caret, in: caretRange).first else {
            return
        }
        DispatchQueue.main.async {
            self.noteTextStorage.removeAttribute(.caret, range: caret.range)
            self.setCaretPosition(to: caret.range.max)
        }
    }

    private func setCaretPosition(to caret: Int) {
        self.selectedRange = NSRange(location: caret, length: 0)
        self.resetTypingAttributes()
    }

    private var oldSelectedRange: NSRange?

    /// Dirty hack to ignore ZERO WIDTH SPACE characters.
    func textViewDidChangeSelection(_ textView: UITextView) {
        guard let oldSelectedRange = self.oldSelectedRange else { return }

        if let char = character(at: selectedRange.location), char == zeroWidthSpace {
            let dir = (selectedRange.location - oldSelectedRange.location) >= 0 ? 1 : -1
            let newSelectedRange = NSMakeRange(selectedRange.location + dir, 0)
            DispatchQueue.main.async {
                self.selectedRange = newSelectedRange
            }
        }
        self.oldSelectedRange = selectedRange
    }

    // MARK: - Checkmarks Views Overlay

    func insertCheckmarkAtCaretPosition() {
        noteTextStorage.insertCheckmark(at: selectedRange.location, withValue: false)
        moveCaretToLineEnd(at: selectedRange.location)
        layoutCheckmarkViews()
    }

    private func moveCaretToLineEnd(at index: Int) {
        guard index < noteTextStorage.length - 1 else {
            fixCaretPosition(in: NSMakeRange(index, 0))
            return
        }
        let lineRange = noteTextStorage.lineRange(for: index)
        DispatchQueue.main.async {
            self.setCaretPosition(to: lineRange.max - 1)
        }
    }

    private func reuseCheckmarkView() -> CheckmarkView {
        let checkmarkView = CheckmarkView()
        checkmarkView.frame = CGRect(x: 0, y: 0, width: 25, height: 25)
        checkmarkView.addTarget(
            self, action: #selector(didTapCheckmark),
            for: .primaryActionTriggered
        )
        return checkmarkView
    }

    @IBAction private func didTapCheckmark(_ checkmarkView: CheckmarkView) {
        precondition(checkmarkView.tag >= 0 && checkmarkView.tag < noteTextStorage.length)
        noteTextStorage.setCheckmark(
            atLine: NSRange(location: checkmarkView.tag, length: 0),
            to: checkmarkView.tickShown
        )
    }

    private var checkmarkViews: [CheckmarkView] = []

    private func layoutCheckmarkViews() {
        for checkmarkView in checkmarkViews {
            checkmarkView.removeFromSuperview()
        }
        checkmarkViews.removeAll()

        noteTextStorage.enumerateAttribute(.list, in: noteTextStorage.range) {
            (attribValue, attribRange, stop) in
            guard let attribValue = attribValue as? String else { return }
            guard let listItem = ListItem(rawValue: attribValue) else { return }
            guard case let ListItem.checkmark(checkmarkValue) = listItem else { return }

            let textRange = self.textRange(from: attribRange)!
            let checkmarkRect = self.firstRect(for: textRange)

            let checkmarkView = self.reuseCheckmarkView()
            checkmarkView.tag = attribRange.location
            checkmarkView.showTick(checkmarkValue!)

            checkmarkView.frame.origin = CGPoint(
                x: 0,
                y: checkmarkRect.midY - checkmarkView.frame.height/2 + 0.5
            )
            self.addSubview(checkmarkView)
            self.checkmarkViews.append(checkmarkView)
        }
    }

    // Gate all automatic scrolling. Only allow scroll when:
    // 1. The user is physically dragging/scrolling, OR
    // 2. The caret is actually below the visible area
    private var isUserScrolling = false

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        if isUserScrolling || isDecelerating {
            super.setContentOffset(contentOffset, animated: animated)
            return
        }

        // Check if the caret is currently visible
        guard let selectedTextRange = selectedTextRange else {
            super.setContentOffset(contentOffset, animated: animated)
            return
        }
        let caret = caretRect(for: selectedTextRange.start)
        let visibleHeight = bounds.height - contentInset.bottom
        let visibleBottom = self.contentOffset.y + visibleHeight

        // Only scroll if the caret is below the visible area
        if caret.maxY > visibleBottom {
            // Scroll just enough to bring the caret to the bottom
            let targetY = caret.maxY - visibleHeight + 20
            let clampedY = max(min(targetY, contentSize.height - visibleHeight), 0)
            super.setContentOffset(CGPoint(x: self.contentOffset.x, y: clampedY), animated: animated)
        }
        // Otherwise: don't scroll at all
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserScrolling = true
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            isUserScrolling = false
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isUserScrolling = false
    }

    private func textRange(from range: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: range.location) else {
            return nil
        }
        guard let end = position(from: beginningOfDocument, offset: range.max) else {
            return nil
        }
        return textRange(from: start, to: end)
    }

    // MARK: - Keyboard Management

    private var oldContentInset: UIEdgeInsets?
    private var oldScrollIndicatorInsets: UIEdgeInsets?

    private func registerForKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(notification:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(notification:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(notification: NSNotification) {
        guard let info = notification.userInfo,
              let keyboardFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }

        let keyboardHeight = keyboardFrame.height
        let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)

        oldContentInset = contentInset
        oldScrollIndicatorInsets = verticalScrollIndicatorInsets

        contentInset = contentInsets
        verticalScrollIndicatorInsets = contentInsets
    }

    @objc private func keyboardWillHide(notification: NSNotification) {
        if let oldContentInset = oldContentInset {
            contentInset = oldContentInset
        }
        if let oldScrollIndicatorInsets = oldScrollIndicatorInsets {
            verticalScrollIndicatorInsets = oldScrollIndicatorInsets
        }
    }

    // MARK: - Helpers

    private func character(at charIndex: Int) -> String? {
        return attributedText!.character(at: charIndex)
    }
}
