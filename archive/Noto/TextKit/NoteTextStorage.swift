//
//  NoteTextStorage.swift
//  Noto
//
//  Based on Simple Notes by Paulo Mattos.
//  Custom NSTextStorage with markdown-like rich text formatting.
//

import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteTextStorage")
private let mainContentFontSize: CGFloat = 20
private let mainContentLineHeight: CGFloat = 28
private let mainContentTracking: CGFloat = mainContentFontSize * -0.01

/// Stores a given note text with rich formatting.
/// This implements the core text formatting engine.
final class NoteTextStorage: NSTextStorage {

    fileprivate let backingStore = NSMutableAttributedString()
    fileprivate var backingString: NSString { return backingStore.string as NSString }

    /// When true, bullet styles vary by indent depth (node view mode).
    var nodeViewMode = false {
        didSet { syncNodeViewMode() }
    }

    // MARK: - Storage Initialization

    override init() {
        super.init()
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        wordsFormatter.storage = self
        listsFormatter.storage = self
        indentFormatter.storage = self
        indentFormatter.nodeViewMode = nodeViewMode
        headingsFormatter.storage = self
    }

    /// Update the indent formatter's mode when nodeViewMode changes.
    private func syncNodeViewMode() {
        indentFormatter.nodeViewMode = nodeViewMode
    }

    // MARK: - NSTextStorage Subclassing Requirements

    /// The character contents of the storage as an `NSString` object.
    override var string: String {
        return backingStore.string
    }

    /// Returns the attributes for the character at a given index.
    override func attributes(
        at location: Int,
        effectiveRange range: NSRangePointer?)
        -> [NSAttributedString.Key: Any] {
        return backingStore.attributes(at: location, effectiveRange: range)
    }

    /// Replaces the characters in the given range
    /// with the characters of the specified string.
    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range,
               changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    /// Sets the attributes for the characters in
    /// the specified range to the specified attributes.
    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - Rich Text Formatting

    let bodyFont = UIFont.systemFont(ofSize: mainContentFontSize)

    var bodyStyle: [NSAttributedString.Key: Any] {
        let bodyParagraphStyle = NSMutableParagraphStyle()
        bodyParagraphStyle.paragraphSpacing = 12
        bodyParagraphStyle.minimumLineHeight = mainContentLineHeight
        bodyParagraphStyle.maximumLineHeight = mainContentLineHeight

        return [
            .paragraphStyle: bodyParagraphStyle,
            .font: bodyFont,
            .foregroundColor: UIColor.label,
            .kern: NSNumber(value: mainContentTracking)
        ]
    }

    private let wordsFormatter = WordsFormatter()
    private let listsFormatter = ListsFormatter()
    private let indentFormatter = IndentFormatter()
    private let headingsFormatter = HeadingsFormatter()

    private func performRichFormatting(in editedRange: NSRange,
                                       with editedMask: EditActions) -> FormattedText? {
        // Plain text mode — no formatting applied
        return nil
    }

    private var lastEditedRange: NSRange?
    private var lastEditedMask: NSTextStorage.EditActions?

    func processRichFormatting() -> FormattedText? {
        if let lastEditedRange = self.lastEditedRange,
            let lastEditedMask = self.lastEditedMask {
            return performRichFormatting(in: lastEditedRange, with: lastEditedMask)
        }
        return nil
    }

    override func processEditing() {
        lastEditedRange = editedRange
        lastEditedMask  = editedMask
        super.processEditing()
    }

    // MARK: - Checkmarks Support

    func insertCheckmark(at index: Int, withValue value: Bool = false) {
        listsFormatter.insertListItem(.checkmark(value), at: index)
    }

    func setCheckmark(atLine lineRange: NSRange, to value: Bool) {
        listsFormatter.updateListItem(.checkmark(value), atLine: lineRange)
    }

    // MARK: - Indent Support

    func indentLine(at index: Int) {
        let lineRange = (self as NSAttributedString).lineRange(for: index)
        beginEditing()
        backingStore.insert(NSAttributedString(string: "\t", attributes: bodyStyle), at: lineRange.location)
        edited(.editedCharacters, range: NSRange(location: lineRange.location, length: 0), changeInLength: 1)
        endEditing()
    }

    func outdentLine(at index: Int) {
        let lineRange = (self as NSAttributedString).lineRange(for: index)
        guard lineRange.length > 0,
              backingString.character(at: lineRange.location) == 0x09 else { return } // tab = 0x09
        beginEditing()
        backingStore.deleteCharacters(in: NSRange(location: lineRange.location, length: 1))
        edited(.editedCharacters, range: NSRange(location: lineRange.location, length: 1), changeInLength: -1)
        endEditing()
    }

    // MARK: - Note IO

    /// Loads the specified note as plain text with body style.
    func load(note: String) {
        let noteString = NSAttributedString(string: note, attributes: bodyStyle)
        setAttributedString(noteString)
    }

    /// Returns the plain text contents.
    func deformatted() -> String {
        return backingStore.string
    }
}

// MARK: - Formatting Metadata

/// Metadata about the interactive changes, in the text, made by the user.
fileprivate struct ChangedText: CustomStringConvertible {
    var contents: String
    var mask: NSTextStorage.EditActions
    var range: NSRange
    var lineRange: NSRange
    var listItem: ListItem?

    var isNewLine: Bool {
        return contents == "\n" && mask.contains(.editedCharacters)
    }

    var description: String {
        let change: String
        switch contents {
        case " ":
            change = "<space>"
        case "\n":
            change = "<newline>"
        default:
            change = "\"\(contents)\""
        }

        var extras: [String] = []
        extras.append("line \(lineRange)")
        if let listStyle = listItem {
            extras.append("\(listStyle)")
        }
        let extrasDescription = extras.joined(separator: ", ")

        return "ChangedText: \(change) at \(range) (\(extrasDescription))"
    }
}

/// Metadata about the resulting formatted text, if any.
struct FormattedText {
    var caretRange: NSRange?
    /// Optional typing attributes to apply after formatting, overriding the
    /// default attribute-inheritance logic. Used when formatting produces an
    /// empty line (e.g., heading trigger on "## " with no content yet) where
    /// there is no adjacent character to inherit attributes from.
    var typingStyle: [NSAttributedString.Key: Any]?

    init(caretRange: NSRange? = nil, typingStyle: [NSAttributedString.Key: Any]? = nil) {
        self.caretRange = caretRange
        self.typingStyle = typingStyle
    }
}

fileprivate class Formatter {

    fileprivate weak var storage: NoteTextStorage!
    fileprivate var backingStore: NSMutableAttributedString { return storage.backingStore }

    var bodyStyle: [NSAttributedString.Key: Any] { return storage.bodyStyle }

    func formattedText(caretAtLine index: Int) -> FormattedText {
        let lineRange = storage.lineRange(for: index)
        return FormattedText(caretRange: lineRange)
    }
}

extension NSAttributedString.Key {

    /// Indicates the last character *before* the fixed/corrected caret location.
    static let caret = NSAttributedString.Key("markdown.caret")
}

// MARK: - Words Formatting

extension NSAttributedString.Key {
    static let blockDepth = NSAttributedString.Key("markdown.blockDepth")
    static let indentBullet = NSAttributedString.Key("markdown.indentBullet")
}

fileprivate extension NSAttributedString.Key {
    static let italic  = NSAttributedString.Key("markdown.italic")
    static let bold    = NSAttributedString.Key("markdown.bold")
    static let heading = NSAttributedString.Key("markdown.heading")
}

fileprivate final class WordsFormatter: Formatter {

    private struct WordFormat {
        var key: NSAttributedString.Key
        var regex: NSRegularExpression
        var style: [NSAttributedString.Key: Any]
        var enclosingChars: String

        func markdown(for text: String) -> String {
            return "\(enclosingChars)\(text)\(enclosingChars)"
        }
    }

    private let italicFormat = WordFormat(
        key: .italic,
        regex: regex("(?<=^|[^*])[*_]{1}(?<text>\\w+(\\s+\\w+)*)[*_]{1}"),
        style: [.italic: true, .font: UIFont.italicSystemFont(ofSize: mainContentFontSize), .foregroundColor: UIColor.label],
        enclosingChars: "*"
    )

    private let boldFormat = WordFormat(
        key:   .bold,
        regex: regex("[*_]{2}(?<text>\\w+(\\s+\\w+)*)[*_]{2}"),
        style: [.bold: true, .font: UIFont.systemFont(ofSize: mainContentFontSize, weight: .bold), .foregroundColor: UIColor.label],
        enclosingChars: "**"
    )

    func formatWords(in change: ChangedText) -> FormattedText? {
        for wordsFormat in [boldFormat, italicFormat] {
            if let formattedText = formatWords(in: change, using: wordsFormat) {
                return formattedText
            }
        }
        return nil
    }

    private func formatWords(in change: ChangedText,
                             using format: WordFormat) -> FormattedText? {
        let match = format.regex.firstMatch(in: backingStore.string, range: change.lineRange)

        if let match = match {
            // Captures the target text.
            let text = storage.backingString.substring(with: match.range(withName: "text"))
            let attribText = NSMutableAttributedString(
                string: text,
                attributes: format.style
            )

            // Adds trailing whitespace if needed.
            let nextChar = storage.character(at: match.range.max)
            if nextChar == nil || nextChar != " " {
                attribText.append(NSAttributedString(string: " ", attributes: bodyStyle))
            }

            // Fixes caret position and applies words formatting.
            attribText.addAttribute(
                .caret, value: true,
                range: NSMakeRange(attribText.length - 1, 1)
            )
            storage.replaceCharacters(in: match.range, with: attribText)
            return formattedText(caretAtLine: match.range.location)
        } else {
            return nil
        }
    }

    func format(_ markdownString: NSAttributedString) -> NSAttributedString {
        var markdownString = markdownString
        for wordsFormat in [boldFormat, italicFormat] {
            markdownString = format(markdownString, using: wordsFormat)
        }
        return markdownString
    }

    private func format(_ markdownString: NSAttributedString,
                        using format: WordFormat) -> NSAttributedString {
        return markdownString.mapLines {
            (attribLine) in
            let line = attribLine.string
            let lineRange = attribLine.range

            let mutableLine = NSMutableAttributedString(attributedString: attribLine)
            let matches = format.regex.matches(in: line, range: lineRange)

            for match in matches.reversed() {
                let text = (line as NSString).substring(with: match.range(withName: "text"))
                let formattedText = NSAttributedString(string: text, attributes: format.style)
                mutableLine.replaceCharacters(in: match.range, with: formattedText)
            }
            return mutableLine
        }
    }

    func deformat(_ formattedString: NSAttributedString) -> NSAttributedString {
        var markdownString = formattedString
        for wordsFormat in [boldFormat, italicFormat] {
            markdownString = deformat(markdownString, using: wordsFormat)
        }
        return markdownString
    }

    private func deformat(_ attribString: NSAttributedString,
                          using format: WordFormat) -> NSAttributedString {
        return attribString.mapLines {
            (attribLine) in
            let line = attribLine.string as NSString
            let mutableLine = NSMutableAttributedString(attributedString: attribLine)
            let attribs = attribLine.attribute(format.key, in: attribLine.range)

            for attrib in attribs.reversed() {
                let text = line.substring(with: attrib.range)
                let markdownText = format.markdown(for: text)
                mutableLine.removeAttribute(format.key, range: attrib.range)
                mutableLine.replaceCharacters(in: attrib.range, with: markdownText)
            }
            return mutableLine
        }
    }
}

// MARK: - Headings Formatting

fileprivate final class HeadingsFormatter: Formatter {

    private struct HeadingLevel {
        let level: Int
        let fontSize: CGFloat
        let lineHeight: CGFloat
    }

    private static let levels: [HeadingLevel] = [
        HeadingLevel(level: 1, fontSize: 28, lineHeight: 36),
        HeadingLevel(level: 2, fontSize: 24, lineHeight: 32),
        HeadingLevel(level: 3, fontSize: 20, lineHeight: 28),
    ]

    private static let headingRegex = regex("^(#{1,3})\\s+(.+)")
    /// Like headingRegex but allows empty content after the space — used during
    /// interactive editing so the heading format triggers immediately on typing
    /// the space, before any content text is entered.
    private static let headingTriggerRegex = regex("^(#{1,3})\\s+(.*)")

    private func headingStyle(for level: Int) -> [NSAttributedString.Key: Any] {
        let info = HeadingsFormatter.levels.first { $0.level == level }
            ?? HeadingsFormatter.levels.last!
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 12
        paragraphStyle.minimumLineHeight = info.lineHeight
        paragraphStyle.maximumLineHeight = info.lineHeight
        return [
            .font: UIFont.systemFont(ofSize: info.fontSize, weight: .bold),
            .foregroundColor: UIColor.label,
            .kern: NSNumber(value: Double(info.fontSize * -0.01)),
            .paragraphStyle: paragraphStyle,
            .heading: level,
        ]
    }

    // MARK: - Interactive editing

    func formatHeading(in change: ChangedText) -> FormattedText? {
        guard change.contents == " " && change.mask.contains(.editedCharacters) else {
            return nil
        }
        let lineRange = backingStore.lineRange(for: change.range.location)
        let lineString = (backingStore.string as NSString).substring(with: lineRange)
        let lineNSRange = NSMakeRange(0, (lineString as NSString).length)

        // Use headingTriggerRegex which allows empty content after the space,
        // so the heading format applies immediately when the user types "## "
        // (before any content text is entered).
        guard let match = HeadingsFormatter.headingTriggerRegex.firstMatch(in: lineString, range: lineNSRange) else {
            return nil
        }

        let hashes = (lineString as NSString).substring(with: match.range(at: 1))
        let level = hashes.count
        guard level >= 1 && level <= 3 else { return nil }

        let textRange = match.range(at: 2)
        let text = textRange.length > 0
            ? (lineString as NSString).substring(with: textRange)
            : ""
        let prefixLength = textRange.location  // characters before content start
        let style = headingStyle(for: level)

        let styledText: NSMutableAttributedString
        if text.isEmpty {
            // No visible content yet — use a zero-width space as a placeholder
            // to keep the line alive in the backing store with heading attributes.
            // This ensures deformat can find the heading attribute and re-insert
            // the "## " prefix when saving.
            styledText = NSMutableAttributedString(string: zeroWidthSpace, attributes: style)
        } else {
            styledText = NSMutableAttributedString(string: text, attributes: style)
        }

        // Preserve trailing newline if present
        let fullLineEnd = lineRange.location + lineRange.length
        let textEnd = lineRange.location + prefixLength + (text as NSString).length
        if textEnd < fullLineEnd {
            styledText.append(NSAttributedString(string: "\n", attributes: style))
        }

        if text.isEmpty {
            // Place caret on the zero-width space (index 0) so the cursor
            // lands right after it (position 1 in styledText = right after
            // ZWS, before any trailing newline). This keeps cursor on the
            // heading line, not the next line.
            styledText.addAttribute(.caret, value: true, range: NSMakeRange(0, 1))
        } else {
            styledText.addAttribute(.caret, value: true,
                                    range: NSMakeRange(styledText.length - 1, 1))
        }

        // Replace the entire line content (prefix + text + optional newline) with styled text
        let replaceRange = NSMakeRange(lineRange.location, lineRange.length)
        storage.replaceCharacters(in: replaceRange, with: styledText)

        var result = formattedText(caretAtLine: lineRange.location)
        // When content is empty, there's no adjacent heading-styled character
        // for resetTypingAttributes to inherit from, so provide the heading
        // style explicitly so subsequent typing is correctly styled.
        if text.isEmpty {
            result.typingStyle = style
        }
        return result
    }

    // MARK: - Load-time formatting

    func format(_ markdownString: NSAttributedString) -> NSAttributedString {
        return markdownString.mapLines { attribLine in
            let line = attribLine.string
            let lineRange = attribLine.range

            // Use headingTriggerRegex so "## " with no content is also
            // recognized on load (e.g., after saving an empty heading).
            guard let match = HeadingsFormatter.headingTriggerRegex.firstMatch(in: line, range: lineRange) else {
                return attribLine
            }

            let hashes = (line as NSString).substring(with: match.range(at: 1))
            let level = hashes.count
            guard level >= 1 && level <= 3 else { return attribLine }

            let textRange = match.range(at: 2)
            let text = textRange.length > 0
                ? (line as NSString).substring(with: textRange)
                : ""
            let style = headingStyle(for: level)

            let content = text.isEmpty ? zeroWidthSpace : text
            let mutableLine = NSMutableAttributedString(string: content, attributes: style)

            // Preserve trailing newline with heading style
            let afterText = textRange.location + textRange.length
            if afterText < lineRange.length {
                let trailing = (line as NSString).substring(from: afterText)
                mutableLine.append(NSAttributedString(string: trailing, attributes: style))
            }

            return mutableLine
        }
    }

    // MARK: - Save-time deformatting

    func deformat(_ attribString: NSAttributedString) -> NSAttributedString {
        return attribString.mapLines { attribLine in
            let mutableLine = NSMutableAttributedString(attributedString: attribLine)
            guard mutableLine.length > 0 else { return mutableLine }

            // Check if the first character has a heading attribute
            guard let level = mutableLine.attribute(.heading, at: 0, effectiveRange: nil) as? Int else {
                return mutableLine
            }

            let prefix = String(repeating: "#", count: level) + " "
            mutableLine.removeAttribute(.heading, range: mutableLine.range)
            // Strip placeholder zero-width spaces that formatHeading inserts
            // for empty heading lines.
            let lineStr = mutableLine.string
            let zwsRanges = lineStr.enumerated()
                .filter { String($0.element) == zeroWidthSpace }
                .map { NSRange(location: $0.offset, length: 1) }
            for r in zwsRanges.reversed() {
                mutableLine.replaceCharacters(in: r, with: "")
            }
            mutableLine.insert(NSAttributedString(string: prefix), at: 0)
            return mutableLine
        }
    }
}

// MARK: - Lists Formatting

extension NSAttributedString.Key {
    static let list = NSAttributedString.Key("markdown.list")
}

let zeroWidthSpace = "\u{200B}"

/// Identifies a given list item (or list kind).
/// This is used as the *value* for the `NSAttributedString.Key.list` custom attribute.
enum ListItem: CaseIterable, CustomStringConvertible {

    case bullet
    case dashed
    case ordered(Int?)
    case checkmark(Bool?)

    static let allCases = [bullet, ordered(nil), checkmark(nil)]

    var description: String {
        return "\(rawValue) list"
    }

    var itemMarker: String {
        switch self {
        case .bullet:
            return "•"
        case .dashed:
            return "–"
        case .ordered(let number):
            return "\(number!)."
        case .checkmark:
            return zeroWidthSpace
        }
    }

    var nextItem: ListItem {
        switch self {
        case .bullet:
            return self
        case .dashed:
            return self
        case .ordered(let number):
            return .ordered(number! + 1)
        case .checkmark:
            return .checkmark(false)
        }
    }

    private static let bulletItemRegex    = regex("^([*]\\h).*")
    private static let dashedItemRegex    = regex("^([-]\\h).*")
    private static let orderedItemRegex   = regex("^((?<number>[0-9]+)[.]\\h).*")
    private static let checkmarkItemRegex = regex("^(\\[(?<bool>_|x)\\]\\h).*")

    var itemRegex: NSRegularExpression {
        switch self {
        case .bullet:
            return ListItem.bulletItemRegex
        case .dashed:
            return ListItem.dashedItemRegex
        case .ordered:
            return ListItem.orderedItemRegex
        case .checkmark:
            return ListItem.checkmarkItemRegex
        }
    }

    func firstMatch(in string: String, range: NSRange) -> (kind: ListItem, range: NSRange)? {
        guard let match = itemRegex.firstMatch(in: string, range: range) else {
            return nil
        }
        switch self {
        case .bullet, .dashed:
            return (self, match.range(at: 1))
        case .ordered:
            let numberRange = match.range(withName: "number")
            let number = (string as NSString).substring(with: numberRange)
            return (.ordered(Int(number)), match.range(at: 1))
        case .checkmark:
            let boolRange = match.range(withName: "bool")
            let boolFlag = (string as NSString).substring(with: boolRange)
            let bool: Bool
            switch boolFlag {
            case "_":
                bool = false
            case "x":
                bool = true
            default:
                preconditionFailure("Unknown bool flag: \(boolFlag)")
            }
            return (.checkmark(bool), match.range(at: 1))
        }
    }

    var paragraphStyle: NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 10
        paragraphStyle.headIndent = 10
        paragraphStyle.paragraphSpacing = 12
        paragraphStyle.minimumLineHeight = mainContentLineHeight
        paragraphStyle.maximumLineHeight = mainContentLineHeight

        switch self {
        case .bullet, .dashed, .ordered:
            break
        case .checkmark:
            paragraphStyle.firstLineHeadIndent = 26
            paragraphStyle.headIndent = 26
        }
        return paragraphStyle
    }

    var kern: NSNumber {
        switch self {
        case .bullet, .dashed:
            return NSNumber(value: 6.5)
        case .ordered:
            return NSNumber(value: 3.5)
        case .checkmark:
            return NSNumber(value: 0.0)
        }
    }

    var markdownPrefix: String {
        switch self {
        case .bullet:
            return "* "
        case .dashed:
            return "- "
        case .ordered(let number):
            return "\(number!). "
        case .checkmark(let bool):
            if bool! {
                return "[x] "
            } else {
                return "[_] "
            }
        }
    }
}

/// Support for encoding as an attribute value.
extension ListItem: RawRepresentable {

    private static let orderedRegex = regex("ordered[(](?<number>[0-9]+)[)]")
    private static let checkmarkRegex = regex("checkmark[(](?<bool>true|false)[)]")

    init?(rawValue: String) {
        switch rawValue {
        case "bullet":
            self = .bullet
        case "dashed":
            self = .dashed
        case "ordered":
            self = .ordered(nil)
        case "checkmark":
            self = .checkmark(nil)
        default:
            if let orderedMatch = ListItem.orderedRegex.firstMatch(in: rawValue) {
                let numberRange = orderedMatch.range(withName: "number")
                let number = (rawValue as NSString).substring(with: numberRange)
                self = .ordered(Int(number))
            } else if let checkmarkMatch = ListItem.checkmarkRegex.firstMatch(in: rawValue) {
                let boolRange = checkmarkMatch.range(withName: "bool")
                let bool = (rawValue as NSString).substring(with: boolRange)
                self = .checkmark(Bool(bool)!)
            } else {
                return nil
            }
        }
    }

    var rawValue: String {
        switch self {
        case .bullet:
            return "bullet"
        case .dashed:
            return "dashed"
        case .ordered(let number):
            if let number = number {
                return "ordered(\(number))"
            } else {
                return "ordered"
            }
        case .checkmark(let bool):
            if let bool = bool {
                return "checkmark(\(bool))"
            } else {
                return "checkmark"
            }
        }
    }
}

fileprivate final class ListsFormatter: Formatter {

    func itemStyle(for listItem: ListItem) -> [NSAttributedString.Key: Any] {
        var itemStyle = bodyStyle
        itemStyle[.list] = listItem.rawValue
        itemStyle[.paragraphStyle] = listItem.paragraphStyle

        return itemStyle
    }

    private func itemMarker(for listItem: ListItem) -> NSAttributedString {
        let itemMarker = NSMutableAttributedString(
            string: listItem.itemMarker,
            attributes: itemStyle(for: listItem)
        )
        itemMarker.addAttribute(
            .kern, value: listItem.kern,
            range: NSMakeRange(itemMarker.length - 1, 1)
        )
        itemMarker.addAttribute(
            .caret, value: true,
            range: NSMakeRange(itemMarker.length - 1, 1)
        )
        return itemMarker
    }

    func listItem(at lineRange: NSRange, effectiveRange: NSRangePointer? = nil) -> ListItem? {
        let lineRange = storage.lineRange(for: lineRange.location)
        let lineStart = lineRange.location
        guard lineStart < backingStore.length else {
            return nil
        }
        let rawListKind = backingStore.attribute(
            .list,
            at: lineStart,
            longestEffectiveRange: effectiveRange,
            in: lineRange
        )
        if let rawListKind = rawListKind as? String {
            return ListItem(rawValue: rawListKind)!
        } else {
            return nil
        }
    }

    func insertListItem(_ listItem: ListItem, at index: Int) {
        let lineRange = storage.lineRange(for: index)
        let itemMarker = self.itemMarker(for: listItem)
        storage.replaceCharacters(in: NSMakeRange(lineRange.location, 0), with: itemMarker)
    }

    @discardableResult
    func updateListItem(_ newListItem: ListItem, atLine lineRange: NSRange) -> Bool {
        var listItemRange = NSMakeRange(0, 0)
        guard let oldListItem = listItem(at: lineRange, effectiveRange: &listItemRange) else {
            return false
        }
        switch (oldListItem, newListItem) {
        case (.bullet, .bullet), (.dashed, .dashed),
             (.ordered, .ordered), (.checkmark, .checkmark):
            storage.replaceCharacters(in: listItemRange, with: newListItem.itemMarker)
            storage.addAttribute(.list, value: newListItem.rawValue, range: listItemRange)
        default:
             preconditionFailure("List not compatible at \(lineRange)")
        }
        return true
    }

    func formatLists(for change: ChangedText) -> FormattedText? {
        for _ in ListItem.allCases {
            if let textFormatted = formatEmptyListItem(for: change) {
                return textFormatted
            }

            if let textFormatted = formatNewListItem(for: change) {
                return textFormatted
            }

            if let textFormatted = formatNewList(for: change) {
                return textFormatted
            }
        }

        // Fixes previous formatting issues, if any.
        // Only reset to body style if the character isn't already heading-formatted.
        // Without this guard, typing on a heading line would lose the heading style
        // because this cleanup overwrites all non-list attributes with bodyStyle.
        if listItem(at: change.range) == nil {
            let hasHeading: Bool = {
                guard change.range.location < backingStore.length else { return false }
                let lineRange = backingStore.lineRange(for: change.range.location)
                var found = false
                backingStore.enumerateAttribute(.heading, in: lineRange) { val, _, stop in
                    if val != nil {
                        found = true
                        stop.pointee = true
                    }
                }
                return found
            }()
            if !hasHeading {
                storage.setAttributes(bodyStyle, range: change.range)
            }
        }

        return nil
    }

    private func formatNewList(for change: ChangedText) -> FormattedText? {
        for listItem in ListItem.allCases {
            let itemMatch = listItem.firstMatch(
                in: backingStore.string,
                range: change.lineRange
            )
            if let itemMatch = itemMatch {
                let itemMarker = self.itemMarker(for: itemMatch.kind)
                storage.replaceCharacters(in: itemMatch.range, with: itemMarker)
                return formattedText(caretAtLine: itemMatch.range.location)
            }
        }
        return nil
    }

    private func formatNewListItem(for change: ChangedText) -> FormattedText? {
        guard let listItem = change.listItem, change.isNewLine else {
            return nil
        }
        let nextItem = listItem.nextItem
        let itemMarker = self.itemMarker(for: nextItem)
        let lineStart = NSMakeRange(change.range.max, 0)

        storage.replaceCharacters(in: lineStart, with: itemMarker)
        switch nextItem {
        case .ordered:
            reformatFollowingOrderedItems(nextItem, at: lineStart.location)
        case .bullet, .dashed, .checkmark:
            break
        }
        return formattedText(caretAtLine: lineStart.location)
    }

    private func reformatFollowingOrderedItems(_ item: ListItem, at lineStart: Int) {
        var nextItem = item
        var lineStart = lineStart

        while true {
            let nextLine = storage.lineRange(for: lineStart).max
            guard nextLine < storage.length else { break }

            nextItem = nextItem.nextItem
            if !updateListItem(nextItem, atLine: NSMakeRange(nextLine, 0)) { break }
            lineStart = nextLine
        }
    }

    private func formatEmptyListItem(for change: ChangedText) -> FormattedText? {
        guard let listItem = change.listItem, change.isNewLine else {
            return nil
        }

        // Is this line empty (i.e., only marker + newline)?
        guard change.lineRange.length <= listItem.itemMarker.count + 1 else {
            return nil
        }

        // Reset the text style of the character that follows.
        let nextChar = change.lineRange.max
        var caretOffset = 0
        if nextChar < storage.length {
            storage.replaceCharacters(in: NSMakeRange(nextChar, 0), with: zeroWidthSpace)
            storage.setAttributes(bodyStyle, range: NSMakeRange(nextChar, 1))
            caretOffset = 1
        }

        storage.setAttributes(bodyStyle, range: change.lineRange)
        storage.replaceCharacters(in: change.lineRange, with: "") // Deletes line.

        // Fixes caret position.
        let itemNewline = NSMakeRange(change.lineRange.location - 1 + caretOffset, 1)
        storage.setAttribute(.caret, value: true, range: itemNewline)

        // Restore bodyStyle on the caret character (setAttribute wipes all attributes)
        // and on the preceding newline, so the paragraph after the list gets
        // normal body spacing instead of the list's tight spacing.
        for (key, value) in bodyStyle {
            storage.addAttribute(key, value: value, range: itemNewline)
        }
        let newlineIndex = change.lineRange.location - 1
        if newlineIndex >= 0 && newlineIndex != itemNewline.location {
            storage.setAttributes(bodyStyle, range: NSMakeRange(newlineIndex, 1))
        }

        return formattedText(caretAtLine: itemNewline.location)
    }

    func format(in markdownString: NSAttributedString) -> NSAttributedString {
        var markdownString = markdownString
        for listItem in ListItem.allCases {
            markdownString = format(listItem, in: markdownString)
        }
        return markdownString
    }

    /// Formats a Markdown-ish string as an attributed string.
    func format(_ listItem: ListItem,
                in markdownString: NSAttributedString) -> NSAttributedString {
        return markdownString.mapLines {
            (attribLine) in
            let line = attribLine.string
            let lineRange = attribLine.range

            if let itemMatch = listItem.firstMatch(in: line, range: lineRange) {
                let mutableLine = NSMutableAttributedString(attributedString: attribLine)
                let itemMarker = self.itemMarker(for: itemMatch.kind)
                mutableLine.replaceCharacters(in: itemMatch.range, with: itemMarker)
                return mutableLine
            } else {
                return attribLine
            }
        }
    }

    /// Deformats an attributed string to a Markdown-ish string.
    func deformat(_ attribString: NSAttributedString) -> NSAttributedString {
        return attribString.mapLines {
            (attribLine) in
            let mutableLine = NSMutableAttributedString(attributedString: attribLine)
            let attribs = attribLine.attribute(.list, in: attribLine.range)

            if let attrib = attribs.first {
                let listItem = ListItem(rawValue: attrib.value as! String)!
                mutableLine.removeAttribute(.list, range: attrib.range)
                mutableLine.replaceCharacters(in: attrib.range, with: listItem.markdownPrefix)
            }

            trimeZeroWidthWhitespaces(from: mutableLine.mutableString)
            return mutableLine
        }
    }

    private let zeroWidthSpaceRegex = regex(zeroWidthSpace)

    private func trimeZeroWidthWhitespaces(from str: NSMutableString) {
        zeroWidthSpaceRegex.replaceMatches(in: str, range: str.range, withTemplate: "")
    }
}

// MARK: - Indent Formatting

fileprivate final class IndentFormatter: Formatter {

    private static let indentWidth: CGFloat = 24

    private static let bulletExtra: CGFloat = 16

    /// When true, bullet character varies by depth and depth-0 lines have no bullet.
    var nodeViewMode = false

    func paragraphStylePublic(for depth: Int) -> NSParagraphStyle {
        return paragraphStyle(for: depth)
    }

    private func paragraphStyle(for depth: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let indent: CGFloat
        let hasBullet: Bool
        if nodeViewMode {
            // In node view, depth 0 = no indent/bullet, depth 1+ = indent with bullet
            indent = depth > 0 ? CGFloat(depth) * IndentFormatter.indentWidth : 0
            hasBullet = !bulletString(for: depth).isEmpty
        } else {
            indent = CGFloat(depth) * IndentFormatter.indentWidth
            hasBullet = depth > 0
        }
        style.firstLineHeadIndent = indent
        style.headIndent = hasBullet ? indent + IndentFormatter.bulletExtra : indent
        style.paragraphSpacing = 12
        style.minimumLineHeight = mainContentLineHeight
        style.maximumLineHeight = mainContentLineHeight
        return style
    }

    // MARK: - Load-time formatting

    /// Strip leading `\t` characters, store depth as `.blockDepth` attribute,
    /// apply paragraph indent style, and insert bullet prefix for indented lines.
    func format(in markdownString: NSAttributedString) -> NSAttributedString {
        return markdownString.mapLines { attribLine in
            let line = attribLine.string
            var depth = 0
            for ch in line {
                guard ch == "\t" else { break }
                depth += 1
            }
            guard depth > 0 else {
                // Still stamp depth=0 on every line for consistency
                let mutableLine = NSMutableAttributedString(attributedString: attribLine)
                mutableLine.addAttribute(.blockDepth, value: 0, range: mutableLine.range)
                return mutableLine
            }

            let mutableLine = NSMutableAttributedString(attributedString: attribLine)
            // Remove leading tabs
            mutableLine.replaceCharacters(in: NSMakeRange(0, depth), with: "")

            // In node view mode, depth-0 lines (first-level children) get no bullet
            let bulletStr = bulletString(for: depth)
            if !bulletStr.isEmpty {
                let bullet = NSMutableAttributedString(
                    string: bulletStr,
                    attributes: storage.bodyStyle
                )
                bullet.addAttribute(.indentBullet, value: true, range: NSMakeRange(0, bullet.length))
                mutableLine.insert(bullet, at: 0)
            }
            // Apply depth attribute & paragraph indent
            mutableLine.addAttribute(.blockDepth, value: depth, range: mutableLine.range)
            mutableLine.addAttribute(.paragraphStyle, value: self.paragraphStyle(for: depth), range: mutableLine.range)
            return mutableLine
        }
    }

    // MARK: - Save-time deformatting

    /// Strip bullet prefix and re-insert `\t` characters based on `.blockDepth` attribute.
    func deformat(_ attribString: NSAttributedString) -> NSAttributedString {
        return attribString.mapLines { attribLine in
            let mutableLine = NSMutableAttributedString(attributedString: attribLine)
            let depth: Int
            if mutableLine.length > 0,
               let val = mutableLine.attribute(.blockDepth, at: 0, effectiveRange: nil) as? Int {
                depth = val
            } else {
                depth = 0
            }
            guard depth > 0 else { return mutableLine }

            // Strip bullet prefix (chars marked .indentBullet) from line start
            var bulletEnd = 0
            if mutableLine.length > 0 {
                mutableLine.enumerateAttribute(.indentBullet, in: mutableLine.range) { val, range, stop in
                    if val as? Bool == true, range.location == bulletEnd {
                        bulletEnd = range.location + range.length
                    } else {
                        stop.pointee = true
                    }
                }
            }
            if bulletEnd > 0 {
                mutableLine.replaceCharacters(in: NSMakeRange(0, bulletEnd), with: "")
            }

            let tabs = String(repeating: "\t", count: depth)
            mutableLine.insert(NSAttributedString(string: tabs), at: 0)
            return mutableLine
        }
    }

    // MARK: - Live editing: dash indent

    private static let dashPrefixRegex = regex("^-\\h")

    /// When the user types "- " at the start of a line, remove "- " and indent.
    func handleDashIndent(for change: ChangedText) -> FormattedText? {
        // Only trigger on space character typed
        guard change.contents == " " && change.mask.contains(.editedCharacters) else {
            return nil
        }
        let lineRange = backingStore.lineRange(for: change.range.location)
        let lineString = (backingStore.string as NSString).substring(with: lineRange)

        guard IndentFormatter.dashPrefixRegex.firstMatch(in: lineString, range: NSMakeRange(0, (lineString as NSString).length)) != nil else {
            return nil
        }

        // Get current depth
        let currentDepth: Int
        if lineRange.location < backingStore.length,
           let val = backingStore.attribute(.blockDepth, at: lineRange.location, effectiveRange: nil) as? Int {
            currentDepth = val
        } else {
            currentDepth = 0
        }
        let newDepth = currentDepth + 1

        // Batch all changes in a single editing transaction so that
        // processEditing() fires only once — AFTER blockDepth is set.
        // Previously, storage.replaceCharacters() triggered its own
        // editing cycle before blockDepth was applied, causing a
        // premature sync that saw depth 0.
        let dashRange = NSMakeRange(lineRange.location, 2)

        storage.beginEditing()
        backingStore.replaceCharacters(in: dashRange, with: "")

        // Insert bullet prefix (depth-aware in node view mode)
        let bullet = makeBullet(for: newDepth)
        if bullet.length > 0 {
            backingStore.insert(bullet, at: lineRange.location)
        }

        // Apply new depth to the line
        let updatedLineRange = backingStore.lineRange(for: lineRange.location)
        if updatedLineRange.length > 0 {
            backingStore.addAttribute(.blockDepth, value: newDepth, range: updatedLineRange)
            backingStore.addAttribute(.paragraphStyle, value: paragraphStyle(for: newDepth), range: updatedLineRange)
        }

        // Mark caret after bullet
        let caretPos = lineRange.location + bullet.length
        if caretPos < backingStore.length {
            backingStore.addAttribute(.caret, value: true, range: NSMakeRange(caretPos, 1))
        }

        // Net change: removed 2 chars ("- "), inserted bullet.length chars
        let netChange = bullet.length - 2
        storage.edited(.editedCharacters, range: dashRange, changeInLength: netChange)
        storage.endEditing()

        return FormattedText(caretRange: NSMakeRange(caretPos, 0))
    }

    // MARK: - Bullet helpers

    private static let bulletPrefix = "• "

    /// Returns the bullet string for the given depth in node view mode.
    func bulletString(for depth: Int) -> String {
        guard nodeViewMode else { return IndentFormatter.bulletPrefix }
        switch depth {
        case 0: return "" // first-level children: no bullet
        case 1: return "• "
        case 2: return "◦ "
        default: return "– "
        }
    }

    func makeBulletPublic(for depth: Int = -1) -> NSAttributedString {
        return makeBullet(for: depth)
    }

    private func makeBullet(for depth: Int = -1) -> NSAttributedString {
        let prefix = depth >= 0 ? bulletString(for: depth) : IndentFormatter.bulletPrefix
        let bullet = NSMutableAttributedString(
            string: prefix,
            attributes: storage.bodyStyle
        )
        bullet.addAttribute(.indentBullet, value: true, range: NSMakeRange(0, bullet.length))
        return bullet
    }

    /// Returns true if the line already starts with a bullet marked `.indentBullet`.
    func lineHasBullet(at lineRange: NSRange) -> Bool {
        guard lineRange.length >= IndentFormatter.bulletPrefix.count else { return false }
        let checkLen = (IndentFormatter.bulletPrefix as NSString).length
        var found = false
        backingStore.enumerateAttribute(.indentBullet, in: NSMakeRange(lineRange.location, checkLen)) { val, _, stop in
            if val as? Bool == true {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// Remove the bullet prefix (chars marked `.indentBullet`) from the start of a line.
    /// Returns the number of characters removed.
    @discardableResult
    private func stripBullet(at lineStart: Int) -> Int {
        let lineRange = backingStore.lineRange(for: lineStart)
        guard lineRange.length > 0 else { return 0 }
        // Find contiguous .indentBullet run from line start
        var bulletEnd = lineRange.location
        backingStore.enumerateAttribute(.indentBullet, in: lineRange) { val, range, stop in
            if val as? Bool == true, range.location == bulletEnd {
                bulletEnd = range.max
            } else {
                stop.pointee = true
            }
        }
        let bulletLen = bulletEnd - lineRange.location
        guard bulletLen > 0 else { return 0 }
        backingStore.replaceCharacters(in: NSMakeRange(lineRange.location, bulletLen), with: "")
        return bulletLen
    }

    // MARK: - Programmatic indent/outdent

    func indentLine(at index: Int) {
        let lineRange = backingStore.lineRange(for: index)
        guard lineRange.length > 0 else { return }

        let currentDepth: Int
        if let val = backingStore.attribute(.blockDepth, at: lineRange.location, effectiveRange: nil) as? Int {
            currentDepth = val
        } else {
            currentDepth = 0
        }
        let newDepth = currentDepth + 1

        storage.beginEditing()

        var lengthChange = 0
        if nodeViewMode {
            // In node view, swap bullet based on new depth
            let removed = stripBullet(at: lineRange.location)
            lengthChange -= removed
            let newBulletStr = bulletString(for: newDepth)
            if !newBulletStr.isEmpty {
                let bullet = makeBullet(for: newDepth)
                backingStore.insert(bullet, at: lineRange.location)
                lengthChange += bullet.length
            }
        } else {
            // Insert bullet when transitioning from depth 0 → 1
            if currentDepth == 0 && !lineHasBullet(at: lineRange) {
                let bullet = makeBullet()
                backingStore.insert(bullet, at: lineRange.location)
                lengthChange = bullet.length
            }
        }

        let updatedLineRange = backingStore.lineRange(for: index + max(lengthChange, 0))
        backingStore.addAttribute(.blockDepth, value: newDepth, range: updatedLineRange)
        backingStore.addAttribute(.paragraphStyle, value: paragraphStyle(for: newDepth), range: updatedLineRange)
        storage.edited(lengthChange != 0 ? .editedCharacters : .editedAttributes,
                       range: lineRange,
                       changeInLength: lengthChange)
        storage.endEditing()
    }

    func outdentLine(at index: Int) {
        let lineRange = backingStore.lineRange(for: index)
        guard lineRange.length > 0 else { return }

        let currentDepth: Int
        if let val = backingStore.attribute(.blockDepth, at: lineRange.location, effectiveRange: nil) as? Int {
            currentDepth = val
        } else {
            currentDepth = 0
        }
        guard currentDepth > 0 else { return }
        let newDepth = currentDepth - 1

        storage.beginEditing()

        var lengthChange = 0
        if nodeViewMode {
            // Swap bullet based on new depth
            let removed = stripBullet(at: lineRange.location)
            lengthChange -= removed
            let newBulletStr = bulletString(for: newDepth)
            if !newBulletStr.isEmpty {
                let bullet = makeBullet(for: newDepth)
                backingStore.insert(bullet, at: lineRange.location)
                lengthChange += bullet.length
            }
        } else {
            // Remove bullet when transitioning from depth 1 → 0
            if newDepth == 0 {
                let removed = stripBullet(at: lineRange.location)
                lengthChange = -removed
            }
        }

        let updatedLineRange = backingStore.lineRange(for: lineRange.location)
        backingStore.addAttribute(.blockDepth, value: newDepth, range: updatedLineRange)
        backingStore.addAttribute(.paragraphStyle, value: paragraphStyle(for: newDepth), range: updatedLineRange)
        storage.edited(lengthChange != 0 ? .editedCharacters : .editedAttributes,
                       range: lineRange,
                       changeInLength: lengthChange)
        storage.endEditing()
    }
}

// MARK: - NSRange Helpers

extension NSRange {

    /// Returns the sum of the location and length of the range.
    var max: Int {
        return self.location + self.length
    }

    func nextChar() -> NSRange {
        return NSRange(location: self.location + 1, length: self.length)
    }
}
