import Foundation
import NotoVault

/// The pure text transforms behind the digest's filing actions. Kept separate
/// from the filesystem so the exact shape of what lands on disk — blank lines,
/// heading, trailing newline — is provable without touching a vault.
public enum DigestMarkdown {
    /// A single-line preview from a plain-text search snippet. The note title
    /// already has its own row, so remove only an exact leading title line.
    /// Title words inside a body sentence and later title lines stay intact.
    public static func contentSnippet(_ snippet: String, title: String) -> String {
        var lines = snippet.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let first = lines.first, first.localizedCaseInsensitiveCompare(title) == .orderedSame {
            lines.removeFirst()
        }
        return lines.joined(separator: " ")
    }

    /// Appends `body` to the end of an existing note document.
    ///
    /// The document's frontmatter and existing body are preserved verbatim; the
    /// capture is separated from whatever came before by exactly one blank line
    /// and the result ends in a single newline. A document that is *only*
    /// frontmatter gets the capture as its first body paragraph.
    public static func appending(_ body: String, to document: String) -> String {
        let capture = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !capture.isEmpty else { return document }

        let trimmedDocument = trimmingTrailingNewlines(document)
        guard !trimmedDocument.isEmpty else { return capture + "\n" }
        return trimmedDocument + "\n\n" + capture + "\n"
    }

    /// A complete new note: vault-standard frontmatter, an H1 of `title`, then
    /// the capture body. Matches what `NoteRepository.createNote` writes, so a
    /// digest-created note is indistinguishable from an editor-created one.
    public static func newNoteDocument(title: String, body: String, id: UUID, date: Date) -> String {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let capture = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let frontmatter = VaultMarkdown.makeFrontmatter(id: id, createdAt: date)
        guard !capture.isEmpty else { return frontmatter + "# \(heading)\n" }
        return frontmatter + "# \(heading)\n\n" + capture + "\n"
    }

    /// A new note that keeps the capture exactly as written: frontmatter, then
    /// the Markdown with no heading added. The note is named from its first
    /// line instead (`noteTitle(fromFirstLineOf:)`), so a title never has to be
    /// typed or injected.
    public static func newNoteDocument(body: String, id: UUID, date: Date) -> String {
        let capture = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let frontmatter = VaultMarkdown.makeFrontmatter(id: id, createdAt: date)
        guard !capture.isEmpty else { return frontmatter }
        return frontmatter + capture + "\n"
    }

    /// The longest title a first line may give a filename.
    public static let maxFirstLineTitleLength = 80

    /// The note's name, taken from its first non-blank line whatever its
    /// Markdown: heading, list, todo and quote markers, emphasis, inline code
    /// and link syntax are dropped, and only the visible text is kept. Long
    /// lines are cut at a word boundary. `nil` when there is no text.
    public static func noteTitle(fromFirstLineOf body: String) -> String? {
        guard let line = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else { return nil }

        var text = line
        let leadingMarkers = [
            #"^#{1,6}\s*"#,                 // heading
            #"^>\s*"#,                      // quote
            #"^[-*+]\s+\[[ xX]\]\s*"#,     // todo
            #"^[-*+]\s+"#,                   // bullet
            #"^\d+[.)]\s+"#,                // numbered
        ]
        for pattern in leadingMarkers {
            if let range = text.range(of: pattern, options: .regularExpression) {
                text.removeSubrange(range)
            }
        }
        text = text.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for marker in ["**", "__", "~~", "`"] {
            text = text.replacingOccurrences(of: marker, with: "")
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if [ "-", "*", "+", "#" ].contains(text) { text = "" }
        guard !text.isEmpty else { return nil }

        guard text.count > maxFirstLineTitleLength else { return text }
        let capped = String(text.prefix(maxFirstLineTitleLength))
        if let lastSpace = capped.lastIndex(of: " ") {
            let cut = String(capped[..<lastSpace]).trimmingCharacters(in: .whitespaces)
            if !cut.isEmpty { return cut }
        }
        return capped.trimmingCharacters(in: .whitespaces)
    }

    /// The filename a note titled `title` should get, or `nil` when the title is
    /// blank or sanitizes away to nothing (a note called `///` cannot be filed).
    public static func filename(forTitle title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let sanitized = VaultMarkdown.sanitizeFilename(trimmed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return nil }
        return sanitized + ".md"
    }

    private static func trimmingTrailingNewlines(_ text: String) -> String {
        var result = text
        while let last = result.last, last == "\n" || last == "\r" || last == " " || last == "\t" {
            result.removeLast()
        }
        return result
    }
}
