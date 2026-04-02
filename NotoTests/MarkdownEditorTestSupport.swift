import Testing
import UIKit
@testable import Noto

struct MarkdownEditorTestHarness {
    let storage: MarkdownTextStorage
    let layoutManager: MarkdownLayoutManager
    let container: NSTextContainer
}

func makeHarness(_ markdown: String, activeLine: NSRange? = nil, cursorPosition: Int? = nil) -> MarkdownEditorTestHarness {
    let storage = MarkdownTextStorage()
    let layoutManager = MarkdownLayoutManager()
    storage.addLayoutManager(layoutManager)

    let container = NSTextContainer(size: CGSize(width: 400, height: 2_000))
    container.widthTracksTextView = false
    layoutManager.addTextContainer(container)

    storage.load(markdown: markdown)
    if let activeLine {
        storage.setActiveLine(activeLine, cursorPosition: cursorPosition)
    }

    return MarkdownEditorTestHarness(storage: storage, layoutManager: layoutManager, container: container)
}

func paragraphStyle(in storage: MarkdownTextStorage, at offset: Int) -> NSParagraphStyle? {
    guard offset < storage.length else { return nil }
    return storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
}

func font(in storage: MarkdownTextStorage, at offset: Int) -> UIFont? {
    guard offset < storage.length else { return nil }
    return storage.attribute(.font, at: offset, effectiveRange: nil) as? UIFont
}

func foregroundColor(in storage: MarkdownTextStorage, at offset: Int) -> UIColor? {
    guard offset < storage.length else { return nil }
    return storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor
}

func strikethroughStyle(in storage: MarkdownTextStorage, at offset: Int) -> Int? {
    guard offset < storage.length else { return nil }
    return storage.attribute(.strikethroughStyle, at: offset, effectiveRange: nil) as? Int
}

func offset(of substring: String, in storage: MarkdownTextStorage) -> Int? {
    let range = (storage.string as NSString).range(of: substring)
    return range.location == NSNotFound ? nil : range.location
}

func lineRange(containing substring: String, in storage: MarkdownTextStorage) -> NSRange? {
    guard let location = offset(of: substring, in: storage) else { return nil }
    return (storage.string as NSString).lineRange(for: NSRange(location: location, length: 0))
}

func todoCheckbox(in storage: MarkdownTextStorage, at offset: Int) -> Bool? {
    guard offset < storage.length else { return nil }
    return storage.attribute(MarkdownTextStorage.todoCheckboxKey, at: offset, effectiveRange: nil) as? Bool
}

func todoCheckboxRect(in harness: MarkdownEditorTestHarness, at offset: Int) -> CGRect? {
    harness.layoutManager.glyphRange(for: harness.container)
    return harness.layoutManager.todoCheckboxRect(
        forCharacterRange: NSRange(location: offset, length: 1),
        in: harness.container
    )
}
