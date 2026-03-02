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

        // 1. Bold: **text** → text
        text = text.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "$1",
            options: .regularExpression
        )

        // 2. Italic: *text* → text (single asterisk not preceded/followed by another asterisk)
        text = text.replacingOccurrences(
            of: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#,
            with: "$1",
            options: .regularExpression
        )

        // 3. Strikethrough: ~~text~~ → text
        text = text.replacingOccurrences(
            of: #"~~(.+?)~~"#,
            with: "$1",
            options: .regularExpression
        )

        // 4. Inline code: `text` → text
        text = text.replacingOccurrences(
            of: #"`(.+?)`"#,
            with: "$1",
            options: .regularExpression
        )

        // 5. List prefixes (checked/unchecked checkboxes first, then bullet/dash/ordered)
        //    Handles both `- [x] ` / `- [ ] ` and `[x] ` / `[_] ` (NoteTextStorage format)
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

        // 6. Trim whitespace
        text = text.trimmingCharacters(in: .whitespaces)

        return text
    }
}
