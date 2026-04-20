#if os(macOS)
import AppKit
import SwiftUI

struct BlockEditorView: NSViewControllerRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange, autoFocus: autoFocus)
    }

    func makeNSViewController(context: Context) -> BlockEditorViewController {
        let viewController = BlockEditorViewController()
        viewController.coordinator = context.coordinator
        viewController.loadMarkdown(text)
        return viewController
    }

    func updateNSViewController(_ viewController: BlockEditorViewController, context: Context) {
        guard !context.coordinator.isUpdatingText else { return }
        guard !viewController.isActivelyEditing else { return }
        if viewController.currentMarkdown() != text {
            viewController.loadMarkdown(text)
        }
    }

    final class Coordinator {
        @Binding var text: String
        var onTextChange: ((String) -> Void)?
        var isUpdatingText = false
        let autoFocus: Bool

        init(text: Binding<String>, onTextChange: ((String) -> Void)?, autoFocus: Bool) {
            _text = text
            self.onTextChange = onTextChange
            self.autoFocus = autoFocus
        }

        func textDidChange(_ markdown: String) {
            isUpdatingText = true
            text = markdown
            isUpdatingText = false
            onTextChange?(markdown)
        }
    }
}

final class BlockEditorViewController: NSViewController {
    var coordinator: BlockEditorView.Coordinator?

    private var document = BlockDocument(blocks: [])
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let stackView = NSStackView()
    private var rowViews: [UUID: BlockRowView] = [:]
    private var focusedIndex: Int?
    private var focusedOffset: Int?
    private(set) var isActivelyEditing = false

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        documentView.translatesAutoresizingMaskIntoConstraints = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)

        view.addSubview(scrollView)
        scrollView.documentView = documentView
        documentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    func loadMarkdown(_ markdown: String) {
        document = BlockDocument(blocks: BlockParser.parse(markdown))
        reloadRows()

        if coordinator?.autoFocus == true, let lastEditableIndex = lastEditableBlockIndex() {
            focusBlock(at: lastEditableIndex, offset: document.blocks[lastEditableIndex].text.count)
        }
    }

    func currentMarkdown() -> String {
        BlockSerializer.serialize(document.blocks)
    }

    private func notifyTextChanged() {
        coordinator?.textDidChange(currentMarkdown())
    }

    private func lastEditableBlockIndex() -> Int? {
        for index in (0..<document.blocks.count).reversed() where document.blocks[index].blockType != .frontmatter {
            return index
        }
        return nil
    }

    private func reloadRows(restoreFocus: Bool = true) {
        rowViews.removeAll()
        stackView.arrangedSubviews.forEach { subview in
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        for (index, block) in document.blocks.enumerated() where block.blockType != .frontmatter {
            let row = BlockRowView()
            row.configure(with: block, delegate: self, index: index)
            stackView.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: stackView.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: stackView.trailingAnchor).isActive = true
            rowViews[block.id] = row
        }

        if restoreFocus, let focusedIndex {
            DispatchQueue.main.async { [weak self] in
                self?.focusBlock(at: focusedIndex, offset: self?.focusedOffset)
            }
        }
    }

    func focusBlock(at index: Int, offset: Int? = nil) {
        guard index >= 0, index < document.blocks.count else { return }
        let previousIndex = focusedIndex
        focusedIndex = index
        focusedOffset = offset

        let block = document.blocks[index]
        guard let row = rowViews[block.id] else { return }
        let previousRow: BlockRowView?
        if let previousIndex, previousIndex >= 0, previousIndex < document.blocks.count {
            previousRow = rowViews[document.blocks[previousIndex].id]
        } else {
            previousRow = nil
        }
        row.focus(at: offset)
        ensureRowVisible(row)

        DispatchQueue.main.async {
            previousRow?.refreshStyling()
            row.refreshStyling()
        }
    }

    private func ensureRowVisible(_ row: BlockRowView) {
        guard let documentView = scrollView.documentView else { return }

        view.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()

        let rowRect = documentView.convert(row.bounds, from: row)
        let visibleRect = scrollView.contentView.documentVisibleRect

        if rowRect.minY < visibleRect.minY {
            scrollView.contentView.scroll(to: NSPoint(x: visibleRect.minX, y: rowRect.minY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }

        if rowRect.maxY > visibleRect.maxY {
            let targetY = max(0, rowRect.maxY - visibleRect.height)
            scrollView.contentView.scroll(to: NSPoint(x: visibleRect.minX, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

extension BlockEditorViewController: BlockRowViewDelegate {
    func blockRow(_ row: BlockRowView, didChangeText text: String, atIndex index: Int) {
        guard index < document.blocks.count else { return }
        document.blocks[index] = Block(id: document.blocks[index].id, text: text)
        notifyTextChanged()
    }

    func blockRow(_ row: BlockRowView, didPressEnterAtIndex index: Int, cursorOffset: Int) {
        let newIndex = document.split(blockIndex: index, atOffset: cursorOffset)

        if newIndex == index {
            row.configure(with: document.blocks[index], delegate: self, index: index)
            row.focus(at: 0)
        } else {
            focusedIndex = newIndex
            let prefixLength = document.blocks[newIndex].blockType.prefix?.count ?? 0
            focusedOffset = prefixLength
            reloadRows(restoreFocus: false)
            focusBlock(at: newIndex, offset: prefixLength)
        }
        notifyTextChanged()
    }

    func blockRow(_ row: BlockRowView, didPressBackspaceAtStartOfIndex index: Int) {
        guard index > 0, index < document.blocks.count else { return }
        if document.blocks[index - 1].blockType == .frontmatter { return }

        let previousLength = document.blocks[index - 1].text.count
        guard document.mergeWithPrevious(blockIndex: index) != nil else { return }

        focusedIndex = index - 1
        focusedOffset = previousLength
        reloadRows(restoreFocus: false)
        focusBlock(at: index - 1, offset: previousLength)
        notifyTextChanged()
    }

    func blockRow(_ row: BlockRowView, didPressMoveUpAtIndex index: Int, cursorOffset: Int) {
        guard index > 0 else { return }
        if document.blocks[index - 1].blockType == .frontmatter { return }
        focusBlock(at: index - 1, offset: min(cursorOffset, document.blocks[index - 1].text.count))
    }

    func blockRow(_ row: BlockRowView, didPressMoveDownAtIndex index: Int, cursorOffset: Int) {
        guard index + 1 < document.blocks.count else { return }
        if document.blocks[index + 1].blockType == .frontmatter { return }
        focusBlock(at: index + 1, offset: min(cursorOffset, document.blocks[index + 1].text.count))
    }

    func blockRow(_ row: BlockRowView, didIndentAtIndex index: Int, cursorOffset: Int) {
        guard index < document.blocks.count else { return }
        let transformed = BlockEditingCommands.indentedLine(document.blocks[index].text)
        guard transformed != document.blocks[index].text else { return }

        document.blocks[index] = Block(id: document.blocks[index].id, text: transformed)
        row.configure(with: document.blocks[index], delegate: self, index: index)
        row.focus(at: cursorOffset + 2)
        notifyTextChanged()
    }

    func blockRow(_ row: BlockRowView, didOutdentAtIndex index: Int, cursorOffset: Int) {
        guard index < document.blocks.count else { return }
        let original = document.blocks[index].text
        let transformed = BlockEditingCommands.outdentedLine(original)
        guard transformed != original else { return }

        let removedCount: Int
        if original.hasPrefix("\t") {
            removedCount = 1
        } else {
            removedCount = min(2, original.prefix(while: { $0 == " " }).count)
        }
        document.blocks[index] = Block(id: document.blocks[index].id, text: transformed)
        row.configure(with: document.blocks[index], delegate: self, index: index)
        row.focus(at: max(0, cursorOffset - removedCount))
        notifyTextChanged()
    }

    func blockRowDidBeginEditing(_ row: BlockRowView, atIndex index: Int) {
        isActivelyEditing = true
        focusedIndex = index
    }

    func blockRowDidEndEditing(_ row: BlockRowView, atIndex index: Int) {
        isActivelyEditing = false
        row.refreshStyling()
    }

    func blockRow(_ row: BlockRowView, didToggleCheckboxAtIndex index: Int) {
        guard index < document.blocks.count else { return }
        let block = document.blocks[index]
        let transformed = TodoMarkdown.checkboxToggledLine(block.text)
        guard transformed != block.text else { return }

        document.blocks[index] = Block(id: block.id, text: transformed)
        row.configure(with: document.blocks[index], delegate: self, index: index)
        row.focus(at: min(document.blocks[index].text.count, block.text.count))
        notifyTextChanged()
    }
}

protocol BlockRowViewDelegate: AnyObject {
    func blockRow(_ row: BlockRowView, didChangeText text: String, atIndex index: Int)
    func blockRow(_ row: BlockRowView, didPressEnterAtIndex index: Int, cursorOffset: Int)
    func blockRow(_ row: BlockRowView, didPressBackspaceAtStartOfIndex index: Int)
    func blockRow(_ row: BlockRowView, didPressMoveUpAtIndex index: Int, cursorOffset: Int)
    func blockRow(_ row: BlockRowView, didPressMoveDownAtIndex index: Int, cursorOffset: Int)
    func blockRow(_ row: BlockRowView, didIndentAtIndex index: Int, cursorOffset: Int)
    func blockRow(_ row: BlockRowView, didOutdentAtIndex index: Int, cursorOffset: Int)
    func blockRow(_ row: BlockRowView, didToggleCheckboxAtIndex index: Int)
    func blockRowDidBeginEditing(_ row: BlockRowView, atIndex index: Int)
    func blockRowDidEndEditing(_ row: BlockRowView, atIndex index: Int)
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class BlockRowTextView: NSTextView {
    weak var commandDelegate: BlockRowKeyboardDelegate?

    override var acceptsFirstResponder: Bool { true }

    override func doCommand(by selector: Selector) {
        if commandDelegate?.textView(self, handleCommand: selector) == true {
            return
        }
        super.doCommand(by: selector)
    }
}

protocol BlockRowKeyboardDelegate: AnyObject {
    func textView(_ textView: NSTextView, handleCommand selector: Selector) -> Bool
}

final class BlockRowView: NSView, NSTextViewDelegate, BlockRowKeyboardDelegate {
    private static let verticalInset: CGFloat = 2
    private let textView = BlockRowTextView()
    private let checkboxButton = NSButton()
    private let listMarkerLabel = NSTextField(labelWithString: "")
    private var textLeadingConstraint: NSLayoutConstraint!
    private var markerLeadingConstraint: NSLayoutConstraint!
    private var checkboxLeadingConstraint: NSLayoutConstraint!
    private var textHeightConstraint: NSLayoutConstraint!
    private weak var rowDelegate: BlockRowViewDelegate?
    private var currentBlock: Block?
    private var isConfiguring = false
    fileprivate var blockIndex = 0

    private static let accessoryLeading: CGFloat = 12
    private static let checkboxSize = MarkdownVisualSpec.todoControlSize
    private static let listIndentStep = MarkdownVisualSpec.listIndentStep

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        updateTextHeight()
    }

    func configure(with block: Block, delegate: BlockRowViewDelegate, index: Int) {
        isConfiguring = true
        currentBlock = block
        rowDelegate = delegate
        blockIndex = index
        textView.string = block.text
        applyTypingAttributes(for: block)
        updateStyling(for: block)
        updateTextHeight()
        isConfiguring = false
    }

    func focus(at offset: Int?) {
        window?.makeFirstResponder(textView)
        if let offset {
            textView.setSelectedRange(NSRange(location: min(offset, textView.string.count), length: 0))
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        textView.commandDelegate = self
        textView.delegate = self
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: Self.verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 28)
        textView.translatesAutoresizingMaskIntoConstraints = false

        checkboxButton.translatesAutoresizingMaskIntoConstraints = false
        checkboxButton.isBordered = false
        checkboxButton.setButtonType(.momentaryChange)
        checkboxButton.bezelStyle = .shadowlessSquare
        checkboxButton.imagePosition = .imageOnly
        checkboxButton.target = self
        checkboxButton.action = #selector(toggleCheckbox)
        checkboxButton.isHidden = true

        listMarkerLabel.translatesAutoresizingMaskIntoConstraints = false
        listMarkerLabel.textColor = .tertiaryLabelColor
        listMarkerLabel.isHidden = true
        listMarkerLabel.alignment = .left

        addSubview(checkboxButton)
        addSubview(listMarkerLabel)
        addSubview(textView)

        textLeadingConstraint = textView.leadingAnchor.constraint(equalTo: leadingAnchor)
        markerLeadingConstraint = listMarkerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.accessoryLeading)
        checkboxLeadingConstraint = checkboxButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.accessoryLeading)
        textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: 28)

        NSLayoutConstraint.activate([
            checkboxLeadingConstraint,
            checkboxButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            checkboxButton.widthAnchor.constraint(equalToConstant: Self.checkboxSize),
            checkboxButton.heightAnchor.constraint(equalToConstant: Self.checkboxSize),

            markerLeadingConstraint,
            listMarkerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textLeadingConstraint,
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textHeightConstraint,
        ])
    }

    private func applyTypingAttributes(for block: Block) {
        let spec = renderSpec(for: block)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = spec.lineSpacing
        paragraphStyle.paragraphSpacingBefore = spec.spacingBefore
        paragraphStyle.paragraphSpacing = spec.spacingAfter
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: spec.fontSize, weight: spec.fontWeight),
            .foregroundColor: spec.textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    private func updateStyling(for block: Block) {
        currentBlock = block
        let spec = renderSpec(for: block)
        let isFocused = window?.firstResponder === textView
        let prefixDisplay = isFocused ? (spec.prefixDisplayWhenFocused ?? spec.prefixDisplay) : spec.prefixDisplay
        let selection = textView.selectedRange()

        isConfiguring = true
        let attributed = BlockRenderer.render(text: block.text, spec: spec, prefixDisplay: prefixDisplay)
        textView.textStorage?.setAttributedString(attributed)
        isConfiguring = false
        if selection.location + selection.length <= attributed.length {
            textView.setSelectedRange(selection)
        }

        textLeadingConstraint.constant = spec.leadingOffset
        textView.textContainerInset = NSSize(width: 12, height: Self.verticalInset)

        let indentationOffset = MarkdownVisualSpec.listLeadingOffset(for: spec.indentLevel)
        checkboxLeadingConstraint.constant = Self.accessoryLeading + indentationOffset
        markerLeadingConstraint.constant = Self.accessoryLeading + indentationOffset

        if spec.showsCheckbox {
            checkboxButton.isHidden = false
            checkboxButton.image = NSImage(
                systemSymbolName: spec.isChecked ? "checkmark.circle.fill" : "circle",
                accessibilityDescription: nil
            )
            checkboxButton.contentTintColor = spec.isChecked ? .systemGreen : .tertiaryLabelColor
        } else {
            checkboxButton.isHidden = true
        }

        if let markerText = markerText(for: block) {
            listMarkerLabel.isHidden = false
            listMarkerLabel.stringValue = markerText
            listMarkerLabel.font = NSFont.systemFont(ofSize: spec.fontSize, weight: spec.fontWeight)
        } else {
            listMarkerLabel.isHidden = true
        }
    }

    private func markerText(for block: Block) -> String? {
        switch block.blockType {
        case .bullet:
            return "-"
        case .orderedList(let number, _):
            return "\(number)."
        default:
            return nil
        }
    }

    private func renderSpec(for block: Block) -> BlockRenderSpec {
        var spec = block.blockType.renderSpec(for: block.text).normalizedForMac()
        if blockIndex == 0 {
            spec.spacingBefore = 0
        }
        return spec
    }

    private func updateTextHeight() {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        let width = max(textView.bounds.width, bounds.width - textLeadingConstraint.constant, 100)
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let insetHeight = textView.textContainerInset.height * 2
        textHeightConstraint.constant = max(28, ceil(usedRect.height + insetHeight + 4))
    }

    @objc private func toggleCheckbox() {
        rowDelegate?.blockRow(self, didToggleCheckboxAtIndex: blockIndex)
    }

    func refreshStyling() {
        guard let currentBlock else { return }
        updateStyling(for: currentBlock)
    }

    func textDidBeginEditing(_ notification: Notification) {
        guard let block = currentBlock, notification.object as? NSTextView === textView else { return }
        rowDelegate?.blockRowDidBeginEditing(self, atIndex: blockIndex)
        applyTypingAttributes(for: block)
        updateStyling(for: block)
    }

    func textDidEndEditing(_ notification: Notification) {
        guard let block = currentBlock, notification.object as? NSTextView === textView else { return }
        currentBlock = Block(id: block.id, text: textView.string)
        rowDelegate?.blockRowDidEndEditing(self, atIndex: blockIndex)
        updateStyling(for: currentBlock!)
    }

    func textDidChange(_ notification: Notification) {
        guard !isConfiguring, notification.object as? NSTextView === textView else { return }
        guard window?.firstResponder === textView else { return }
        currentBlock = currentBlock.map { Block(id: $0.id, text: textView.string) }
        rowDelegate?.blockRow(self, didChangeText: textView.string, atIndex: blockIndex)
        updateTextHeight()
    }

    func textView(_ textView: NSTextView, handleCommand selector: Selector) -> Bool {
        let selectedRange = textView.selectedRange()

        if selector == #selector(NSResponder.insertNewline(_:)) {
            rowDelegate?.blockRow(self, didPressEnterAtIndex: blockIndex, cursorOffset: selectedRange.location)
            return true
        }

        if selector == #selector(NSResponder.deleteBackward(_:)),
           selectedRange.location == 0,
           selectedRange.length == 0 {
            rowDelegate?.blockRow(self, didPressBackspaceAtStartOfIndex: blockIndex)
            return true
        }

        if selector == #selector(NSResponder.insertTab(_:)) {
            rowDelegate?.blockRow(self, didIndentAtIndex: blockIndex, cursorOffset: selectedRange.location)
            return true
        }

        if selector == #selector(NSResponder.insertBacktab(_:)) {
            rowDelegate?.blockRow(self, didOutdentAtIndex: blockIndex, cursorOffset: selectedRange.location)
            return true
        }

        if selector == #selector(NSResponder.moveUp(_:)), isCaretOnFirstVisualLine() {
            rowDelegate?.blockRow(self, didPressMoveUpAtIndex: blockIndex, cursorOffset: selectedRange.location)
            return true
        }

        if selector == #selector(NSResponder.moveDown(_:)), isCaretOnLastVisualLine() {
            rowDelegate?.blockRow(self, didPressMoveDownAtIndex: blockIndex, cursorOffset: selectedRange.location)
            return true
        }

        return false
    }

    private func isCaretOnFirstVisualLine() -> Bool {
        guard let layoutManager = textView.layoutManager else { return true }
        guard layoutManager.numberOfGlyphs > 0 else { return true }

        var lineRange = NSRange()
        _ = layoutManager.lineFragmentRect(forGlyphAt: caretGlyphIndex(in: layoutManager), effectiveRange: &lineRange)
        return lineRange.location == 0
    }

    private func isCaretOnLastVisualLine() -> Bool {
        guard let layoutManager = textView.layoutManager else { return true }
        guard layoutManager.numberOfGlyphs > 0 else { return true }

        var lineRange = NSRange()
        _ = layoutManager.lineFragmentRect(forGlyphAt: caretGlyphIndex(in: layoutManager), effectiveRange: &lineRange)
        return NSMaxRange(lineRange) >= layoutManager.numberOfGlyphs
    }

    private func caretGlyphIndex(in layoutManager: NSLayoutManager) -> Int {
        let location = min(textView.selectedRange().location, textView.string.count)
        guard layoutManager.numberOfGlyphs > 0 else { return 0 }
        if location == textView.string.count {
            return max(layoutManager.numberOfGlyphs - 1, 0)
        }
        return layoutManager.glyphIndexForCharacter(at: location)
    }
}

private struct BlockRenderSpec {
    var fontSize: CGFloat = 17
    var fontWeight: NSFont.Weight = .regular
    var textColor: NSColor = .labelColor
    var lineSpacing: CGFloat = 4
    var spacingBefore: CGFloat = 0
    var spacingAfter: CGFloat = 0
    var prefixLength: Int = 0
    var prefixDisplay: PrefixDisplay = .visible
    var prefixDisplayWhenFocused: PrefixDisplay? = nil
    var leadingOffset: CGFloat = 0
    var indentLevel: Int = 0
    var showsCheckbox = false
    var isChecked = false
    var contentStrikethrough = false
    var contentColor: NSColor? = nil

    enum PrefixDisplay {
        case visible
        case dimmed
        case hidden
        case stripped
    }
}

private extension BlockRenderSpec {
    func normalizedForMac() -> BlockRenderSpec {
        var spec = self
        spec.fontSize = round(spec.fontSize * 0.94)
        return spec
    }
}

private extension BlockType {
    func renderSpec(for text: String) -> BlockRenderSpec {
        var spec = BlockRenderSpec()

        switch self {
        case .paragraph:
            spec.spacingBefore = 6

        case .heading(let level):
            let sizes: [Int: CGFloat] = [1: 28, 2: 22, 3: 18]
            let weights: [Int: NSFont.Weight] = [1: .bold, 2: .bold, 3: .semibold]
            spec.fontSize = sizes[level] ?? 17
            spec.fontWeight = weights[level] ?? .regular
            spec.prefixLength = level + 1
            spec.prefixDisplay = .stripped
            spec.prefixDisplayWhenFocused = .dimmed
            spec.spacingBefore = sizes[level].map { $0 * 0.8 } ?? 12
            spec.spacingAfter = sizes[level].map { $0 * 0.3 } ?? 4

        case .todo(let checked, let indent):
            spec.prefixLength = prefixLength(of: text, pattern: #"^(\s*- \[[ x]\] ?)"#)
            spec.prefixDisplay = .hidden
            spec.prefixDisplayWhenFocused = .hidden
            spec.showsCheckbox = true
            spec.isChecked = checked
            spec.indentLevel = indent
            spec.spacingBefore = 4
            spec.spacingAfter = 4
            if checked {
                spec.contentStrikethrough = true
                spec.contentColor = .secondaryLabelColor
            }

        case .bullet(let indent):
            spec.prefixLength = prefixLength(of: text, pattern: #"^(\s*[*\-•] )"#)
            spec.prefixDisplay = .hidden
            spec.prefixDisplayWhenFocused = .hidden
            spec.indentLevel = indent
            spec.spacingBefore = 4
            spec.spacingAfter = 4

        case .orderedList(_, let indent):
            spec.prefixLength = prefixLength(of: text, pattern: #"^(\s*\d+\. )"#)
            spec.prefixDisplay = .hidden
            spec.prefixDisplayWhenFocused = .hidden
            spec.indentLevel = indent
            spec.spacingBefore = 4
            spec.spacingAfter = 4

        case .frontmatter:
            break
        }

        return spec
    }

    private func prefixLength(of text: String, pattern: String) -> Int {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return 0 }
        return text.distance(from: text.startIndex, to: range.upperBound)
    }
}

private enum BlockRenderer {
    static func render(text: String, spec: BlockRenderSpec, prefixDisplay: BlockRenderSpec.PrefixDisplay) -> NSAttributedString {
        if prefixDisplay == .stripped, spec.prefixLength > 0, spec.prefixLength <= text.count {
            let content = String(text.dropFirst(spec.prefixLength))
            return buildAttributed(displayText: content, spec: spec, prefixLength: 0, prefixDisplay: .visible)
        }

        return buildAttributed(displayText: text, spec: spec, prefixLength: spec.prefixLength, prefixDisplay: prefixDisplay)
    }

    private static func buildAttributed(
        displayText: String,
        spec: BlockRenderSpec,
        prefixLength: Int,
        prefixDisplay: BlockRenderSpec.PrefixDisplay
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = spec.lineSpacing
        paragraphStyle.paragraphSpacingBefore = spec.spacingBefore
        paragraphStyle.paragraphSpacing = spec.spacingAfter

        let font = NSFont.systemFont(ofSize: spec.fontSize, weight: spec.fontWeight)
        let attributed = NSMutableAttributedString(string: displayText, attributes: [
            .font: font,
            .foregroundColor: spec.textColor,
            .paragraphStyle: paragraphStyle,
        ])

        let safePrefixLength = min(spec.prefixLength, attributed.length)
        if safePrefixLength > 0 {
            let prefixRange = NSRange(location: 0, length: safePrefixLength)
            switch prefixDisplay {
            case .visible:
                break
            case .dimmed:
                attributed.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: prefixRange)
            case .hidden:
                attributed.addAttribute(.foregroundColor, value: NSColor.clear, range: prefixRange)
            case .stripped:
                break
            }
        }

        let contentRange = NSRange(location: safePrefixLength, length: max(0, attributed.length - safePrefixLength))
        if contentRange.length > 0 {
            if spec.contentStrikethrough {
                attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            }
            if let contentColor = spec.contentColor {
                attributed.addAttribute(.foregroundColor, value: contentColor, range: contentRange)
            }
        }

        InlineFormatter.apply(to: attributed, baseFont: font)
        return attributed
    }
}

private enum InlineFormatter {
    private static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let italicRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
    private static let codeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)

    static func apply(to attributed: NSMutableAttributedString, baseFont: NSFont) {
        let string = attributed.string
        let fullRange = NSRange(location: 0, length: attributed.length)

        boldRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let match else { return }
            let currentFont = attributed.attribute(.font, at: match.range.location, effectiveRange: nil) as? NSFont ?? baseFont
            attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: currentFont.pointSize, weight: .bold), range: match.range)
        }

        italicRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let match else { return }
            let currentFont = attributed.attribute(.font, at: match.range.location, effectiveRange: nil) as? NSFont ?? baseFont
            let descriptor = currentFont.fontDescriptor.withSymbolicTraits(.italic)
            let italicFont = NSFont(descriptor: descriptor, size: currentFont.pointSize) ?? currentFont
            attributed.addAttribute(.font, value: italicFont, range: match.range)
        }

        codeRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let match else { return }
            attributed.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .backgroundColor: NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.3),
            ], range: match.range)
        }
    }
}
#endif
