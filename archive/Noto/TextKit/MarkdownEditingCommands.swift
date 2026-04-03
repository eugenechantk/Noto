import Foundation

enum MarkdownLineBreakAction: Equatable {
    case none
    case insert(String)
    case removeCurrentLinePrefix(prefixLength: Int)
}

struct MarkdownEditingCommands {
    static func lineBreakAction(for line: String) -> MarkdownLineBreakAction {
        let (core, _) = splitLineEnding(in: line)

        if let todoMatch = TodoMarkdown.match(in: core) {
            let todoPrefix = todoMatch.indentation + "- [ ] "
            let content = todoMatch.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                return .removeCurrentLinePrefix(prefixLength: todoMatch.prefixLength)
            }
            return .insert("\n" + todoPrefix)
        }

        if let bulletPrefix = bulletPrefix(in: core) {
            let content = String(core.dropFirst(bulletPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                return .removeCurrentLinePrefix(prefixLength: bulletPrefix.count)
            }
            return .insert("\n" + bulletPrefix)
        }

        if let orderedListMatch = orderedListMatch(in: core) {
            if orderedListMatch.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .removeCurrentLinePrefix(prefixLength: orderedListMatch.prefixLength)
            }
            return .insert("\n" + orderedListMatch.nextPrefix)
        }

        return .none
    }

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

    private static func bulletPrefix(in line: String) -> String? {
        guard let match = line.range(of: #"^(\s*[*\-•] )"#, options: .regularExpression) else {
            return nil
        }
        return String(line[match])
    }

    private static func orderedListMatch(in line: String) -> (prefixLength: Int, nextPrefix: String, content: String)? {
        guard let match = line.range(of: #"^(\s*)\d+\. "#, options: .regularExpression) else {
            return nil
        }

        let leadingSpaces = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let stripped = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let dotIndex = stripped.firstIndex(of: ".") else {
            return nil
        }

        let numberString = String(stripped[stripped.startIndex..<dotIndex])
        guard let number = Int(numberString) else {
            return nil
        }

        let nextPrefix = "\(leadingSpaces)\(number + 1). "
        let prefixLength = line.distance(from: line.startIndex, to: match.upperBound)
        let content = String(line[match.upperBound...])
        return (prefixLength, nextPrefix, content)
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
}
