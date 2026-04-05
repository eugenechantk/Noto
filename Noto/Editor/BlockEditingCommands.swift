import Foundation

enum BlockLineBreakAction: Equatable {
    case none
    case insert(String)
    case removeCurrentLinePrefix(prefixLength: Int)
}

struct TextSelectionTransform: Equatable {
    let text: String
    let selection: NSRange
}

struct BlockEditingCommands {
    static func indentedLine(_ line: String) -> String {
        let (core, ending) = splitLineEnding(in: line)
        return "  " + core + ending
    }

    static func outdentedLine(_ line: String) -> String {
        let (core, ending) = splitLineEnding(in: line)

        if core.hasPrefix("\t") {
            return String(core.dropFirst()) + ending
        }

        let leadingSpaces = core.prefix(while: { $0 == " " }).count
        let spacesToRemove = min(leadingSpaces, 2)
        return String(core.dropFirst(spacesToRemove)) + ending
    }

    static func indentedLines(in text: String, selection: NSRange) -> TextSelectionTransform? {
        transformedSelectedLines(in: text, selection: selection, lineTransform: indentedLine) { _, _, offset in
            offset + 2
        }
    }

    static func outdentedLines(in text: String, selection: NSRange) -> TextSelectionTransform? {
        transformedSelectedLines(in: text, selection: selection, lineTransform: outdentedLine) { originalLine, _, offset in
            max(0, offset - removedIndentCount(in: originalLine))
        }
    }

    static func toggledTodoLines(in text: String, selection: NSRange) -> TextSelectionTransform? {
        transformedSelectedLines(in: text, selection: selection, lineTransform: TodoMarkdown.toolbarToggledLine) { originalLine, transformedLine, offset in
            let originalContentStart = TodoMarkdown.toolbarContentStart(in: originalLine)
            let transformedContentStart = TodoMarkdown.toolbarToggledContentStart(in: originalLine)

            if offset <= originalContentStart {
                return min(offset, transformedContentStart)
            }

            let contentOffset = offset - originalContentStart
            return min(transformedContentStart + contentOffset, transformedLine.utf16.count)
        }
    }

    static func toggledStrikethrough(in text: String, selection: NSRange) -> TextSelectionTransform? {
        let nsText = text as NSString
        guard selection.location != NSNotFound else { return nil }

        let safeLocation = max(0, min(selection.location, nsText.length))
        let safeLength = max(0, min(selection.length, nsText.length - safeLocation))
        let safeSelection = NSRange(location: safeLocation, length: safeLength)

        let targetRange: NSRange
        if safeSelection.length > 0 {
            targetRange = safeSelection
        } else if let wordRange = wordRange(around: safeSelection.location, in: nsText) {
            targetRange = wordRange
        } else {
            return nil
        }

        let selectedText = nsText.substring(with: targetRange)
        guard selectedText.contains(where: { !$0.isWhitespace && !$0.isNewline }) else { return nil }

        if let wrappedRange = wrappedStrikethroughRange(containing: targetRange, in: nsText) {
            let wrappedText = nsText.substring(with: wrappedRange)
            let unwrappedText = String(wrappedText.dropFirst(2).dropLast(2))
            let updatedText = nsText.replacingCharacters(in: wrappedRange, with: unwrappedText)
            return TextSelectionTransform(
                text: updatedText,
                selection: NSRange(location: wrappedRange.location, length: unwrappedText.utf16.count)
            )
        }

        let updatedText = NSMutableString(string: text)
        updatedText.insert("~~", at: NSMaxRange(targetRange))
        updatedText.insert("~~", at: targetRange.location)
        return TextSelectionTransform(
            text: updatedText as String,
            selection: NSRange(location: targetRange.location + 2, length: targetRange.length)
        )
    }

    private static func splitLineEnding(in line: String) -> (core: String, ending: String) {
        if line.hasSuffix("\r\n") {
            return (String(line.dropLast(2)), "\r\n")
        }
        if line.hasSuffix("\n") {
            return (String(line.dropLast()), "\n")
        }
        return (line, "")
    }

    private static func transformedSelectedLines(
        in text: String,
        selection: NSRange,
        lineTransform: (String) -> String,
        collapsedSelectionTransform: (String, String, Int) -> Int
    ) -> TextSelectionTransform? {
        let nsText = text as NSString
        guard selection.location != NSNotFound else { return nil }

        let safeLocation = max(0, min(selection.location, nsText.length))
        let safeLength = max(0, min(selection.length, nsText.length - safeLocation))
        let safeSelection = NSRange(location: safeLocation, length: safeLength)

        let affectedRange = nsText.lineRange(for: safeSelection)
        let originalText = nsText.substring(with: affectedRange)
        let transformedText = transformedLines(in: originalText, using: lineTransform)
        guard transformedText != originalText else { return nil }

        let updatedText = nsText.replacingCharacters(in: affectedRange, with: transformedText)

        if safeSelection.length == 0 {
            let offsetInLine = safeSelection.location - affectedRange.location
            let transformedOffset = collapsedSelectionTransform(originalText, transformedText, offsetInLine)
            let clampedOffset = max(0, min(transformedOffset, transformedText.utf16.count))
            return TextSelectionTransform(
                text: updatedText,
                selection: NSRange(location: affectedRange.location + clampedOffset, length: 0)
            )
        }

        return TextSelectionTransform(
            text: updatedText,
            selection: NSRange(location: affectedRange.location, length: transformedText.utf16.count)
        )
    }

    private static func transformedLines(in text: String, using lineTransform: (String) -> String) -> String {
        guard !text.isEmpty else { return lineTransform(text) }

        var transformed = ""
        var lineStart = text.startIndex

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let nextIndex = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
            transformed += lineTransform(String(text[lineStart..<nextIndex]))
            lineStart = nextIndex
        }

        return transformed
    }

    private static func removedIndentCount(in line: String) -> Int {
        let (core, _) = splitLineEnding(in: line)

        if core.hasPrefix("\t") {
            return 1
        }

        return min(core.prefix(while: { $0 == " " }).count, 2)
    }

    private static func wrappedStrikethroughRange(containing range: NSRange, in text: NSString) -> NSRange? {
        if range.length >= 4 {
            let selectedText = text.substring(with: range)
            if selectedText.hasPrefix("~~"), selectedText.hasSuffix("~~") {
                return range
            }
        }

        let prefixRange = NSRange(location: range.location - 2, length: 2)
        let suffixRange = NSRange(location: NSMaxRange(range), length: 2)
        guard prefixRange.location >= 0,
              NSMaxRange(suffixRange) <= text.length else {
            return nil
        }

        guard text.substring(with: prefixRange) == "~~",
              text.substring(with: suffixRange) == "~~" else {
            return nil
        }

        return NSRange(location: prefixRange.location, length: range.length + 4)
    }

    private static func wordRange(around location: Int, in text: NSString) -> NSRange? {
        guard text.length > 0 else { return nil }

        var index = max(0, min(location, text.length))
        if !isWordCharacter(at: index, in: text) {
            if index > 0, isWordCharacter(at: index - 1, in: text) {
                index -= 1
            } else {
                return nil
            }
        }

        var start = index
        while start > 0, isWordCharacter(at: start - 1, in: text) {
            start -= 1
        }

        var end = index + 1
        while end < text.length, isWordCharacter(at: end, in: text) {
            end += 1
        }

        return NSRange(location: start, length: end - start)
    }

    private static func isWordCharacter(at index: Int, in text: NSString) -> Bool {
        guard index >= 0, index < text.length else { return false }
        let character = text.substring(with: NSRange(location: index, length: 1))
        return character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }
}
