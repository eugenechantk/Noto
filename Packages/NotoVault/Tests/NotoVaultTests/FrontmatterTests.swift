import Testing
import Foundation
@testable import NotoVault

// MARK: - Test Index
// testSerializeAndParse — Round-trip: serialize a NoteFile then parse it back
// testParseValidFrontmatter — Parse a well-formed markdown string with frontmatter
// testParseNoFrontmatter — Markdown without frontmatter returns nil metadata and full body
// testParseInvalidUUID — Frontmatter with invalid UUID returns nil metadata
// testParseMissingClosingDashes — Unclosed frontmatter returns nil metadata
// testBodyPreservedExactly — Content after frontmatter is preserved without modification

@Suite("Frontmatter")
struct FrontmatterTests {

    @Test func testSerializeAndParse() {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let modified = Date(timeIntervalSince1970: 1_700_001_000)
        let note = NoteFile(id: id, content: "Hello world\n\nSecond paragraph", createdAt: created, modifiedAt: modified)

        let markdown = Frontmatter.serialize(note)
        let (metadata, body) = Frontmatter.parse(markdown)

        #expect(metadata != nil)
        #expect(metadata?.id == id)
        #expect(body == "Hello world\n\nSecond paragraph")
    }

    @Test func testParseValidFrontmatter() {
        let id = UUID()
        let markdown = """
        ---
        id: \(id.uuidString)
        created: 2026-03-17T09:00:00Z
        modified: 2026-03-17T10:00:00Z
        ---
        Some content here
        """

        let (metadata, body) = Frontmatter.parse(markdown)

        #expect(metadata != nil)
        #expect(metadata?.id == id)
        #expect(body.trimmingCharacters(in: .whitespacesAndNewlines) == "Some content here")
    }

    @Test func testParseNoFrontmatter() {
        let markdown = "Just some text without frontmatter"
        let (metadata, body) = Frontmatter.parse(markdown)

        #expect(metadata == nil)
        #expect(body == markdown)
    }

    @Test func testParseInvalidUUID() {
        let markdown = """
        ---
        id: not-a-uuid
        created: 2026-03-17T09:00:00Z
        modified: 2026-03-17T10:00:00Z
        ---
        Body text
        """

        let (metadata, _) = Frontmatter.parse(markdown)
        #expect(metadata == nil)
    }

    @Test func testParseMissingClosingDashes() {
        let markdown = """
        ---
        id: \(UUID().uuidString)
        created: 2026-03-17T09:00:00Z
        """

        let (metadata, _) = Frontmatter.parse(markdown)
        #expect(metadata == nil)
    }

    @Test func testBodyPreservedExactly() {
        let id = UUID()
        let bodyContent = "# Heading\n\nParagraph one.\n\nParagraph two with **bold**."
        let note = NoteFile(id: id, content: bodyContent, createdAt: Date(), modifiedAt: Date())

        let markdown = Frontmatter.serialize(note)
        let (_, body) = Frontmatter.parse(markdown)

        #expect(body == bodyContent)
    }
}
