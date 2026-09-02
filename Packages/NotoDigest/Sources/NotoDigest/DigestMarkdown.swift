import Foundation
import NotoVault

/// The pure text transforms behind the digest's filing actions. Kept separate
/// from the filesystem so the exact shape of what lands on disk — blank lines,
/// heading, trailing newline — is provable without touching a vault.
public enum DigestMarkdown {
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
