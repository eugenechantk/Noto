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

private struct StrikethroughLineTarget {
    let range: NSRange
    let wrappedRange: NSRange?
}

enum MarkdownImageInsertion {
    static func transform(in text: String, selection: NSRange, markdown: String) -> TextSelectionTransform {
        let nsText = text as NSString
        let safeLocation = max(0, min(selection.location, nsText.length))
        let safeLength = max(0, min(selection.length, nsText.length - safeLocation))
        let replacementRange = NSRange(location: safeLocation, length: safeLength)

        let needsLeadingNewline = safeLocation > 0 && nsText.character(at: safeLocation - 1) != 10
        let replacementEnd = safeLocation + safeLength
        let needsTrailingNewline = replacementEnd < nsText.length && nsText.character(at: replacementEnd) != 10

        let insertion = "\(needsLeadingNewline ? "\n" : "")\(markdown)\(needsTrailingNewline ? "\n" : "\n")"
        let updatedText = nsText.replacingCharacters(in: replacementRange, with: insertion)
        return TextSelectionTransform(
            text: updatedText,
            selection: NSRange(location: safeLocation + (insertion as NSString).length, length: 0)
        )
    }
}

struct HyperlinkMarkdown {
    enum Target: Equatable {
        case external(URL)
        case vaultDocument(relativePath: String)

        var linkAttributeURL: URL? {
            switch self {
            case .external(let url):
                return url
            case .vaultDocument(let relativePath):
                var components = URLComponents()
                components.scheme = "noto-document"
                components.host = "open"
                components.queryItems = [URLQueryItem(name: "path", value: relativePath)]
                return components.url
            }
        }
    }

    struct Match: Equatable {
        let fullRange: NSRange
        let titleRange: NSRange
        let urlRange: NSRange
        let title: String
        let urlText: String

        var url: URL? {
            target?.linkAttributeURL
        }

        var target: Target? {
            HyperlinkMarkdown.target(from: urlText)
        }
    }

    private static let regex = try! NSRegularExpression(
        pattern: #"(?<!!)\[([^\]\n]+)\]\(([^)\n]+)\)"#
    )

    static func matches(in text: String) -> [Match] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: fullRange).compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }

            let titleRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            guard titleRange.location != NSNotFound,
                  urlRange.location != NSNotFound,
                  NSMaxRange(titleRange) <= nsText.length,
                  NSMaxRange(urlRange) <= nsText.length else {
                return nil
            }

            let urlText = nsText.substring(with: urlRange)
            guard target(from: urlText) != nil else { return nil }

            return Match(
                fullRange: match.range,
                titleRange: titleRange,
                urlRange: urlRange,
                title: nsText.substring(with: titleRange),
                urlText: urlText
            )
        }
    }

    static func url(at location: Int, in text: String) -> URL? {
        target(at: location, in: text)?.linkAttributeURL
    }

    static func target(at location: Int, in text: String) -> Target? {
        match(at: location, in: text)?.target
    }

    static func match(at location: Int, in text: String) -> Match? {
        matches(in: text).first { match in
            NSLocationInRange(location, match.titleRange)
        }
    }

    static func matchForToggle(selection: NSRange, in text: NSString) -> Match? {
        matches(in: text as String).first { match in
            if NSEqualRanges(selection, match.fullRange) {
                return true
            }

            if selection.length == 0 {
                return NSLocationInRange(selection.location, match.titleRange)
            }

            return selection.location >= match.titleRange.location &&
                NSMaxRange(selection) <= NSMaxRange(match.titleRange)
        }
    }

    static func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        guard trimmed.contains("."),
              !trimmed.contains("["),
              !trimmed.contains("]"),
              !trimmed.contains("("),
              !trimmed.contains(")") else {
            return nil
        }

        return URL(string: "https://\(trimmed)")
    }

    static func target(from rawValue: String) -> Target? {
        if let relativePath = normalizedVaultRelativePath(from: rawValue) {
            return .vaultDocument(relativePath: relativePath)
        }

        if let url = normalizedURL(from: rawValue) {
            return .external(url)
        }

        return nil
    }

    static func normalizedVaultRelativePath(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let unwrapped: String
        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">"), trimmed.count > 2 {
            unwrapped = String(trimmed.dropFirst().dropLast())
        } else {
            unwrapped = trimmed
        }

        guard !unwrapped.hasPrefix("/"),
              !unwrapped.hasPrefix("~"),
              !unwrapped.contains("\n"),
              unwrapped.rangeOfCharacter(from: CharacterSet(charactersIn: "[]")) == nil,
              URL(string: unwrapped)?.scheme == nil,
              unwrapped.lowercased().hasSuffix(".md") else {
            return nil
        }

        let decoded = unwrapped.removingPercentEncoding ?? unwrapped
        let components = decoded.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }

        return decoded
    }

    static func urlRange(around location: Int, in text: NSString) -> NSRange? {
        guard text.length > 0 else { return nil }

        var index = max(0, min(location, text.length))
        if !isURLCharacter(at: index, in: text) {
            if index > 0, isURLCharacter(at: index - 1, in: text) {
                index -= 1
            } else {
                return nil
            }
        }

        var start = index
        while start > 0, isURLCharacter(at: start - 1, in: text) {
            start -= 1
        }

        var end = index + 1
        while end < text.length, isURLCharacter(at: end, in: text) {
            end += 1
        }

        let range = NSRange(location: start, length: end - start)
        let candidate = text.substring(with: range)
        return normalizedURL(from: candidate) == nil ? nil : range
    }

    private static func isURLCharacter(at index: Int, in text: NSString) -> Bool {
        guard index >= 0, index < text.length else { return false }
        let character = text.substring(with: NSRange(location: index, length: 1))
        guard let scalar = character.unicodeScalars.first else { return false }

        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return false
        }

        return character.rangeOfCharacter(from: CharacterSet(charactersIn: "[]<>\"")) == nil
    }
}

struct PageMentionQuery: Equatable {
    let range: NSRange
    let query: String
}

enum PageMentionMarkdown {
    static func activeQuery(in text: String, selection: NSRange) -> PageMentionQuery? {
        activeQuery(in: text as NSString, selection: selection)
    }

    static func activeQuery(in nsText: NSString, selection: NSRange) -> PageMentionQuery? {
        guard selection.location != NSNotFound, selection.length == 0 else { return nil }

        let cursor = max(0, min(selection.location, nsText.length))
        let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
        guard cursor >= lineRange.location else { return nil }

        var mentionLocation: Int?
        var index = cursor - 1
        while index >= lineRange.location {
            let character = nsText.substring(with: NSRange(location: index, length: 1))
            if character == "@" {
                mentionLocation = index
                break
            }
            index -= 1
        }

        guard let mentionLocation,
              isValidMentionBoundary(before: mentionLocation, in: nsText) else {
            return nil
        }

        let queryRange = NSRange(location: mentionLocation + 1, length: cursor - mentionLocation - 1)
        let query = nsText.substring(with: queryRange)
        guard query.utf16.count <= 80,
              query.rangeOfCharacter(from: CharacterSet(charactersIn: "@[]()")) == nil else {
            return nil
        }

        return PageMentionQuery(
            range: NSRange(location: mentionLocation, length: cursor - mentionLocation),
            query: query
        )
    }

    static func markdownLink(for document: PageMentionDocument) -> String {
        "[\(document.title)](\(escapedRelativePath(document.relativePath)))"
    }

    private static func escapedRelativePath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }

    private static func isValidMentionBoundary(before mentionLocation: Int, in text: NSString) -> Bool {
        guard mentionLocation > 0 else { return true }
        let previous = text.substring(with: NSRange(location: mentionLocation - 1, length: 1))
        guard let scalar = previous.unicodeScalars.first else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar) ||
            CharacterSet(charactersIn: "([{\"'").contains(scalar)
    }
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
        .map(normalizedOrderedListNumbering)
    }

    static func outdentedLines(in text: String, selection: NSRange) -> TextSelectionTransform? {
        transformedSelectedLines(in: text, selection: selection, lineTransform: outdentedLine) { originalLine, _, offset in
            max(0, offset - removedIndentCount(in: originalLine))
        }
        .map(normalizedOrderedListNumbering)
    }

    static func toggledTodoLines(in text: String, selection: NSRange) -> TextSelectionTransform? {
        transformedSelectedLines(in: text, selection: selection, lineTransform: TodoMarkdown.toolbarToggledLine) { originalLine, transformedLine, offset in
            let wasTodoLine = TodoMarkdown.match(in: originalLine) != nil
            let originalContentStart = TodoMarkdown.toolbarContentStart(in: originalLine)
            let transformedContentStart = TodoMarkdown.toolbarToggledContentStart(in: originalLine)

            if offset <= originalContentStart {
                return wasTodoLine ? min(offset, transformedContentStart) : transformedContentStart
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

        if safeSelection.length > 0,
           nsText.substring(with: safeSelection).contains(where: { $0.isNewline }) {
            return toggledMultilineStrikethrough(in: text, selection: safeSelection)
        }

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

    private static func toggledMultilineStrikethrough(
        in text: String,
        selection safeSelection: NSRange
    ) -> TextSelectionTransform? {
        let nsText = text as NSString
        let targets = strikethroughLineTargets(in: nsText, selection: safeSelection)
        guard !targets.isEmpty else { return nil }

        let allTargetsWrapped = targets.allSatisfy { $0.wrappedRange != nil }
        if allTargetsWrapped {
            return applyStrikethroughLineEdits(
                in: text,
                affectedRange: nsText.lineRange(for: safeSelection),
                edits: targets.compactMap { target in
                    guard let wrappedRange = target.wrappedRange else { return nil }
                    let wrappedText = nsText.substring(with: wrappedRange)
                    return TextReplacement(
                        range: wrappedRange,
                        replacement: String(wrappedText.dropFirst(2).dropLast(2))
                    )
                }
            )
        }

        if let wrappedRange = multilineWrapperRange(containing: safeSelection, in: nsText) {
            let wrappedText = nsText.substring(with: wrappedRange)
            let unwrappedText = String(wrappedText.dropFirst(2).dropLast(2))
            let updatedText = nsText.replacingCharacters(in: wrappedRange, with: unwrappedText)
            return TextSelectionTransform(
                text: updatedText,
                selection: NSRange(location: wrappedRange.location, length: unwrappedText.utf16.count)
            )
        }

        return applyStrikethroughLineEdits(
            in: text,
            affectedRange: nsText.lineRange(for: safeSelection),
            edits: targets.compactMap { target in
                guard target.wrappedRange == nil else { return nil }
                let selectedLineText = nsText.substring(with: target.range)
                return TextReplacement(
                    range: target.range,
                    replacement: "~~\(selectedLineText)~~"
                )
            }
        )
    }

    static func toggledBold(in text: String, selection: NSRange) -> TextSelectionTransform? {
        toggledInlineMarker("**", in: text, selection: selection)
    }

    static func toggledItalic(in text: String, selection: NSRange) -> TextSelectionTransform? {
        toggledInlineMarker("*", in: text, selection: selection)
    }

    static func toggledHyperlink(in text: String, selection: NSRange) -> TextSelectionTransform? {
        let nsText = text as NSString
        guard selection.location != NSNotFound else { return nil }

        let safeLocation = max(0, min(selection.location, nsText.length))
        let safeLength = max(0, min(selection.length, nsText.length - safeLocation))
        let safeSelection = NSRange(location: safeLocation, length: safeLength)

        if let match = HyperlinkMarkdown.matchForToggle(selection: safeSelection, in: nsText) {
            let updatedText = nsText.replacingCharacters(in: match.fullRange, with: match.title)
            return TextSelectionTransform(
                text: updatedText,
                selection: NSRange(location: match.fullRange.location, length: match.title.utf16.count)
            )
        }

        let targetRange: NSRange
        if safeSelection.length > 0 {
            targetRange = safeSelection
        } else if let urlRange = HyperlinkMarkdown.urlRange(around: safeSelection.location, in: nsText) {
            targetRange = urlRange
        } else {
            return nil
        }

        let selectedText = nsText.substring(with: targetRange)
        guard HyperlinkMarkdown.normalizedURL(from: selectedText) != nil,
              selectedText.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }

        let linkMarkdown = "[\(selectedText)](\(selectedText))"
        let updatedText = nsText.replacingCharacters(in: targetRange, with: linkMarkdown)
        return TextSelectionTransform(
            text: updatedText,
            selection: NSRange(location: targetRange.location + 1, length: selectedText.utf16.count)
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

    private struct TextLengthChange {
        let range: NSRange
        let replacementLength: Int

        var delta: Int {
            replacementLength - range.length
        }
    }

    private static func normalizedOrderedListNumbering(_ transform: TextSelectionTransform) -> TextSelectionTransform {
        let result = orderedListNumberingNormalizedText(transform.text)
        guard result.text != transform.text else { return transform }

        let start = adjustedLocation(transform.selection.location, changes: result.changes)
        let end = adjustedLocation(NSMaxRange(transform.selection), changes: result.changes)
        return TextSelectionTransform(
            text: result.text,
            selection: NSRange(location: start, length: max(0, end - start))
        )
    }

    private static func orderedListNumberingNormalizedText(_ text: String) -> (text: String, changes: [TextLengthChange]) {
        let nsText = text as NSString
        guard nsText.length > 0 else { return (text, []) }

        var counters: [Int: Int] = [:]
        var output = ""
        var changes: [TextLengthChange] = []
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let lineTextRange = lineTextRange(from: lineRange, in: nsText)
            let lineText = nsText.substring(with: lineTextRange)
            let lineEndingRange = NSRange(
                location: NSMaxRange(lineTextRange),
                length: NSMaxRange(lineRange) - NSMaxRange(lineTextRange)
            )
            let lineEnding = nsText.substring(with: lineEndingRange)

            if let marker = orderedListMarker(in: lineText) {
                counters = counters.filter { $0.key <= marker.indent }
                let nextNumber = (counters[marker.indent] ?? 0) + 1
                counters[marker.indent] = nextNumber

                let nextNumberText = "\(nextNumber)"
                let nsLineText = lineText as NSString
                output += nsLineText.replacingCharacters(in: marker.numberRange, with: nextNumberText)
                output += lineEnding

                if nsLineText.substring(with: marker.numberRange) != nextNumberText {
                    changes.append(TextLengthChange(
                        range: NSRange(
                            location: lineTextRange.location + marker.numberRange.location,
                            length: marker.numberRange.length
                        ),
                        replacementLength: nextNumberText.utf16.count
                    ))
                }
            } else {
                if let indent = markdownListIndent(in: lineText) {
                    counters = counters.filter { $0.key <= indent }
                } else if !lineText.trimmingCharacters(in: .whitespaces).isEmpty {
                    counters.removeAll()
                }
                output += lineText
                output += lineEnding
            }

            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return (output, changes)
    }

    private static func adjustedLocation(_ location: Int, changes: [TextLengthChange]) -> Int {
        var adjusted = location
        for change in changes {
            if adjusted <= change.range.location {
                break
            }

            if adjusted <= NSMaxRange(change.range) {
                adjusted = change.range.location + change.replacementLength
            } else {
                adjusted += change.delta
            }
        }
        return max(0, adjusted)
    }

    private static func orderedListMarker(in line: String) -> (indent: Int, numberRange: NSRange)? {
        let nsLine = line as NSString
        guard nsLine.length > 0 else { return nil }

        var index = 0
        while index < nsLine.length, nsLine.substring(with: NSRange(location: index, length: 1)) == " " {
            index += 1
        }

        let numberStart = index
        while index < nsLine.length,
              isDecimalDigit(nsLine.substring(with: NSRange(location: index, length: 1))) {
            index += 1
        }

        guard index > numberStart,
              index + 1 < nsLine.length,
              nsLine.substring(with: NSRange(location: index, length: 1)) == ".",
              nsLine.substring(with: NSRange(location: index + 1, length: 1)) == " " else {
            return nil
        }

        return (
            indent: numberStart / 2,
            numberRange: NSRange(location: numberStart, length: index - numberStart)
        )
    }

    private static func isDecimalDigit(_ character: String) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return CharacterSet.decimalDigits.contains(scalar)
    }

    private static func markdownListIndent(in line: String) -> Int? {
        if let marker = orderedListMarker(in: line) {
            return marker.indent
        }

        let nsLine = line as NSString
        guard nsLine.length >= 2 else { return nil }

        var index = 0
        while index < nsLine.length, nsLine.substring(with: NSRange(location: index, length: 1)) == " " {
            index += 1
        }

        guard index + 1 < nsLine.length else { return nil }
        let marker = nsLine.substring(with: NSRange(location: index, length: 1))
        let next = nsLine.substring(with: NSRange(location: index + 1, length: 1))
        guard ["-", "*", "•"].contains(marker), next == " " else { return nil }

        return index / 2
    }

    private static func strikethroughLineTargets(
        in text: NSString,
        selection: NSRange
    ) -> [StrikethroughLineTarget] {
        let affectedRange = text.lineRange(for: selection)
        let affectedEnd = NSMaxRange(affectedRange)
        var targets: [StrikethroughLineTarget] = []
        var location = affectedRange.location

        while location < affectedEnd {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let lineTextRange = lineTextRange(from: lineRange, in: text)
            let targetRange = NSIntersectionRange(lineTextRange, selection)

            if targetRange.length > 0 {
                let targetText = text.substring(with: targetRange)
                if targetText.contains(where: { !$0.isWhitespace && !$0.isNewline }) {
                    let wrappedRange = wrappedStrikethroughRange(containing: targetRange, in: text)
                    targets.append(StrikethroughLineTarget(range: targetRange, wrappedRange: wrappedRange))
                }
            }

            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return targets
    }

    private static func multilineWrapperRange(containing range: NSRange, in text: NSString) -> NSRange? {
        guard let wrappedRange = wrappedStrikethroughRange(containing: range, in: text) else { return nil }
        let wrappedText = text.substring(with: wrappedRange)
        guard wrappedText.contains(where: { $0.isNewline }) else { return nil }
        return wrappedRange
    }

    private static func applyStrikethroughLineEdits(
        in text: String,
        affectedRange: NSRange,
        edits: [TextReplacement]
    ) -> TextSelectionTransform? {
        guard !edits.isEmpty else { return nil }

        let updatedText = NSMutableString(string: text)
        var lengthDelta = 0

        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            updatedText.replaceCharacters(in: edit.range, with: edit.replacement)
            lengthDelta += edit.replacement.utf16.count - edit.range.length
        }

        return TextSelectionTransform(
            text: updatedText as String,
            selection: NSRange(location: affectedRange.location, length: max(0, affectedRange.length + lengthDelta))
        )
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

    private static func toggledInlineMarker(
        _ marker: String,
        in text: String,
        selection: NSRange
    ) -> TextSelectionTransform? {
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

        if let wrappedRange = wrappedInlineMarkerRange(containing: targetRange, marker: marker, in: nsText) {
            let wrappedText = nsText.substring(with: wrappedRange)
            let markerLength = marker.utf16.count
            let unwrappedText = String(wrappedText.dropFirst(markerLength).dropLast(markerLength))
            let updatedText = nsText.replacingCharacters(in: wrappedRange, with: unwrappedText)
            return TextSelectionTransform(
                text: updatedText,
                selection: NSRange(location: wrappedRange.location, length: unwrappedText.utf16.count)
            )
        }

        let updatedText = NSMutableString(string: text)
        updatedText.insert(marker, at: NSMaxRange(targetRange))
        updatedText.insert(marker, at: targetRange.location)
        return TextSelectionTransform(
            text: updatedText as String,
            selection: NSRange(location: targetRange.location + marker.utf16.count, length: targetRange.length)
        )
    }

    private static func wrappedInlineMarkerRange(
        containing range: NSRange,
        marker: String,
        in text: NSString
    ) -> NSRange? {
        let markerLength = marker.utf16.count

        if range.length >= markerLength * 2 {
            let selectedText = text.substring(with: range)
            if selectedText.hasPrefix(marker),
               selectedText.hasSuffix(marker),
               isStandaloneMarkerRange(
                NSRange(location: range.location, length: markerLength),
                marker: marker,
                in: text
               ),
               isStandaloneMarkerRange(
                NSRange(location: NSMaxRange(range) - markerLength, length: markerLength),
                marker: marker,
                in: text
               ) {
                return range
            }
        }

        let prefixRange = NSRange(location: range.location - markerLength, length: markerLength)
        let suffixRange = NSRange(location: NSMaxRange(range), length: markerLength)
        guard prefixRange.location >= 0,
              NSMaxRange(suffixRange) <= text.length else {
            return nil
        }

        guard text.substring(with: prefixRange) == marker,
              text.substring(with: suffixRange) == marker,
              isStandaloneMarkerRange(prefixRange, marker: marker, in: text),
              isStandaloneMarkerRange(suffixRange, marker: marker, in: text) else {
            return nil
        }

        return NSRange(location: prefixRange.location, length: range.length + markerLength * 2)
    }

    private static func isStandaloneMarkerRange(_ range: NSRange, marker: String, in text: NSString) -> Bool {
        guard marker == "*" else { return true }

        let beforeLocation = range.location - 1
        if beforeLocation >= 0,
           text.substring(with: NSRange(location: beforeLocation, length: 1)) == marker {
            return false
        }

        let afterLocation = NSMaxRange(range)
        if afterLocation < text.length,
           text.substring(with: NSRange(location: afterLocation, length: 1)) == marker {
            return false
        }

        return true
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
