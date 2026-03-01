//
//  NoteTextView.swift
//  Noto
//
//  Based on Simple Notes by Paulo Mattos.
//  Custom UITextView subclass for showing & editing notes with rich formatting.
//

import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteTextView")

protocol NoteTextViewDelegate: AnyObject {
    func noteTextViewDidBeginEditing(_ noteTextView: NoteTextView)
    func noteTextViewDidEndEditing(_ noteTextView: NoteTextView)
    func noteTextViewDidChange(_ noteTextView: NoteTextView)
    func noteTextView(_ noteTextView: NoteTextView, moveLineAt sourceIndex: Int, toLineAt destinationIndex: Int)
    func noteTextView(_ noteTextView: NoteTextView, didDoubleTapLineAt lineIndex: Int)
}

/// Custom `UITextView` subclass for showing & editing a given note.
final class NoteTextView: UITextView, UITextViewDelegate, UITextPasteDelegate, UIGestureRecognizerDelegate {

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

    /// When true, a double-tap gesture is enabled for navigation.
    var enableDoubleTapNavigation = false {
        didSet { setUpDoubleTapGesture() }
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
        setUpReorderGesture()
    }

    private func setUpInputAccessoryBar() {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()

        let indentButton = UIBarButtonItem(
            image: UIImage(systemName: "increase.indent"),
            style: .plain,
            target: self,
            action: #selector(indentCurrentLine)
        )
        let outdentButton = UIBarButtonItem(
            image: UIImage(systemName: "decrease.indent"),
            style: .plain,
            target: self,
            action: #selector(outdentCurrentLine)
        )
        let moveUpButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up"),
            style: .plain,
            target: self,
            action: #selector(moveCurrentLineUp)
        )
        moveUpButton.accessibilityIdentifier = "moveUp"
        moveUpButton.accessibilityLabel = "Move Up"
        let moveDownButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.down"),
            style: .plain,
            target: self,
            action: #selector(moveCurrentLineDown)
        )
        moveDownButton.accessibilityIdentifier = "moveDown"
        moveDownButton.accessibilityLabel = "Move Down"
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .plain,
            target: self,
            action: #selector(dismissKeyboardTapped)
        )
        doneButton.accessibilityIdentifier = "dismissKeyboard"
        doneButton.accessibilityLabel = "Dismiss Keyboard"
        toolbar.items = [indentButton, outdentButton, moveUpButton, moveDownButton, flexSpace, doneButton]
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

    // MARK: - Indent / Outdent

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(indentCurrentLine)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdentCurrentLine)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: .alternate, action: #selector(moveCurrentLineUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: .alternate, action: #selector(moveCurrentLineDown))
        ]
    }

    @objc private func indentCurrentLine() {
        noteTextStorage.indentLine(at: selectedRange.location)
        noteTextViewDelegate?.noteTextViewDidChange(self)
    }

    @objc private func outdentCurrentLine() {
        noteTextStorage.outdentLine(at: selectedRange.location)
        noteTextViewDelegate?.noteTextViewDidChange(self)
    }

    // MARK: - Move Line Up / Down

    @objc private func moveCurrentLineUp() {
        guard let lineIdx = lineIndexAtCursor(), lineIdx > 0 else { return }
        // Move line at lineIdx to before the previous line (insertion index = lineIdx - 1)
        noteTextViewDelegate?.noteTextView(self, moveLineAt: lineIdx, toLineAt: lineIdx - 1)
    }

    @objc private func moveCurrentLineDown() {
        guard let lineIdx = lineIndexAtCursor(), lineIdx < lineCount() - 1 else { return }
        // Move line at lineIdx to after the next line (insertion index = lineIdx + 2)
        noteTextViewDelegate?.noteTextView(self, moveLineAt: lineIdx, toLineAt: lineIdx + 2)
    }

    /// Returns the line index where the cursor currently sits.
    private func lineIndexAtCursor() -> Int? {
        let charIndex = selectedRange.location
        guard charIndex <= textStorage.length else { return nil }
        let prefix = textStorage.string.prefix(charIndex)
        return prefix.filter({ $0 == "\n" }).count
    }

    // MARK: - Long-Press Drag Reorder

    private struct DragState {
        let sourceLineIndex: Int
        let sourceLineRange: NSRange
        let snapshotView: UIView
        let snapshotOffsetY: CGFloat
        let insertionIndicator: UIView
        var currentTargetIndex: Int
    }

    private var dragState: DragState?
    private var reorderGesture: UILongPressGestureRecognizer?
    private var autoScrollTimer: CADisplayLink?
    private var autoScrollSpeed: CGFloat = 0

    private func setUpReorderGesture() {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleReorderGesture(_:)))
        gesture.minimumPressDuration = 0.3
        gesture.delegate = self
        addGestureRecognizer(gesture)
        reorderGesture = gesture
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow double-tap navigation to fire alongside text selection
        if gestureRecognizer === doubleTapGesture || otherGestureRecognizer === doubleTapGesture {
            return true
        }
        return false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === reorderGesture else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        // Only start if the touch is on a valid line
        let point = gestureRecognizer.location(in: self)
        return lineIndex(at: point) != nil
    }

    /// Make text interaction gestures (selection, magnifying glass) require our
    /// reorder gesture to fail first, giving reorder priority on long-press.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === reorderGesture else { return false }
        // If the other gesture belongs to UITextInteraction, defer it
        let otherName = String(describing: type(of: otherGestureRecognizer))
        return otherName.contains("TextInteraction") || otherName.contains("TextSelection")
    }

    @objc private func handleReorderGesture(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            reorderBegan(gesture)
        case .changed:
            reorderChanged(gesture)
        case .ended:
            reorderEnded(gesture)
        case .cancelled, .failed:
            reorderCancelled()
        default:
            break
        }
    }

    // MARK: Reorder — .began

    private func reorderBegan(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)
        guard let lineIdx = lineIndex(at: point) else { return }
        guard let lineRange = rangeForLine(lineIdx) else { return }
        let lineRect = rectForLine(lineIdx)

        // Dismiss keyboard and disable editing during drag
        resignFirstResponder()
        isEditable = false

        // Snapshot of the line
        let snapshot = createLineSnapshot(for: lineRect)
        snapshot.center = CGPoint(x: lineRect.midX, y: lineRect.midY)
        addSubview(snapshot)

        let offsetY = point.y - lineRect.midY

        // Insertion indicator
        let indicator = UIView()
        indicator.backgroundColor = tintColor
        indicator.frame = CGRect(x: textContainerInset.left, y: lineRect.minY, width: bounds.width - textContainerInset.left - textContainerInset.right, height: 2)
        indicator.layer.cornerRadius = 1
        addSubview(indicator)

        // Dim source line
        dimLine(at: lineIdx, alpha: 0.15)

        // Haptic
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        dragState = DragState(
            sourceLineIndex: lineIdx,
            sourceLineRange: lineRange,
            snapshotView: snapshot,
            snapshotOffsetY: offsetY,
            insertionIndicator: indicator,
            currentTargetIndex: lineIdx
        )
    }

    // MARK: Reorder — .changed

    private func reorderChanged(_ gesture: UILongPressGestureRecognizer) {
        guard var state = dragState else { return }
        let point = gesture.location(in: self)

        // Move snapshot to follow touch
        state.snapshotView.center.y = point.y - state.snapshotOffsetY

        // Compute target insertion index
        let totalLines = lineCount()
        var targetIndex = state.sourceLineIndex
        for i in 0..<totalLines {
            let lineRect = rectForLine(i)
            if point.y < lineRect.midY {
                targetIndex = i
                break
            }
            targetIndex = i + 1
        }
        targetIndex = max(0, min(targetIndex, totalLines))

        // Reposition insertion indicator
        let indicatorY: CGFloat
        if targetIndex < totalLines {
            indicatorY = rectForLine(targetIndex).minY - 1
        } else {
            indicatorY = rectForLine(totalLines - 1).maxY - 1
        }
        state.insertionIndicator.frame.origin.y = indicatorY

        // Haptic on target change
        if targetIndex != state.currentTargetIndex {
            let light = UIImpactFeedbackGenerator(style: .light)
            light.impactOccurred()
            state.currentTargetIndex = targetIndex
        }

        dragState = state

        // Auto-scroll near edges
        handleAutoScroll(touchY: point.y)
    }

    // MARK: Reorder — .ended

    private func reorderEnded(_ gesture: UILongPressGestureRecognizer) {
        guard let state = dragState else { return }
        let source = state.sourceLineIndex
        let destination = state.currentTargetIndex

        cleanUpDrag()

        // Notify delegate if position actually changed
        // destination == source or destination == source + 1 means no-op
        if destination != source && destination != source + 1 {
            noteTextViewDelegate?.noteTextView(self, moveLineAt: source, toLineAt: destination)
        }
    }

    // MARK: Reorder — .cancelled

    private func reorderCancelled() {
        cleanUpDrag()
    }

    // MARK: Reorder — cleanup

    private func cleanUpDrag() {
        guard let state = dragState else { return }

        state.snapshotView.removeFromSuperview()
        state.insertionIndicator.removeFromSuperview()

        // Restore source line opacity
        restoreLineDim(at: state.sourceLineIndex)

        dragState = nil
        isEditable = true

        stopAutoScroll()
    }

    // MARK: Reorder — line geometry helpers

    private func lineIndex(at point: CGPoint) -> Int? {
        let adjustedPoint = CGPoint(
            x: point.x - textContainerInset.left,
            y: point.y - textContainerInset.top
        )
        let charIndex = layoutManager.characterIndex(
            for: adjustedPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard charIndex < textStorage.length else { return nil }

        let text = textStorage.string
        var lineIdx = 0
        var searchStart = text.startIndex
        while searchStart < text.endIndex {
            let lineEnd = text[searchStart...].firstIndex(of: "\n") ?? text.endIndex
            let nsLoc = text.distance(from: text.startIndex, to: searchStart)
            let nsEnd = text.distance(from: text.startIndex, to: lineEnd)
            if charIndex >= nsLoc && charIndex <= nsEnd {
                return lineIdx
            }
            if lineEnd < text.endIndex {
                searchStart = text.index(after: lineEnd)
            } else {
                break
            }
            lineIdx += 1
        }
        return lineIdx
    }

    private func lineCount() -> Int {
        let text = textStorage.string
        if text.isEmpty { return 1 }
        return text.components(separatedBy: "\n").count
    }

    private func rangeForLine(_ index: Int) -> NSRange? {
        let text = textStorage.string
        let lines = text.components(separatedBy: "\n")
        guard index >= 0 && index < lines.count else { return nil }

        var location = 0
        for i in 0..<index {
            location += lines[i].count + 1 // +1 for newline
        }
        let length = lines[index].count
        return NSRange(location: location, length: length)
    }

    private func rectForLine(_ index: Int) -> CGRect {
        guard let range = rangeForLine(index) else { return .zero }
        // Use at least length 1 so empty lines still have a rect
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: range.location, length: max(range.length, 1)),
            actualCharacterRange: nil
        )
        var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        lineRect.origin.x += textContainerInset.left
        lineRect.origin.y += textContainerInset.top
        lineRect.size.width = bounds.width - textContainerInset.left - textContainerInset.right
        return lineRect
    }

    private func createLineSnapshot(for rect: CGRect) -> UIView {
        let snapshot = UIView(frame: rect)
        snapshot.backgroundColor = .systemBackground

        // Render the line region into an image
        let renderer = UIGraphicsImageRenderer(bounds: rect)
        let image = renderer.image { ctx in
            self.layer.render(in: ctx.cgContext)
        }
        let imageView = UIImageView(image: image)
        imageView.frame = snapshot.bounds
        snapshot.addSubview(imageView)

        // Shadow and slight scale
        snapshot.layer.shadowColor = UIColor.black.cgColor
        snapshot.layer.shadowOpacity = 0.25
        snapshot.layer.shadowRadius = 8
        snapshot.layer.shadowOffset = CGSize(width: 0, height: 2)
        snapshot.transform = CGAffineTransform(scaleX: 1.03, y: 1.03)
        snapshot.alpha = 0.9

        return snapshot
    }

    // MARK: Reorder — visual feedback helpers

    private func dimLine(at lineIndex: Int, alpha: CGFloat) {
        guard let range = rangeForLine(lineIndex) else { return }
        textStorage.addAttribute(.foregroundColor, value: UIColor.label.withAlphaComponent(alpha), range: range)
    }

    private func restoreLineDim(at lineIndex: Int) {
        guard let range = rangeForLine(lineIndex) else { return }
        textStorage.addAttribute(.foregroundColor, value: UIColor.label, range: range)
    }

    // MARK: Reorder — auto-scroll

    private func handleAutoScroll(touchY: CGFloat) {
        let visibleTop = contentOffset.y
        let visibleBottom = contentOffset.y + bounds.height - contentInset.bottom
        let edgeMargin: CGFloat = 50

        if touchY < visibleTop + edgeMargin {
            autoScrollSpeed = -4.0
            startAutoScroll()
        } else if touchY > visibleBottom - edgeMargin {
            autoScrollSpeed = 4.0
            startAutoScroll()
        } else {
            stopAutoScroll()
        }
    }

    private func startAutoScroll() {
        guard autoScrollTimer == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(autoScrollTick))
        link.add(to: .main, forMode: .common)
        autoScrollTimer = link
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollSpeed = 0
    }

    @objc private func autoScrollTick() {
        guard dragState != nil else {
            stopAutoScroll()
            return
        }
        let maxY = max(contentSize.height - bounds.height + contentInset.bottom, 0)
        let newY = min(max(contentOffset.y + autoScrollSpeed, 0), maxY)
        contentOffset.y = newY
    }

    // MARK: - Double-Tap Navigation

    private var doubleTapGesture: UITapGestureRecognizer?

    private func setUpDoubleTapGesture() {
        // Remove existing gesture if any
        if let existing = doubleTapGesture {
            removeGestureRecognizer(existing)
            doubleTapGesture = nil
        }
        guard enableDoubleTapNavigation else { return }

        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        gesture.numberOfTapsRequired = 2
        gesture.delegate = self
        addGestureRecognizer(gesture)
        doubleTapGesture = gesture
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        guard let lineIdx = lineIndex(at: point) else { return }
        noteTextViewDelegate?.noteTextView(self, didDoubleTapLineAt: lineIdx)
    }

    // MARK: - Helpers

    private func character(at charIndex: Int) -> String? {
        return attributedText!.character(at: charIndex)
    }
}
