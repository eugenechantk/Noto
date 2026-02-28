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
        self.dataDetectorTypes = [.link, .phoneNumber]
        self.font = noteTextStorage.bodyFont
        self.textColor = .label
        self.isSelectable = true

        resetTypingAttributes()
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

    // MARK: - User Interaction

    private var initialTouchY: CGFloat = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        initialTouchY = touches.first!.location(in: self).y
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        let swipeDistance = abs(touch.location(in: self).y - initialTouchY)
        if  swipeDistance <= 10 {
            if !didTapNoteView(touch) {
                super.touchesEnded(touches, with: event)
            }
        }
    }

    @objc private func didTapNoteView(_ touch: UITouch) -> Bool {
        var location = touch.location(in: self)
        location.x -= self.textContainerInset.left;
        location.y -= self.textContainerInset.top;

        var unitInsertionPoint: CGFloat = 0
        let charIndex = self.layoutManager.characterIndex(
            for: location,
            in: self.textContainer,
            fractionOfDistanceBetweenInsertionPoints: &unitInsertionPoint
        )
        assert(unitInsertionPoint >= 0.0 && unitInsertionPoint <= 1.0)

        if !detectTappableText(at: charIndex, with: unitInsertionPoint) {
            startEditing(at: charIndex, with: unitInsertionPoint)
            return true
        } else {
            return false
        }
    }

    private func detectTappableText(at charIndex: Int,
                                    with unitInsertionPoint: CGFloat) -> Bool {
        guard charIndex < self.textStorage.length else {
            return false
        }

        let noteText = self.attributedText!
        let tappableAttribs: [NSAttributedString.Key] = [.link, .list]
        for attrib in tappableAttribs {
            var attribRange = NSRange(location: 0, length: 0)
            let attribValue = noteText.attribute(attrib, at: charIndex,
                                                 effectiveRange: &attribRange)
            guard let _ = attribValue else {
                continue
            }
            guard !(charIndex == attribRange.max - 1 && unitInsertionPoint == 1.0) else {
                continue
            }
            return true
        }
        return false
    }

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

    private func startEditing(at charIndex: Int, with unitInsertionPoint: CGFloat) {
        var charIndex = charIndex
        if character(at: charIndex) != "\n" {
            charIndex += Int(unitInsertionPoint.rounded())
        }
        selectedRange = NSRange(location: charIndex, length: 0)

        isEditable = true
        becomeFirstResponder()
        resetTypingAttributes()
    }

    func endEditing() {
        endEditing(false)
        isEditable = false
        resignFirstResponder()
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

    private func textRange(from range: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: range.location) else {
            return nil
        }
        guard let end = position(from: beginningOfDocument, offset: range.max) else {
            return nil
        }
        return textRange(from: start, to: end)
    }

    // MARK: - Helpers

    private func character(at charIndex: Int) -> String? {
        return attributedText!.character(at: charIndex)
    }
}
