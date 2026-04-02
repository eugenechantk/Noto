#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class MarkdownTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()
    private let formatter = MarkdownFormatter()
    private(set) var activeLine: NSRange?
    private(set) var cursorPosition: Int?

    // MARK: - NSTextStorage required overrides

    override var string: String { backing.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        super.processEditing()
    }

    // MARK: - Load / Export

    func load(markdown: String) {
        let fullRange = NSRange(location: 0, length: backing.length)
        replaceCharacters(in: fullRange, with: markdown)
        render(activeLine: activeLine, cursorPosition: cursorPosition)
    }

    func render(activeLine: NSRange?, cursorPosition: Int? = nil) {
        self.activeLine = activeLine
        self.cursorPosition = cursorPosition
        let formatted = formatter.makeAttributedString(
            markdown: backing.string,
            activeLine: activeLine,
            cursorPosition: cursorPosition
        )
        let fullRange = NSRange(location: 0, length: backing.length)
        guard fullRange.length > 0 else { return }

        beginEditing()
        formatted.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            backing.setAttributes(attrs, range: range)
        }
        edited(.editedAttributes, range: fullRange, changeInLength: 0)
        endEditing()
    }

    func setActiveLine(_ range: NSRange?, cursorPosition: Int? = nil) {
        let cursorChanged = self.cursorPosition != cursorPosition
        guard activeLine != range || cursorChanged else { return }
        render(activeLine: range, cursorPosition: cursorPosition)
    }

    func markdownContent() -> String {
        backing.string
    }
}
