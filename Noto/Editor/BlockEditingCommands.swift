import Foundation

enum BlockLineBreakAction: Equatable {
    case none
    case insert(String)
    case removeCurrentLinePrefix(prefixLength: Int)
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
