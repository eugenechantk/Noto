//
//  PlainTextExtractor.swift
//  NotoCore
//
//  Strips markdown-like formatting from block content strings.
//  Shared by both keyword (FTS5) and semantic search pipelines.
//

import Foundation

public struct PlainTextExtractor {

    /// Strips markdown formatting markers and list prefixes from a block's content string.
    ///
    /// Processing order matters — bold (`**`) is stripped before italic (`*`) since both use asterisks.
    public static func plainText(from content: String) -> String {
        var text = content

        // 1. Headings: # text → text
        text = text.replacingOccurrences(
            of: #"^#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )

        // 2. Blockquotes: > text → text (supports nested >>> )
        text = text.replacingOccurrences(
            of: #"^(?:>\s*)+"#,
            with: "",
            options: .regularExpression
        )

        // 3. Images: ![alt](url) → alt
        text = text.replacingOccurrences(
            of: #"!\[([^\]]*)\]\([^\)]+\)"#,
            with: "$1",
            options: .regularExpression
        )

        // 4. Links: [text](url) → text
        text = text.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^\)]+\)"#,
            with: "$1",
            options: .regularExpression
        )

        // 5. Bold+italic: ***text*** or ___text___ → text
        text = text.replacingOccurrences(
            of: #"\*{3}(.+?)\*{3}"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"_{3}(.+?)_{3}"#,
            with: "$1",
            options: .regularExpression
        )

        // 6. Bold: **text** or __text__ → text
        text = text.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"__(.+?)__"#,
            with: "$1",
            options: .regularExpression
        )

        // 7. Italic: *text* or _text_ → text
        text = text.replacingOccurrences(
            of: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#,
            with: "$1",
            options: .regularExpression
        )

        // 8. Strikethrough: ~~text~~ → text
        text = text.replacingOccurrences(
            of: #"~~(.+?)~~"#,
            with: "$1",
            options: .regularExpression
        )

        // 9. Inline code: `text` → text
        text = text.replacingOccurrences(
            of: #"`(.+?)`"#,
            with: "$1",
            options: .regularExpression
        )

        // 10. Code fence markers: ``` or ```lang → (remove entire line)
        text = text.replacingOccurrences(
            of: #"^```\w*\s*$"#,
            with: "",
            options: .regularExpression
        )

        // 11. Horizontal rules: ---, ***, ___ (standalone) → empty
        text = text.replacingOccurrences(
            of: #"^[-*_]{3,}\s*$"#,
            with: "",
            options: .regularExpression
        )

        // 12. List prefixes (checked/unchecked checkboxes first, then bullet/dash/ordered)
        //     Handles both `- [x] ` / `- [ ] ` and `[x] ` / `[_] ` (NoteTextStorage format)
        text = text.replacingOccurrences(
            of: #"^- \[[x ]\] "#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"^\[[x_]\] "#,
            with: "",
            options: .regularExpression
        )
        // Bullet: * item
        text = text.replacingOccurrences(
            of: #"^\* "#,
            with: "",
            options: .regularExpression
        )
        // Dash: - item
        text = text.replacingOccurrences(
            of: #"^- "#,
            with: "",
            options: .regularExpression
        )
        // Ordered: 1. item
        text = text.replacingOccurrences(
            of: #"^\d+\. "#,
            with: "",
            options: .regularExpression
        )

        // 13. Trim whitespace
        text = text.trimmingCharacters(in: .whitespaces)

        return text
    }
}
