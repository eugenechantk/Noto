import Foundation

struct TodoMarkdown {
    struct Match {
        let indentation: String
        let prefix: String
        let isChecked: Bool
        let content: String

        var prefixLength: Int { indentation.count + prefix.count }
    }

    static func isTodoLine(_ line: String) -> Bool {
        match(in: line) != nil
    }

    static func match(in line: String) -> Match? {
        let (core, _) = splitLineEnding(in: line)
        let indentation = String(core.prefix(while: { $0 == " " || $0 == "\t" }))
        let rest = String(core.dropFirst(indentation.count))

        if rest.hasPrefix("- [ ] ") {
            return Match(indentation: indentation, prefix: "- [ ] ", isChecked: false, content: String(rest.dropFirst(6)))
        }
        if rest == "- [ ]" {
            return Match(indentation: indentation, prefix: "- [ ]", isChecked: false, content: "")
        }
        if rest.hasPrefix("- [x] ") {
            return Match(indentation: indentation, prefix: "- [x] ", isChecked: true, content: String(rest.dropFirst(6)))
        }
        if rest == "- [x]" {
            return Match(indentation: indentation, prefix: "- [x]", isChecked: true, content: "")
        }
        return nil
    }

    static func toolbarToggledLine(_ line: String) -> String {
        let (core, ending) = splitLineEnding(in: line)
        if let match = match(in: core) {
            return match.indentation + match.content + ending
        }

        let indentation = String(core.prefix(while: { $0 == " " || $0 == "\t" }))
        let rest = String(core.dropFirst(indentation.count))
        let content = contentAfterNonTodoPrefix(in: rest)

        return indentation + "- [ ] " + content + ending
    }

    static func toolbarContentStart(in line: String) -> Int {
        let (core, _) = splitLineEnding(in: line)
        if let match = match(in: core) {
            return match.prefixLength
        }

        let indentation = core.prefix(while: { $0 == " " || $0 == "\t" }).count
        let rest = String(core.dropFirst(indentation))
        return indentation + nonTodoPrefixLength(in: rest)
    }

    static func toolbarToggledContentStart(in line: String) -> Int {
        let (core, _) = splitLineEnding(in: line)
        let indentation = core.prefix(while: { $0 == " " || $0 == "\t" }).count

        if match(in: core) != nil {
            return indentation
        }

        return indentation + 6
    }

    static func checkboxToggledLine(_ line: String) -> String {
        let (core, ending) = splitLineEnding(in: line)
        guard let match = match(in: core) else { return line }

        let toggledPrefix = match.isChecked ? "- [ ] " : "- [x] "
        return match.indentation + toggledPrefix + match.content + ending
    }

    private static func contentAfterNonTodoPrefix(in line: String) -> String {
        let prefixLength = nonTodoPrefixLength(in: line)
        guard prefixLength > 0 else { return line }
        return String(line.dropFirst(prefixLength))
    }

    private static func nonTodoPrefixLength(in line: String) -> Int {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            return 2
        }

        var digits = ""
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }

        if !digits.isEmpty, index < line.endIndex, line[index] == "." {
            let afterDot = line.index(after: index)
            if afterDot < line.endIndex, line[afterDot] == " " {
                return digits.count + 2
            }
        }

        return 0
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
