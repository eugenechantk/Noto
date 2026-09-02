import Foundation
import Testing
@testable import NotoDigest

/// The exact bytes the digest's filing actions produce.
///
/// | Test | Covers |
/// | --- | --- |
/// | `appendsAfterOneBlankLine` | SC3 — capture joins an existing body with exactly one blank line |
/// | `appendsAsFirstParagraphOfEmptyNote` | SC3 — a frontmatter-only note gets the capture as its body |
/// | `appendPreservesFrontmatterAndBodyVerbatim` | SC3 — nothing above the append point is rewritten |
/// | `appendNormalizesRaggedTrailingWhitespace` | SC3 — trailing blank lines don't accumulate |
/// | `appendIgnoresEmptyCapture` | SC3 — an empty capture leaves the target byte-identical |
/// | `newNoteHasFrontmatterHeadingAndBody` | SC4 — created note shape |
/// | `newNoteWithEmptyBodyIsJustAHeading` | SC4 — no trailing blank paragraph |
/// | `filenameSanitizesAndAppendsExtension` | SC4 — reserved characters survive as look-alikes |
/// | `filenameIsNilWhenTitleIsBlankOrUnusable` | SC4 — a title that sanitizes to nothing is rejected |
@Suite("DigestMarkdown — filing text transforms")
struct DigestMarkdownTests {
    private let note = """
    ---
    id: a1b2c3d4-e5f6-7890-abcd-000000000001
    created: 2026-03-15T10:00:00Z
    updated: 2026-03-15T10:00:00Z
    ---
    # Project Alpha

    - existing bullet
    """

    /// The canonical add-to case: one blank line between the old body and the
    /// capture, and a single trailing newline.
    @Test("appending joins the capture after exactly one blank line")
    func appendsAfterOneBlankLine() {
        let out = DigestMarkdown.appending("Remember to email Sam", to: note)
        #expect(out.hasSuffix("- existing bullet\n\nRemember to email Sam\n"))
    }

    /// A note that is only frontmatter has no body to separate from, so the
    /// capture becomes the first paragraph.
    @Test("appending to a frontmatter-only note makes the capture the body")
    func appendsAsFirstParagraphOfEmptyNote() {
        let empty = "---\nid: x\nupdated: 2026-01-01T00:00:00Z\n---\n\n"
        let out = DigestMarkdown.appending("First thought", to: empty)
        #expect(out == "---\nid: x\nupdated: 2026-01-01T00:00:00Z\n---\n\nFirst thought\n")
    }

    /// Everything above the insertion point must come back byte-for-byte —
    /// filing into a note may never rewrite the note.
    @Test("appending preserves the target's frontmatter and existing body verbatim")
    func appendPreservesFrontmatterAndBodyVerbatim() {
        let out = DigestMarkdown.appending("New line", to: note)
        #expect(out.hasPrefix(note))
    }

    /// Repeated filing into the same note must not grow a stack of blank lines.
    @Test("appending collapses ragged trailing whitespace to one blank line")
    func appendNormalizesRaggedTrailingWhitespace() {
        let ragged = note + "\n\n\n   \n"
        let out = DigestMarkdown.appending("Second", to: ragged)
        #expect(out.hasSuffix("- existing bullet\n\nSecond\n"))
        #expect(!out.contains("\n\n\n"))
    }

    /// Nothing to append means nothing changes — no stray newline.
    @Test("appending an empty capture returns the target unchanged")
    func appendIgnoresEmptyCapture() {
        #expect(DigestMarkdown.appending("   \n  ", to: note) == note)
    }

    /// A created note must look like an editor-created note: frontmatter, H1,
    /// blank line, body.
    @Test("newNoteDocument writes frontmatter, an H1 title, then the capture")
    func newNoteHasFrontmatterHeadingAndBody() {
        let id = UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-000000000009")!
        let date = ISO8601DateFormatter().date(from: "2026-06-25T12:00:00Z")!
        let out = DigestMarkdown.newNoteDocument(title: "Email Sam", body: "About the Q3 plan", id: id, date: date)

        #expect(out.hasPrefix("---\n"))
        #expect(out.contains("id: A1B2C3D4-E5F6-7890-ABCD-000000000009"))
        #expect(out.contains("created: 2026-06-25T12:00:00Z"))
        #expect(out.hasSuffix("# Email Sam\n\nAbout the Q3 plan\n"))
    }

    /// A capture that is empty after trimming leaves a bare titled note rather
    /// than a note with a dangling blank paragraph.
    @Test("newNoteDocument with an empty body is just the heading")
    func newNoteWithEmptyBodyIsJustAHeading() {
        let out = DigestMarkdown.newNoteDocument(title: "Placeholder", body: "  ", id: UUID(), date: Date())
        #expect(out.hasSuffix("# Placeholder\n"))
        #expect(!out.hasSuffix("\n\n"))
    }

    /// Slashes and colons are legal in a title but not a filename; the vault's
    /// look-alike substitution keeps the title readable on disk.
    @Test("filename sanitizes reserved characters and adds the .md extension")
    func filenameSanitizesAndAppendsExtension() {
        #expect(DigestMarkdown.filename(forTitle: "Email Sam") == "Email Sam.md")
        let sanitized = DigestMarkdown.filename(forTitle: "Q3: plan/notes")
        #expect(sanitized?.hasSuffix(".md") == true)
        #expect(sanitized?.contains("/") == false)
        #expect(sanitized?.contains(":") == false)
    }

    /// Blank titles, and titles made only of characters that sanitize away, have
    /// no valid filename — the caller must surface `invalidTitle` instead.
    @Test("filename is nil for a blank or unusable title")
    func filenameIsNilWhenTitleIsBlankOrUnusable() {
        #expect(DigestMarkdown.filename(forTitle: "") == nil)
        #expect(DigestMarkdown.filename(forTitle: "   \n ") == nil)
    }
}
