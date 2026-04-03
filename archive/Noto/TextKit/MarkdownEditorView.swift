import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "MarkdownEditorView")

// MARK: - Shared helper

/// Returns the character index after the frontmatter + "# " prefix.
/// Everything before this index is protected from editing.
func protectedRangeEnd(in text: String) -> Int {
    var offset = 0

    // Skip frontmatter
    if text.hasPrefix("---") {
        if let closeRange = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
            offset = text.distance(from: text.startIndex, to: closeRange.upperBound)
        } else if let closeRange = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
            offset = text.distance(from: text.startIndex, to: closeRange.upperBound)
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

// MARK: - iOS

#if os(iOS)
import UIKit

func effectiveCaretFont(from attributes: [NSAttributedString.Key: Any]) -> UIFont? {
    guard let font = attributes[.font] as? UIFont else { return nil }
    return font.pointSize < 1 ? MarkdownEditorTheme.bodyFont : font
}

func effectiveCaretFont(at characterOffset: Int, in storage: NSTextStorage) -> UIFont? {
    guard storage.length > 0 else { return nil }
    guard characterOffset >= 0, characterOffset <= storage.length else { return nil }
    let attributeOffset = min(characterOffset, storage.length - 1)
    let attrs = storage.attributes(at: attributeOffset, effectiveRange: nil)
    return effectiveCaretFont(from: attrs)
}

private class CheckboxOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit == self ? nil : hit
    }
}

/// UITextView subclass that fixes caret height to match the text line height,
/// excluding paragraph spacing that would otherwise make the caret too tall.
private class NotoTextView: UITextView {
    var onCheckboxTap: ((Int) -> Void)?
    private let checkboxOverlayView = CheckboxOverlayView()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureCheckboxOverlay()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCheckboxOverlay()
    }

    private func configureCheckboxOverlay() {
        checkboxOverlayView.backgroundColor = .clear
        checkboxOverlayView.isUserInteractionEnabled = true
        addSubview(checkboxOverlayView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        checkboxOverlayView.frame = bounds
        refreshTodoCheckboxButtons()
    }

    func refreshTodoCheckboxButtons() {
        checkboxOverlayView.subviews.forEach { $0.removeFromSuperview() }

        guard let markdownLayoutManager = layoutManager as? MarkdownLayoutManager else { return }
        let textOrigin = CGPoint(
            x: textContainerInset.left - contentOffset.x,
            y: textContainerInset.top - contentOffset.y
        )
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(MarkdownTodoCheckboxStyle.attributeKey, in: fullRange, options: []) { value, attrRange, _ in
            guard let isChecked = value as? Bool else { return }
            guard let checkboxRect = markdownLayoutManager.todoCheckboxRect(
                forCharacterRange: attrRange,
                in: self.textContainer,
                origin: textOrigin
            ) else { return }

            let button = UIButton(type: .custom)
            button.frame = checkboxRect.insetBy(dx: -8, dy: -8)
            button.backgroundColor = .clear
            button.tag = attrRange.location
            button.accessibilityIdentifier = "todo_checkbox_\(attrRange.location)"
            button.accessibilityLabel = isChecked ? "Checked todo item" : "Unchecked todo item"
            button.accessibilityTraits = isChecked ? [.button, .selected] : [.button]
            button.addTarget(self, action: #selector(todoCheckboxButtonTapped(_:)), for: .touchUpInside)
            checkboxOverlayView.addSubview(button)
        }
    }

        @objc private func todoCheckboxButtonTapped(_ sender: UIButton) {
            let wasFirstResponder = isFirstResponder
            onCheckboxTap?(sender.tag)
            if !wasFirstResponder, let markdownStorage = textStorage as? MarkdownTextStorage {
                markdownStorage.setActiveLine(nil, cursorPosition: nil)
                setNeedsLayout()
            }
        }

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)

        let charOffset = self.offset(from: beginningOfDocument, to: position)
        let storage = self.textStorage
        guard let font = effectiveCaretFont(at: charOffset, in: storage) else { return rect }
        let attributeOffset = min(max(charOffset, 0), storage.length - 1)
        let attrs = storage.attributes(at: attributeOffset, effectiveRange: nil)

        let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
        let lineSpacing = paragraphStyle?.lineSpacing ?? 0
        let targetHeight = font.lineHeight + lineSpacing

        if rect.size.height > targetHeight {
            let spacingBefore = paragraphStyle?.paragraphSpacingBefore ?? 0

            let nsText = (storage.string as NSString)
            let paraRange = nsText.paragraphRange(for: NSRange(location: charOffset, length: 0))
            let isFirstLine = (charOffset == paraRange.location) || isOnFirstVisualLine(charOffset: charOffset, paragraphStart: paraRange.location)

            if isFirstLine {
                rect.origin.y += spacingBefore
            }
            rect.size.height = targetHeight
        } else if rect.size.height < targetHeight {
            rect.size.height = targetHeight
        }

        return rect
    }

    private func isOnFirstVisualLine(charOffset: Int, paragraphStart: Int) -> Bool {
        guard let layoutManager = self.layoutManager as? NSLayoutManager else { return true }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: charOffset)
        let paraGlyphIndex = layoutManager.glyphIndexForCharacter(at: paragraphStart)
        var lineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
        return NSLocationInRange(paraGlyphIndex, lineRange)
    }
}

/// Transparent input accessory view that floats over content.
private class TransparentAccessoryView: UIView {
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        superview?.backgroundColor = .clear
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        superview?.backgroundColor = .clear
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit == self ? nil : hit
    }
}

/// SwiftUI wrapper around a UITextView with MarkdownTextStorage for live markdown rendering.
struct MarkdownEditorView: UIViewRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange)
    }

    func makeUIView(context: Context) -> UITextView {
        let textStorage = MarkdownTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NotoTextView(frame: .zero, textContainer: container)
        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 40, right: 12)
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.keyboardDismissMode = .interactive
        textView.accessibilityIdentifier = "note_editor"
        textView.delegate = context.coordinator
        textView.inputAccessoryView = context.coordinator.makeKeyboardToolbar(for: textView)

        textStorage.load(markdown: text)

        context.coordinator.textStorage = textStorage
        context.coordinator.textView = textView
        textView.onCheckboxTap = { [weak coordinator = context.coordinator] charIndex in
            coordinator?.handleCheckboxTap(at: charIndex)
        }
        textView.setNeedsLayout()

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
        // Skip if we're the source of the change (re-entrant from textViewDidChange)
        guard !context.coordinator.isUpdatingText else { return }
        // Skip if the user is actively typing — the binding may lag behind the
        // text storage by one render cycle, causing a just-typed character to be
        // reverted. External changes (e.g. iCloud sync) will apply when the
        // keyboard is dismissed.
        guard !textView.isFirstResponder else { return }
        if textStorage.markdownContent() != text {
            let selectedRange = textView.selectedRange
            textStorage.load(markdown: text)
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
        private var saveWorkItem: DispatchWorkItem?
        var isUpdatingText = false
        /// Guards against re-entrant shouldChangeTextIn during programmatic insertText.
        private var isInsertingProgrammatically = false

        /// Inserts text programmatically with re-entrancy guard.
        private func programmaticInsert(_ text: String, in textView: UITextView) {
            isInsertingProgrammatically = true
            textView.insertText(text)
            isInsertingProgrammatically = false
        }

        /// Replaces text at a range without triggering auto-continue logic.
        private func programmaticInsert(at range: NSRange, replacement: String, in textView: UITextView) {
            isInsertingProgrammatically = true
            textView.selectedRange = range
            textView.insertText(replacement)
            isInsertingProgrammatically = false
        }

        /// Deferred text replacement — schedules on next runloop tick.
        /// Used from shouldChangeTextIn to avoid confusing UIKit's text input system.
        private func deferredReplace(range: NSRange, with text: String, in textView: UITextView) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isInsertingProgrammatically = true
                textView.selectedRange = range
                textView.insertText(text)
                self.isInsertingProgrammatically = false
            }
        }

        init(text: Binding<String>, onTextChange: ((String) -> Void)?) {
            _text = text
            self.onTextChange = onTextChange
            super.init()
            observeKeyboard()
        }

        deinit {
            keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
            saveWorkItem?.cancel()
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
            let protectedEnd = protectedRangeEnd(in: fullText)

            if range.location < protectedEnd {
                return false
            }

            // Skip auto-continue if we're already doing a programmatic insert
            guard !isInsertingProgrammatically else { return true }

            // Auto-continue bullet/ordered lists on Enter
            if text == "\n" {
                let nsText = fullText as NSString
                guard range.location <= nsText.length else { return true }
                let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
                guard lineRange.length > 0, NSMaxRange(lineRange) <= nsText.length else { return true }
                let line = nsText.substring(with: lineRange)
                switch MarkdownEditingCommands.lineBreakAction(for: line) {
                case .none:
                    break
                case .insert(let insertion):
                    deferredReplace(range: range, with: insertion, in: textView)
                    return false
                case .removeCurrentLinePrefix(let prefixLength):
                    deferredReplace(
                        range: NSRange(location: lineRange.location, length: prefixLength),
                        with: "",
                        in: textView
                    )
                    return false
                }
            }

            return true
        }

        // MARK: - Keyboard Toolbar

        func makeKeyboardToolbar(for textView: UITextView) -> UIView {
            let pillHeight: CGFloat = 40
            let bottomMargin: CGFloat = 8
            let barHeight: CGFloat = pillHeight + bottomMargin
            let pillPadding: CGFloat = 12
            let buttonSize: CGFloat = 36
            let buttonSpacing: CGFloat = 4

            let wrapper = TransparentAccessoryView(frame: CGRect(x: 0, y: 0, width: 400, height: barHeight))
            wrapper.backgroundColor = .clear
            wrapper.autoresizingMask = .flexibleWidth

            let glassEffect = UIGlassEffect()
            glassEffect.isInteractive = true
            let pill = UIVisualEffectView(effect: glassEffect)
            pill.layer.cornerRadius = pillHeight / 2
            pill.clipsToBounds = true
            pill.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(pill)

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)

            let outdentButton = UIButton(type: .system)
            outdentButton.setImage(UIImage(systemName: "decrease.indent", withConfiguration: symbolConfig), for: .normal)
            outdentButton.tintColor = .white
            outdentButton.addTarget(self, action: #selector(outdentTapped), for: .touchUpInside)
            outdentButton.accessibilityLabel = "Outdent"
            outdentButton.accessibilityIdentifier = "outdentButton"

            let indentButton = UIButton(type: .system)
            indentButton.setImage(UIImage(systemName: "increase.indent", withConfiguration: symbolConfig), for: .normal)
            indentButton.tintColor = .white
            indentButton.addTarget(self, action: #selector(indentTapped), for: .touchUpInside)
            indentButton.accessibilityLabel = "Indent"
            indentButton.accessibilityIdentifier = "indentButton"

            let todoButton = UIButton(type: .system)
            todoButton.setImage(UIImage(systemName: "checklist", withConfiguration: symbolConfig), for: .normal)
            todoButton.tintColor = .white
            todoButton.addTarget(self, action: #selector(todoTapped), for: .touchUpInside)
            todoButton.accessibilityLabel = "Todo"
            todoButton.accessibilityIdentifier = "todoButton"

            let stack = UIStackView(arrangedSubviews: [outdentButton, indentButton, todoButton])
            stack.axis = .horizontal
            stack.spacing = buttonSpacing
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false
            pill.contentView.addSubview(stack)

            NSLayoutConstraint.activate([
                pill.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -12),
                pill.topAnchor.constraint(equalTo: wrapper.topAnchor),
                pill.heightAnchor.constraint(equalToConstant: pillHeight),
                stack.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor, constant: pillPadding),
                stack.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor, constant: -pillPadding),
                stack.centerYAnchor.constraint(equalTo: pill.contentView.centerYAnchor),
                outdentButton.widthAnchor.constraint(equalToConstant: buttonSize),
                outdentButton.heightAnchor.constraint(equalToConstant: buttonSize),
                indentButton.widthAnchor.constraint(equalToConstant: buttonSize),
                indentButton.heightAnchor.constraint(equalToConstant: buttonSize),
                todoButton.widthAnchor.constraint(equalToConstant: buttonSize),
                todoButton.heightAnchor.constraint(equalToConstant: buttonSize),
            ])

            return wrapper
        }

        @objc private func indentTapped() {
            guard let textView else { return }
            let nsText = textView.text as NSString
            let cursorPos = textView.selectedRange.location
            guard cursorPos <= nsText.length else { return }

            let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
            let line = nsText.substring(with: lineRange)
            let transformed = MarkdownEditingCommands.indentedLine(line)
            self.programmaticInsert(at: lineRange, replacement: transformed, in: textView)
            textView.selectedRange = NSRange(location: cursorPos + 2, length: 0)
        }

        @objc private func outdentTapped() {
            guard let textView else { return }
            let nsText = textView.text as NSString
            let cursorPos = textView.selectedRange.location
            guard cursorPos <= nsText.length else { return }

            let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
            let line = nsText.substring(with: lineRange)
            let transformed = MarkdownEditingCommands.outdentedLine(line)
            guard transformed != line else { return }

            let delta = transformed.count - line.count
            self.programmaticInsert(at: lineRange, replacement: transformed, in: textView)
            let newCursor = max(cursorPos + delta, lineRange.location)
            textView.selectedRange = NSRange(location: newCursor, length: 0)
        }

        @objc private func todoTapped() {
            guard let textView else { return }
            let nsText = textView.text as NSString
            let cursorPos = textView.selectedRange.location
            guard cursorPos <= nsText.length else { return }

            let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
            let line = nsText.substring(with: lineRange)
            let transformed = TodoMarkdown.toolbarToggledLine(line)
            let delta = transformed.count - line.count
            self.programmaticInsert(at: lineRange, replacement: transformed, in: textView)
            let newCursor = max(lineRange.location, min(cursorPos + delta, lineRange.location + transformed.count))
            textView.selectedRange = NSRange(location: newCursor, length: 0)
            textView.setNeedsLayout()
        }

        func handleCheckboxTap(at charIndex: Int) {
            guard let textView else { return }
            let nsText = textView.text as NSString
            let lineRange = nsText.lineRange(for: NSRange(location: charIndex, length: 0))
            let line = nsText.substring(with: lineRange)
            let transformed = TodoMarkdown.checkboxToggledLine(line)
            guard transformed != line else { return }

            let selection = textView.selectedRange
            let delta = transformed.count - line.count
            self.programmaticInsert(at: lineRange, replacement: transformed, in: textView)
            let newLocation = max(lineRange.location, min(selection.location + delta, lineRange.location + transformed.count))
            textView.selectedRange = NSRange(location: newLocation, length: selection.length)
            textView.setNeedsLayout()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Skip during programmatic inserts to avoid re-entrant formatting
            guard !isInsertingProgrammatically else { return }

            let fullText = textView.text ?? ""
            let protectedEnd = protectedRangeEnd(in: fullText)
            let selection = textView.selectedRange

            if selection.location < protectedEnd {
                let newLocation = protectedEnd
                let newLength = max(0, selection.length - (protectedEnd - selection.location))
                textView.selectedRange = NSRange(location: newLocation, length: newLength)
            }

            let nsText = fullText as NSString
            let cursorPos = textView.selectedRange.location
            if cursorPos <= nsText.length {
                let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
                textStorage?.setActiveLine(lineRange, cursorPosition: cursorPos)
            }
            textView.setNeedsLayout()
        }

        func textViewDidChange(_ textView: UITextView) {
            let nsText = (textView.text ?? "") as NSString
            let cursorPos = min(textView.selectedRange.location, nsText.length)
            let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
            textStorage?.render(activeLine: lineRange, cursorPosition: cursorPos)

            guard let content = textStorage?.markdownContent() else { return }
            isUpdatingText = true
            self.text = content
            isUpdatingText = false
            onTextChange?(content)
            textView.setNeedsLayout()
        }

        func flushPendingSave() {
            saveWorkItem?.cancel()
            guard let content = textStorage?.markdownContent() else { return }
            isUpdatingText = true
            self.text = content
            isUpdatingText = false
            onTextChange?(content)
        }
    }
}

// MARK: - macOS

#elseif os(macOS)
import AppKit

/// SwiftUI wrapper around NSTextView with MarkdownTextStorage for live markdown rendering.
struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = MarkdownTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.setAccessibilityIdentifier("note_editor")

        textStorage.load(markdown: text)

        context.coordinator.textStorage = textStorage
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        if autoFocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: textStorage.length, length: 0))
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textStorage = context.coordinator.textStorage,
              let textView = context.coordinator.textView else { return }
        guard !context.coordinator.isUpdatingText else { return }
        if textStorage.markdownContent() != text {
            let selectedRange = textView.selectedRange()
            textStorage.load(markdown: text)
            if selectedRange.location + selectedRange.length <= textStorage.length {
                textView.setSelectedRange(selectedRange)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onTextChange: ((String) -> Void)?
        weak var textStorage: MarkdownTextStorage?
        weak var textView: NSTextView?
        var isUpdatingText = false

        init(text: Binding<String>, onTextChange: ((String) -> Void)?) {
            _text = text
            self.onTextChange = onTextChange
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            let fullText = textView.string
            let protectedEnd = protectedRangeEnd(in: fullText)

            if affectedCharRange.location < protectedEnd {
                return false
            }

            // Auto-continue bullet/ordered lists on Enter
            if let replacement = replacementString, replacement == "\n" {
                let nsText = fullText as NSString
                let lineRange = nsText.lineRange(for: NSRange(location: affectedCharRange.location, length: 0))
                let line = nsText.substring(with: lineRange)
                switch MarkdownEditingCommands.lineBreakAction(for: line) {
                case .none:
                    break
                case .insert(let insertion):
                    textView.insertText(insertion, replacementRange: affectedCharRange)
                    return false
                case .removeCurrentLinePrefix(let prefixLength):
                    let prefixRange = NSRange(location: lineRange.location, length: prefixLength)
                    textView.insertText("", replacementRange: prefixRange)
                    return false
                }
            }

            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let fullText = textView.string
            let protectedEnd = protectedRangeEnd(in: fullText)
            let selection = textView.selectedRange()

            if selection.location < protectedEnd {
                let newLocation = protectedEnd
                let newLength = max(0, selection.length - (protectedEnd - selection.location))
                textView.setSelectedRange(NSRange(location: newLocation, length: newLength))
            }

            let nsText = fullText as NSString
            let cursorPos = textView.selectedRange().location
            if cursorPos <= nsText.length {
                let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
                textStorage?.setActiveLine(lineRange, cursorPosition: cursorPos)
            }
        }

        func textDidChange(_ notification: Notification) {
            if let textView {
                let nsText = textView.string as NSString
                let cursorPos = min(textView.selectedRange().location, nsText.length)
                let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
                textStorage?.render(activeLine: lineRange, cursorPosition: cursorPos)
            }

            guard let content = textStorage?.markdownContent() else { return }
            isUpdatingText = true
            self.text = content
            isUpdatingText = false
            onTextChange?(content)
        }
    }
}
#endif
