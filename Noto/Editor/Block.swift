import Foundation

// MARK: - Block

/// A single block in the document. The text contains the full markdown line
/// including any prefix (e.g., `## `, `- [ ] `, `- `). The block type is
/// derived from the prefix — editing the prefix changes the type.
struct Block: Identifiable, Equatable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }

    /// The semantic type of this block, derived from its text prefix.
    var blockType: BlockType {
        BlockType.detect(from: text)
    }
}

// MARK: - BlockType

enum BlockType: Equatable {
    case paragraph
    case heading(level: Int)
    case todo(checked: Bool, indent: Int)
    case bullet(indent: Int)
    case orderedList(number: Int, indent: Int)
    case frontmatter

    /// Detect block type from the text content.
    static func detect(from text: String) -> BlockType {
        // Frontmatter is handled at parse time, not by prefix detection
        if text.hasPrefix("---") && text.contains("\n") { return .frontmatter }

        let indentCount = text.prefix(while: { $0 == " " }).count
        let indent = indentCount / 2
        let stripped = String(text.dropFirst(indentCount))

        // Todo: - [ ] or - [x]
        if stripped.hasPrefix("- [ ] ") || stripped == "- [ ]" {
            return .todo(checked: false, indent: indent)
        }
        if stripped.hasPrefix("- [x] ") || stripped == "- [x]" {
            return .todo(checked: true, indent: indent)
        }

        // Headings (only at indent 0)
        if indent == 0 {
            if stripped.hasPrefix("### ") { return .heading(level: 3) }
            if stripped.hasPrefix("## ") { return .heading(level: 2) }
            if stripped.hasPrefix("# ") { return .heading(level: 1) }
        }

        // Bullet: - or * or •
        if stripped.hasPrefix("- ") || stripped.hasPrefix("* ") || stripped.hasPrefix("• ") {
            return .bullet(indent: indent)
        }

        // Ordered list: digits + ". "
        if let dotIndex = stripped.firstIndex(of: "."),
           dotIndex > stripped.startIndex,
           stripped[stripped.startIndex..<dotIndex].allSatisfy(\.isNumber) {
            let afterDot = stripped.index(after: dotIndex)
            if afterDot < stripped.endIndex && stripped[afterDot] == " " {
                let number = Int(stripped[stripped.startIndex..<dotIndex]) ?? 1
                return .orderedList(number: number, indent: indent)
            }
        }

        return .paragraph
    }

    /// The prefix string for this block type (used for auto-continue).
    var prefix: String? {
        switch self {
        case .paragraph, .frontmatter: return nil
        case .heading(let level): return String(repeating: "#", count: level) + " "
        case .todo(_, let indent): return String(repeating: " ", count: indent * 2) + "- [ ] "
        case .bullet(let indent): return String(repeating: " ", count: indent * 2) + "- "
        case .orderedList(let number, let indent): return String(repeating: " ", count: indent * 2) + "\(number). "
        }
    }

    /// The next prefix to use when auto-continuing (Enter at end of block).
    var continuationPrefix: String? {
        switch self {
        case .paragraph, .heading, .frontmatter: return nil
        case .todo(_, let indent): return String(repeating: " ", count: indent * 2) + "- [ ] "
        case .bullet(let indent): return String(repeating: " ", count: indent * 2) + "- "
        case .orderedList(let number, let indent): return String(repeating: " ", count: indent * 2) + "\(number + 1). "
        }
    }

    /// Whether this is a list type that supports auto-continue.
    var isList: Bool {
        switch self {
        case .todo, .bullet, .orderedList: return true
        default: return false
        }
    }

    /// The content portion of the block text (after the prefix).
    func content(of text: String) -> String {
        guard let pfx = prefix else { return text }
        let indentCount = text.prefix(while: { $0 == " " }).count
        let stripped = String(text.dropFirst(indentCount))
        // Find where the prefix pattern ends
        guard stripped.hasPrefix(String(pfx.drop(while: { $0 == " " }))) else { return text }
        let prefixLength = pfx.count
        guard text.count >= prefixLength else { return "" }
        return String(text.dropFirst(prefixLength))
    }
}

// MARK: - BlockParser

struct BlockParser {
    /// Parse a markdown string into blocks.
    /// Frontmatter (--- ... ---) is kept as a single block.
    static func parse(_ markdown: String) -> [Block] {
        guard !markdown.isEmpty else { return [Block(text: "")] }

        var blocks: [Block] = []
        var remaining = markdown

        // Extract frontmatter if present
        if remaining.hasPrefix("---\n") || remaining.hasPrefix("---\r\n") {
            let searchStart = remaining.index(remaining.startIndex, offsetBy: 4)
            if let closeRange = remaining.range(of: "\n---", range: searchStart..<remaining.endIndex) {
                let fmEnd = closeRange.upperBound
                let frontmatter = String(remaining[remaining.startIndex..<fmEnd])
                blocks.append(Block(text: frontmatter))

                // Skip the \n after frontmatter close
                if fmEnd < remaining.endIndex && remaining[fmEnd] == "\n" {
                    remaining = String(remaining[remaining.index(after: fmEnd)...])
                } else {
                    remaining = String(remaining[fmEnd...])
                }
            }
        }

        // Split remaining content by newlines
        if !remaining.isEmpty {
            let lines = remaining.split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines {
                blocks.append(Block(text: String(line)))
            }
        }

        return blocks.isEmpty ? [Block(text: "")] : blocks
    }
}

// MARK: - BlockSerializer

struct BlockSerializer {
    /// Serialize blocks back to a markdown string.
    static func serialize(_ blocks: [Block]) -> String {
        guard !blocks.isEmpty else { return "" }

        var parts: [String] = []
        for (i, block) in blocks.enumerated() {
            if block.blockType == .frontmatter {
                parts.append(block.text)
            } else {
                parts.append(block.text)
            }
            // Don't add trailing newline after last block
            if i < blocks.count - 1 && block.blockType != .frontmatter {
                // newline is added by join
            } else if block.blockType == .frontmatter && i < blocks.count - 1 {
                // frontmatter already ends without \n, join adds it
            }
        }

        // Frontmatter block is joined differently — it already contains \n internally
        if let first = blocks.first, first.blockType == .frontmatter {
            let fm = first.text
            let rest = blocks.dropFirst().map(\.text).joined(separator: "\n")
            if rest.isEmpty { return fm }
            return fm + "\n" + rest
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - BlockDocument

/// The document model: an array of blocks with operations for editing.
struct BlockDocument {
    var blocks: [Block]

    /// Split a block at the given text offset (Enter key).
    /// Returns the index of the new block (where cursor should go).
    @discardableResult
    mutating func split(blockIndex: Int, atOffset offset: Int) -> Int {
        guard blockIndex >= 0, blockIndex < blocks.count else { return blockIndex }
        let block = blocks[blockIndex]
        let text = block.text
        let type = block.blockType

        // If this is a list type with empty content, remove the prefix instead of splitting
        if type.isList {
            let content = type.content(of: text).trimmingCharacters(in: .whitespaces)
            if content.isEmpty && offset >= text.count {
                blocks[blockIndex] = Block(id: block.id, text: "")
                return blockIndex
            }
        }

        // Split the text
        let splitIndex = text.index(text.startIndex, offsetBy: min(offset, text.count))
        let beforeText = String(text[text.startIndex..<splitIndex])
        var afterText = String(text[splitIndex...])

        // Auto-continue: if splitting a list at the end, add prefix to new block
        if type.isList && offset >= text.count {
            afterText = type.continuationPrefix ?? ""
        } else if type.isList && offset > 0 {
            // Splitting in the middle of a list item — new block gets the continuation prefix + remaining text
            if let contPrefix = type.continuationPrefix {
                // Only add prefix if splitting after the prefix area
                if let pfx = type.prefix, offset >= pfx.count {
                    afterText = contPrefix + afterText
                }
            }
        }

        blocks[blockIndex] = Block(id: block.id, text: beforeText)
        let newBlock = Block(text: afterText)
        blocks.insert(newBlock, at: blockIndex + 1)
        return blockIndex + 1
    }

    /// Merge a block with the previous one (Backspace at start).
    /// Returns the cursor offset in the merged block (where the join point is),
    /// or nil if the merge was a no-op.
    @discardableResult
    mutating func mergeWithPrevious(blockIndex: Int) -> Int? {
        guard blockIndex > 0, blockIndex < blocks.count else { return nil }

        let previous = blocks[blockIndex - 1]
        let current = blocks[blockIndex]

        // Don't merge into frontmatter
        if previous.blockType == .frontmatter { return nil }

        let cursorOffset = previous.text.count
        let mergedText = previous.text + current.text
        blocks[blockIndex - 1] = Block(id: previous.id, text: mergedText)
        blocks.remove(at: blockIndex)
        return cursorOffset
    }
}
