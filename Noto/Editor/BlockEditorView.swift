#if os(iOS)
import SwiftUI
import UIKit

/// Block-based markdown editor. Each line is its own UITextField with
/// isolated styling. Formatting in one block cannot affect another.
struct BlockEditorView: UIViewControllerRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange, autoFocus: autoFocus)
    }

    func makeUIViewController(context: Context) -> BlockEditorViewController {
        let vc = BlockEditorViewController()
        vc.coordinator = context.coordinator
        vc.loadMarkdown(text)
        return vc
    }

    func updateUIViewController(_ vc: BlockEditorViewController, context: Context) {
        guard !context.coordinator.isUpdatingText else { return }
        // Never reload while the user is actively editing — it dismisses the keyboard.
        // Only reload for external changes (e.g., iCloud sync).
        guard !vc.isActivelyEditing else { return }
        if vc.currentMarkdown() != text {
            vc.loadMarkdown(text)
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

// MARK: - BlockEditorViewController

final class BlockEditorViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var coordinator: BlockEditorView.Coordinator?
    private var document = BlockDocument(blocks: [])
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var focusedIndex: Int?
    private var focusedOffset: Int?
    /// True when any block's text view is first responder.
    private(set) var isActivelyEditing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.keyboardDismissMode = .interactive
        tableView.register(BlockCell.self, forCellReuseIdentifier: BlockCell.reuseID)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.accessibilityIdentifier = "note_editor"
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func loadMarkdown(_ markdown: String) {
        document = BlockDocument(blocks: BlockParser.parse(markdown))
        tableView.reloadData()
        if coordinator?.autoFocus == true, let lastEditableIndex = lastEditableBlockIndex() {
            focusedIndex = lastEditableIndex
            focusedOffset = document.blocks[lastEditableIndex].text.count
            DispatchQueue.main.async { [weak self] in
                self?.focusBlock(at: lastEditableIndex)
            }
        }
    }

    func currentMarkdown() -> String {
        BlockSerializer.serialize(document.blocks)
    }

    private func notifyTextChanged() {
        coordinator?.textDidChange(currentMarkdown())
    }

    private func lastEditableBlockIndex() -> Int? {
        for i in (0..<document.blocks.count).reversed() {
            if document.blocks[i].blockType != .frontmatter { return i }
        }
        return nil
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        document.blocks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: BlockCell.reuseID, for: indexPath) as! BlockCell
        let block = document.blocks[indexPath.row]
        cell.configure(with: block, delegate: self, index: indexPath.row)
        if indexPath.row == focusedIndex {
            cell.focus(at: focusedOffset)
            focusedOffset = nil
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let block = document.blocks[indexPath.row]
        if block.blockType == .frontmatter {
            return 0 // hide frontmatter completely
        }
        return UITableView.automaticDimension
    }

    // MARK: - Focus management

    func focusBlock(at index: Int, offset: Int? = nil) {
        guard index >= 0, index < document.blocks.count else { return }
        focusedIndex = index
        focusedOffset = offset
        let indexPath = IndexPath(row: index, section: 0)
        if let cell = tableView.cellForRow(at: indexPath) as? BlockCell {
            cell.focus(at: offset)
            focusedOffset = nil
        } else {
            // Cell not visible — scroll to it, configure will focus
            tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
        }
    }
}

// MARK: - BlockCellDelegate

extension BlockEditorViewController: BlockCellDelegate {
    func blockCell(_ cell: BlockCell, didChangeText text: String, atIndex index: Int) {
        guard index < document.blocks.count else { return }
        document.blocks[index] = Block(id: document.blocks[index].id, text: text)
        notifyTextChanged()
        // Never restyle while the user is actively typing.
        // Styling is applied when focus leaves the block (textViewDidEndEditing).
    }

    func blockCell(_ cell: BlockCell, didPressEnterAtIndex index: Int, cursorOffset: Int) {
        let newIndex = document.split(blockIndex: index, atOffset: cursorOffset)

        if newIndex == index {
            // Empty list → converted to paragraph, no new block
            // Update the cell in-place without reloading (keeps keyboard alive)
            cell.configure(with: document.blocks[index], delegate: self, index: index)
            cell.focus(at: 0)
        } else {
            // Update the old cell's text in-place (don't reload — keeps keyboard alive)
            cell.configure(with: document.blocks[index], delegate: self, index: index)

            // Insert the new row
            tableView.insertRows(at: [IndexPath(row: newIndex, section: 0)], with: .none)

            // Focus the new block immediately
            let newBlock = document.blocks[newIndex]
            let prefixLen = newBlock.blockType.prefix?.count ?? 0
            focusBlock(at: newIndex, offset: prefixLen)
        }
        notifyTextChanged()
    }

    func blockCell(_ cell: BlockCell, didPressBackspaceAtStartOfIndex index: Int) {
        guard index > 0, index < document.blocks.count else { return }
        if document.blocks[index - 1].blockType == .frontmatter { return }

        let cursorOffset = document.blocks[index - 1].text.count
        guard document.mergeWithPrevious(blockIndex: index) != nil else { return }

        let prevIndexPath = IndexPath(row: index - 1, section: 0)
        let prevCell = tableView.cellForRow(at: prevIndexPath) as? BlockCell

        // Update the previous cell's text directly (no reload → keyboard stays)
        if let prevCell {
            prevCell.setTextDirectly(document.blocks[index - 1].text)
            prevCell.blockIndex = index - 1
            // Transfer first responder before removing the current row so the
            // keyboard stays attached during block deletion.
            prevCell.focus(at: cursorOffset)
        }

        // Delete the current row
        tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .none)

        // If the previous cell wasn't visible, restore focus after the delete.
        if prevCell == nil {
            focusedIndex = index - 1
            focusedOffset = cursorOffset
        }

        notifyTextChanged()
    }

    func blockCellDidBeginEditing(_ cell: BlockCell, atIndex index: Int) {
        isActivelyEditing = true
    }

    func blockCellDidEndEditing(_ cell: BlockCell, atIndex index: Int) {
        isActivelyEditing = false
    }

    func blockCell(_ cell: BlockCell, didToggleCheckboxAtIndex index: Int) {
        guard index < document.blocks.count else { return }
        let block = document.blocks[index]
        let text = TodoMarkdown.checkboxToggledLine(block.text)
        guard text != block.text else { return }
        document.blocks[index] = Block(id: block.id, text: text)
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
        notifyTextChanged()
    }
}

// MARK: - BlockCellDelegate protocol

protocol BlockCellDelegate: AnyObject {
    func blockCell(_ cell: BlockCell, didChangeText text: String, atIndex index: Int)
    func blockCell(_ cell: BlockCell, didPressEnterAtIndex index: Int, cursorOffset: Int)
    func blockCell(_ cell: BlockCell, didPressBackspaceAtStartOfIndex index: Int)
    func blockCell(_ cell: BlockCell, didToggleCheckboxAtIndex index: Int)
    func blockCellDidBeginEditing(_ cell: BlockCell, atIndex index: Int)
    func blockCellDidEndEditing(_ cell: BlockCell, atIndex index: Int)
}

// MARK: - BlockCell

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

/// UITextView subclass that notifies on backspace at position 0.
private class BlockTextView: UITextView {
    var onDeleteBackwardAtStart: (() -> Void)?

    override func deleteBackward() {
        if selectedRange.location == 0 && selectedRange.length == 0 {
            onDeleteBackwardAtStart?()
            return
        }
        super.deleteBackward()
    }
}

final class BlockCell: UITableViewCell, UITextViewDelegate {
    static let reuseID = "BlockCell"

    private let blockTextView = BlockTextView()
    private let checkboxButton = UIButton(type: .custom)
    private let listMarkerLabel = UILabel()
    fileprivate var blockIndex: Int = 0
    private weak var cellDelegate: BlockCellDelegate?
    private var isConfiguring = false
    private var textLeadingConstraint: NSLayoutConstraint!
    private var checkboxLeadingConstraint: NSLayoutConstraint!
    private var checkboxTopConstraint: NSLayoutConstraint!
    private var markerLeadingConstraint: NSLayoutConstraint!
    private var markerTopConstraint: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let checkboxSize: CGFloat = 28
    private static let checkboxLeading: CGFloat = 12

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        blockTextView.isScrollEnabled = false
        blockTextView.textContainerInset = UIEdgeInsets(top: 2, left: 12, bottom: 2, right: 12)
        blockTextView.textContainer.lineFragmentPadding = 0
        blockTextView.backgroundColor = .clear
        blockTextView.delegate = self
        blockTextView.font = UIFont.systemFont(ofSize: 17)
        blockTextView.inputAccessoryView = makeKeyboardToolbar()
        blockTextView.translatesAutoresizingMaskIntoConstraints = false
        blockTextView.onDeleteBackwardAtStart = { [weak self] in
            guard let self else { return }
            self.cellDelegate?.blockCell(self, didPressBackspaceAtStartOfIndex: self.blockIndex)
        }

        checkboxButton.isHidden = true
        checkboxButton.translatesAutoresizingMaskIntoConstraints = false
        checkboxButton.addTarget(self, action: #selector(checkboxTapped), for: .touchUpInside)

        listMarkerLabel.isHidden = true
        listMarkerLabel.translatesAutoresizingMaskIntoConstraints = false
        listMarkerLabel.textColor = .tertiaryLabel
        listMarkerLabel.textAlignment = .left
        listMarkerLabel.setContentHuggingPriority(.required, for: .horizontal)
        listMarkerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentView.addSubview(checkboxButton)
        contentView.addSubview(listMarkerLabel)
        contentView.addSubview(blockTextView)

        textLeadingConstraint = blockTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        checkboxLeadingConstraint = checkboxButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.checkboxLeading)
        checkboxTopConstraint = checkboxButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4)
        markerLeadingConstraint = listMarkerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.checkboxLeading)
        markerTopConstraint = listMarkerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4)

        NSLayoutConstraint.activate([
            checkboxLeadingConstraint,
            checkboxButton.widthAnchor.constraint(equalToConstant: Self.checkboxSize),
            checkboxButton.heightAnchor.constraint(equalToConstant: Self.checkboxSize),
            checkboxTopConstraint,

            markerLeadingConstraint,
            markerTopConstraint,

            blockTextView.topAnchor.constraint(equalTo: contentView.topAnchor),
            blockTextView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            textLeadingConstraint,
            blockTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    private var currentBlock: Block?

    private func makeKeyboardToolbar() -> UIView {
        let pillHeight: CGFloat = 40
        let bottomMargin: CGFloat = 8
        let barHeight: CGFloat = pillHeight + bottomMargin
        let pillPadding: CGFloat = 12
        let buttonSize: CGFloat = 36

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
        let todoButton = UIButton(type: .system)
        todoButton.setImage(UIImage(systemName: "checklist", withConfiguration: symbolConfig), for: .normal)
        todoButton.tintColor = .white
        todoButton.addTarget(self, action: #selector(todoTapped), for: .touchUpInside)
        todoButton.accessibilityLabel = "Todo"
        todoButton.accessibilityIdentifier = "todoButton"
        todoButton.translatesAutoresizingMaskIntoConstraints = false
        pill.contentView.addSubview(todoButton)

        NSLayoutConstraint.activate([
            pill.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -12),
            pill.topAnchor.constraint(equalTo: wrapper.topAnchor),
            pill.heightAnchor.constraint(equalToConstant: pillHeight),
            todoButton.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor, constant: pillPadding),
            todoButton.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor, constant: -pillPadding),
            todoButton.centerYAnchor.constraint(equalTo: pill.contentView.centerYAnchor),
            todoButton.widthAnchor.constraint(equalToConstant: buttonSize),
            todoButton.heightAnchor.constraint(equalToConstant: buttonSize),
        ])

        return wrapper
    }

    private func replaceTextPreservingSelection(_ text: String, delta: Int) {
        let selection = blockTextView.selectedRange
        let safeLocation = max(0, min(selection.location + delta, text.count))
        let safeLength = min(selection.length, max(0, text.count - safeLocation))

        currentBlock = currentBlock.map { Block(id: $0.id, text: text) }

        isConfiguring = true
        blockTextView.text = text
        if let updatedBlock = currentBlock {
            updateStyling(for: updatedBlock)
            applyTypingAttributes(for: updatedBlock)
        }
        blockTextView.selectedRange = NSRange(location: safeLocation, length: safeLength)
        isConfiguring = false

        cellDelegate?.blockCell(self, didChangeText: text, atIndex: blockIndex)

        if let tableView = superview as? UITableView {
            UIView.performWithoutAnimation {
                tableView.beginUpdates()
                tableView.endUpdates()
            }
        }
    }

    @objc private func todoTapped() {
        let existingText = blockTextView.text ?? ""
        let transformed = TodoMarkdown.toolbarToggledLine(existingText)
        guard transformed != existingText else { return }

        let delta = transformed.count - existingText.count
        replaceTextPreservingSelection(transformed, delta: delta)
    }

    func configure(with block: Block, delegate: BlockCellDelegate, index: Int) {
        isConfiguring = true
        self.cellDelegate = delegate
        self.blockIndex = index
        self.currentBlock = block
        blockTextView.text = block.text
        updateStyling(for: block)
        applyTypingAttributes(for: block)
        isConfiguring = false
    }

    /// Set typingAttributes so new characters typed by the user
    /// use the correct font/color without needing to restyle the whole block.
    private func applyTypingAttributes(for block: Block) {
        let spec = block.blockType.renderSpec(for: block.text)
        let font = UIFont.systemFont(ofSize: spec.fontSize, weight: spec.fontWeight)
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = spec.lineSpacing
        paraStyle.paragraphSpacingBefore = spec.spacingBefore
        paraStyle.paragraphSpacing = spec.spacingAfter
        blockTextView.typingAttributes = [
            .font: font,
            .foregroundColor: spec.contentColor ?? spec.textColor,
            .paragraphStyle: paraStyle,
        ]
    }

    func updateStyling(for block: Block) {
        let type = block.blockType
        let text = block.text
        self.currentBlock = block
        let spec = type.renderSpec(for: text)
        let isCurrentlyEditing = blockTextView.isFirstResponder
        let prefixDisplay = isCurrentlyEditing ? (spec.prefixDisplayWhenFocused ?? spec.prefixDisplay) : spec.prefixDisplay

        // Hide frontmatter blocks entirely
        if type == .frontmatter {
            blockTextView.isHidden = true
            checkboxButton.isHidden = true
            listMarkerLabel.isHidden = true
            return
        }
        blockTextView.isHidden = false

        // Build attributed string from spec
        let attributed = BlockRenderer.render(text: text, spec: spec, isFocused: isCurrentlyEditing)
        let savedSelection = blockTextView.selectedRange
        blockTextView.attributedText = attributed
        if isCurrentlyEditing && savedSelection.location + savedSelection.length <= attributed.length {
            blockTextView.selectedRange = savedSelection
        }

        // Layout from spec
        textLeadingConstraint.constant = spec.leadingOffset
        let leftInset: CGFloat = spec.showsCheckbox ? 0 : 12
        blockTextView.textContainerInset = UIEdgeInsets(
            top: spec.spacingBefore + 2,
            left: leftInset,
            bottom: spec.spacingAfter + 2,
            right: 12
        )

        let font = UIFont.systemFont(ofSize: spec.fontSize, weight: spec.fontWeight)
        let textTopInset = blockTextView.textContainerInset.top
        let accessoryLineCenter = textTopInset + font.lineHeight / 2
        let indentationOffset = CGFloat(spec.indentLevel) * 12

        // Keep the structured todo marker visible whenever the markdown prefix
        // is visually hidden, including while the row is focused.
        let showCheckbox = spec.showsCheckbox && (prefixDisplay == .hidden || prefixDisplay == .stripped)
        checkboxLeadingConstraint.constant = Self.checkboxLeading + indentationOffset
        if showCheckbox {
            checkboxButton.isHidden = false
            let imageName = spec.isChecked ? "checkmark.circle.fill" : "circle"
            let color: UIColor = spec.isChecked ? .systemGreen : .systemGray2
            let config = UIImage.SymbolConfiguration(pointSize: Self.checkboxSize - 4, weight: .regular)
            checkboxButton.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
            checkboxButton.tintColor = color
            checkboxTopConstraint.constant = accessoryLineCenter - Self.checkboxSize / 2
        } else {
            checkboxButton.isHidden = true
        }

        // Focused bullets and ordered lists keep their visual marker instead of
        // exposing raw markdown prefixes after pressing Return.
        if let markerText = focusedListMarkerText(for: block, prefixDisplay: prefixDisplay) {
            listMarkerLabel.isHidden = false
            listMarkerLabel.text = markerText
            listMarkerLabel.font = font
            listMarkerLabel.textColor = .tertiaryLabel
            markerLeadingConstraint.constant = Self.checkboxLeading + indentationOffset
            markerTopConstraint.constant = accessoryLineCenter - font.lineHeight / 2
        } else {
            listMarkerLabel.isHidden = true
        }

        // When editing a todo, keep the content aligned after the hidden prefix.
        if spec.showsCheckbox && isCurrentlyEditing {
            textLeadingConstraint.constant = 0
            blockTextView.textContainerInset.left = 12
        }
    }

    private func focusedListMarkerText(for block: Block, prefixDisplay: BlockRenderSpec.PrefixDisplay) -> String? {
        guard blockTextView.isFirstResponder, prefixDisplay == .hidden else { return nil }

        switch block.blockType {
        case .bullet:
            return "\u{2022}"
        case .orderedList(let number, _):
            return "\(number)."
        default:
            return nil
        }
    }

    /// Update the text view's text without restyling (keeps keyboard alive).
    func setTextDirectly(_ text: String) {
        isConfiguring = true
        blockTextView.text = text
        currentBlock = currentBlock.map { Block(id: $0.id, text: text) }
        isConfiguring = false
    }

    func focus(at offset: Int?) {
        blockTextView.becomeFirstResponder()
        if let offset {
            let safeOffset = min(offset, blockTextView.text.count)
            if let pos = blockTextView.position(from: blockTextView.beginningOfDocument, offset: safeOffset) {
                blockTextView.selectedTextRange = blockTextView.textRange(from: pos, to: pos)
            }
        }
    }

    @objc private func checkboxTapped() {
        cellDelegate?.blockCell(self, didToggleCheckboxAtIndex: blockIndex)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        guard let block = currentBlock else { return }
        cellDelegate?.blockCellDidBeginEditing(self, atIndex: blockIndex)
        applyTypingAttributes(for: block)
        let spec = block.blockType.renderSpec(for: block.text)

        // If the block normally strips its prefix, restyle in the focused state
        // and place the caret after the underlying markdown prefix.
        if spec.prefixDisplay == .stripped && spec.prefixLength > 0 {
            isConfiguring = true
            updateStyling(for: block)
            // Place cursor after the prefix
            if let pos = textView.position(from: textView.beginningOfDocument, offset: spec.prefixLength) {
                textView.selectedTextRange = textView.textRange(from: pos, to: pos)
            }
            isConfiguring = false
        } else {
            updateStyling(for: block)
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        guard let block = currentBlock else { return }
        cellDelegate?.blockCellDidEndEditing(self, atIndex: blockIndex)
        let spec = block.blockType.renderSpec(for: block.text)

        // If prefix was stripped, the text view has full markdown — sync back
        if spec.prefixDisplay == .stripped && spec.prefixLength > 0 {
            let fullText = textView.text ?? ""
            if fullText != block.text {
                cellDelegate?.blockCell(self, didChangeText: fullText, atIndex: blockIndex)
                currentBlock = Block(id: block.id, text: fullText)
            }
        }

        if let updatedBlock = currentBlock {
            isConfiguring = true
            updateStyling(for: updatedBlock)
            isConfiguring = false
        }
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        guard !isConfiguring else { return }
        // Update the block text without restyling (styling happens on focus change)
        currentBlock = currentBlock.map { Block(id: $0.id, text: textView.text) }
        cellDelegate?.blockCell(self, didChangeText: textView.text, atIndex: blockIndex)
        // Resize cell if text wrapped to a new line — use invalidateIntrinsicContentSize
        // which is less disruptive than beginUpdates/endUpdates (won't dismiss keyboard)
        blockTextView.invalidateIntrinsicContentSize()
        if let tableView = superview as? UITableView {
            UIView.performWithoutAnimation {
                tableView.beginUpdates()
                tableView.endUpdates()
            }
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            let cursorOffset = textView.selectedRange.location
            cellDelegate?.blockCell(self, didPressEnterAtIndex: blockIndex, cursorOffset: cursorOffset)
            return false
        }
        return true
    }
}

// MARK: - BlockRenderSpec

/// Declarative rendering specification for a block type.
/// Each block type declares its visual properties; a shared function
/// builds the NSAttributedString from the spec.
struct BlockRenderSpec {
    // MARK: Typography
    var fontSize: CGFloat = 17
    var fontWeight: UIFont.Weight = .regular
    var textColor: UIColor = .label
    var lineSpacing: CGFloat = 4
    var spacingBefore: CGFloat = 0
    var spacingAfter: CGFloat = 0

    // MARK: Prefix
    /// How many characters at the start are the markdown prefix.
    var prefixLength: Int = 0
    /// How to show the prefix.
    var prefixDisplay: PrefixDisplay = .visible
    /// When focused, how to show the prefix (overrides prefixDisplay).
    var prefixDisplayWhenFocused: PrefixDisplay? = nil

    enum PrefixDisplay {
        case visible           // show as normal text
        case dimmed            // show in tertiaryLabel color
        case hidden            // clear color, same font (invisible but takes space)
        case stripped          // remove from displayed text entirely (content shifts left)
    }

    // MARK: Layout
    var leadingOffset: CGFloat = 0
    var indentLevel: Int = 0

    // MARK: Checkbox
    var showsCheckbox: Bool = false
    var isChecked: Bool = false

    // MARK: Content styling
    var contentStrikethrough: Bool = false
    var contentColor: UIColor? = nil // nil = use textColor

    // MARK: Inline formatting
    var supportsInlineFormatting: Bool = true
}

// MARK: - BlockType → Spec

extension BlockType {
    func renderSpec(for text: String) -> BlockRenderSpec {
        var spec = BlockRenderSpec()

        switch self {
        case .paragraph:
            spec.spacingBefore = 6

        case .heading(let level):
            let sizes: [Int: CGFloat] = [1: 28, 2: 22, 3: 18]
            let weights: [Int: UIFont.Weight] = [1: .bold, 2: .bold, 3: .semibold]
            spec.fontSize = sizes[level] ?? 17
            spec.fontWeight = weights[level] ?? .regular
            spec.prefixLength = level + 1
            spec.prefixDisplay = .stripped
            spec.prefixDisplayWhenFocused = .dimmed
            // Spacing proportional to font size
            spec.spacingBefore = sizes[level].map { $0 * 0.8 } ?? 12
            spec.spacingAfter = sizes[level].map { $0 * 0.3 } ?? 4

        case .todo(let checked, let indent):
            spec.prefixLength = prefixLength(of: text, pattern: #"^(\s*- \[[ x]\] )"#)
            spec.prefixDisplay = .stripped  // hide prefix, checkbox replaces it
            spec.prefixDisplayWhenFocused = .hidden
            spec.showsCheckbox = true
            spec.isChecked = checked
            spec.indentLevel = indent
            // checkbox (12 leading + 28 size + 4 gap) = 44
            spec.leadingOffset = 44 + CGFloat(indent) * 12
            spec.spacingBefore = 4
            spec.spacingAfter = 4
            if checked {
                spec.contentStrikethrough = true
                spec.contentColor = .secondaryLabel
            }

        case .bullet(let indent):
            spec.prefixLength = prefixLength(of: text, pattern: #"^(\s*[*\-•] )"#)
            spec.prefixDisplay = .dimmed
            spec.prefixDisplayWhenFocused = .hidden
            spec.indentLevel = indent
            spec.leadingOffset = CGFloat(indent) * 12
            spec.spacingBefore = 4
            spec.spacingAfter = 4

        case .orderedList(_, let indent):
            spec.prefixLength = prefixLength(of: text, pattern: #"^(\s*\d+\. )"#)
            spec.prefixDisplay = .dimmed
            spec.prefixDisplayWhenFocused = .hidden
            spec.indentLevel = indent
            spec.leadingOffset = CGFloat(indent) * 12
            spec.spacingBefore = 4
            spec.spacingAfter = 4

        case .frontmatter:
            spec.supportsInlineFormatting = false
        }

        return spec
    }

    private func prefixLength(of text: String, pattern: String) -> Int {
        guard let match = text.range(of: pattern, options: .regularExpression) else { return 0 }
        return text.distance(from: text.startIndex, to: match.upperBound)
    }
}

// MARK: - Spec → NSAttributedString

enum BlockRenderer {
    static func render(text: String, spec: BlockRenderSpec, isFocused: Bool) -> NSAttributedString {
        let prefixDisplay = isFocused ? (spec.prefixDisplayWhenFocused ?? spec.prefixDisplay) : spec.prefixDisplay

        // If prefix is stripped, show only content when not in the stripped-override state
        if prefixDisplay == .stripped && spec.prefixLength > 0 && spec.prefixLength <= text.count {
            let content = String(text.dropFirst(spec.prefixLength))
            return buildAttributed(displayText: content, spec: spec, prefixLength: 0, prefixDisplay: .visible, isFocused: isFocused)
        }

        return buildAttributed(displayText: text, spec: spec, prefixLength: spec.prefixLength, prefixDisplay: prefixDisplay, isFocused: isFocused)
    }

    private static func buildAttributed(
        displayText: String,
        spec: BlockRenderSpec,
        prefixLength: Int,
        prefixDisplay: BlockRenderSpec.PrefixDisplay,
        isFocused: Bool
    ) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: spec.fontSize, weight: spec.fontWeight)
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = spec.lineSpacing
        paraStyle.paragraphSpacingBefore = spec.spacingBefore
        paraStyle.paragraphSpacing = spec.spacingAfter

        let attributed = NSMutableAttributedString(string: displayText, attributes: [
            .font: font,
            .foregroundColor: spec.textColor,
            .paragraphStyle: paraStyle,
        ])

        guard attributed.length > 0 else { return attributed }

        // Prefix styling
        let safePrefixLen = min(prefixLength, displayText.count)
        if safePrefixLen > 0 {
            switch prefixDisplay {
            case .visible:
                break // default attributes
            case .dimmed:
                attributed.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: NSRange(location: 0, length: safePrefixLen))
            case .hidden:
                attributed.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: 0, length: safePrefixLen))
            case .stripped:
                break // handled above by removing prefix from displayText
            }
        }

        // Content styling (strikethrough, custom color)
        let contentStart = safePrefixLen
        let contentLen = displayText.count - contentStart
        if contentLen > 0 {
            let contentRange = NSRange(location: contentStart, length: contentLen)
            if spec.contentStrikethrough {
                attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            }
            if let contentColor = spec.contentColor {
                attributed.addAttribute(.foregroundColor, value: contentColor, range: contentRange)
            }
        }

        // Inline formatting
        if spec.supportsInlineFormatting {
            InlineFormatter.apply(to: attributed, baseFont: font)
        }

        return attributed
    }
}

// MARK: - InlineFormatter

enum InlineFormatter {
    private static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let italicRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
    private static let codeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)

    static func apply(to attributed: NSMutableAttributedString, baseFont: UIFont) {
        let string = attributed.string
        let fullRange = NSRange(location: 0, length: attributed.length)

        boldRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let match else { return }
            let currentFont = attributed.attribute(.font, at: match.range.location, effectiveRange: nil) as? UIFont ?? baseFont
            attributed.addAttribute(.font, value: UIFont.systemFont(ofSize: currentFont.pointSize, weight: .bold), range: match.range)
            attributed.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: NSRange(location: match.range.location, length: 2))
            attributed.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: NSRange(location: match.range.location + match.range.length - 2, length: 2))
        }

        italicRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let match else { return }
            let currentFont = attributed.attribute(.font, at: match.range.location, effectiveRange: nil) as? UIFont ?? baseFont
            let descriptor = currentFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? currentFont.fontDescriptor
            attributed.addAttribute(.font, value: UIFont(descriptor: descriptor, size: currentFont.pointSize), range: match.range)
            attributed.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: NSRange(location: match.range.location, length: 1))
            attributed.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: NSRange(location: match.range.location + match.range.length - 1, length: 1))
        }

        codeRegex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let match else { return }
            attributed.addAttributes([
                .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel,
                .backgroundColor: UIColor.secondarySystemFill,
            ], range: match.range)
        }
    }
}

#endif
