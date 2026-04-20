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

struct TextReplacement: Equatable {
    let range: NSRange
    let replacement: String
}

enum TextEditDiff {
    static func singleReplacement(from oldText: String, to newText: String) -> TextReplacement? {
        guard oldText != newText else { return nil }

        let old = oldText as NSString
        let new = newText as NSString
        let oldLength = old.length
        let newLength = new.length

        var prefixLength = 0
        while prefixLength < oldLength,
              prefixLength < newLength,
              old.character(at: prefixLength) == new.character(at: prefixLength) {
            prefixLength += 1
        }

        var suffixLength = 0
        while suffixLength < oldLength - prefixLength,
              suffixLength < newLength - prefixLength,
              old.character(at: oldLength - suffixLength - 1) == new.character(at: newLength - suffixLength - 1) {
            suffixLength += 1
        }

        let replacedLength = oldLength - prefixLength - suffixLength
        let insertedLength = newLength - prefixLength - suffixLength
        let replacement = new.substring(with: NSRange(location: prefixLength, length: insertedLength))

        return TextReplacement(
            range: NSRange(location: prefixLength, length: replacedLength),
            replacement: replacement
        )
    }
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

    static func continuedListLineBreak(in text: String, selection: NSRange) -> TextSelectionTransform? {
        let nsText = text as NSString
        guard selection.location != NSNotFound, selection.length == 0 else { return nil }

        let safeLocation = max(0, min(selection.location, nsText.length))
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        let lineTextRange = lineTextRange(from: lineRange, in: nsText)
        let lineText = nsText.substring(with: lineTextRange)
        let offsetInLine = max(0, min(safeLocation - lineRange.location, lineTextRange.length))

        let type = Block(text: lineText).blockType
        guard type.isList,
              let prefix = type.prefix,
              let continuationPrefix = type.continuationPrefix else {
            return nil
        }

        let prefixLength = prefix.utf16.count
        guard offsetInLine >= prefixLength else { return nil }

        let content = type.content(of: lineText).trimmingCharacters(in: .whitespaces)
        if content.isEmpty && offsetInLine >= lineTextRange.length {
            let updatedText = nsText.replacingCharacters(
                in: NSRange(location: lineRange.location, length: min(prefixLength, lineTextRange.length)),
                with: ""
            )
            return TextSelectionTransform(
                text: updatedText,
                selection: NSRange(location: lineRange.location, length: 0)
            )
        }

        let insertedText = "\n" + continuationPrefix
        let updatedText = nsText.replacingCharacters(
            in: NSRange(location: safeLocation, length: 0),
            with: insertedText
        )
        return TextSelectionTransform(
            text: updatedText,
            selection: NSRange(location: safeLocation + insertedText.utf16.count, length: 0)
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

    private static func lineTextRange(from lineRange: NSRange, in text: NSString) -> NSRange {
        guard lineRange.length > 0 else { return lineRange }

        let lastCharacterRange = NSRange(location: NSMaxRange(lineRange) - 1, length: 1)
        guard lastCharacterRange.location >= 0,
              NSMaxRange(lastCharacterRange) <= text.length,
              text.substring(with: lastCharacterRange) == "\n" else {
            return lineRange
        }

        return NSRange(location: lineRange.location, length: lineRange.length - 1)
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
