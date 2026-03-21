import Testing
import Foundation
@testable import NotoVault

// MARK: - Test Index
// testTitleFromFirstLine — Title is the first non-empty line of content
// testTitleStripsHeadingMarkers — Leading # characters are stripped from title
// testTitleUntitledWhenEmpty — Empty content returns "Untitled"
// testTitleUntitledWhenOnlyWhitespace — Whitespace-only content returns "Untitled"
// testTitleUntitledWhenOnlyHashes — Content with only # characters returns "Untitled"
// testDefaultValues — Default init creates a valid note with empty content

@Suite("NoteFile")
struct NoteFileTests {

    @Test func testTitleFromFirstLine() {
        let note = NoteFile(content: "My First Note\nSome body text")
        #expect(note.title == "My First Note")
    }

    @Test func testTitleStripsHeadingMarkers() {
        let note = NoteFile(content: "# My Heading\nBody")
        #expect(note.title == "My Heading")

        let note2 = NoteFile(content: "## Second Level\nBody")
        #expect(note2.title == "Second Level")

        let note3 = NoteFile(content: "### Third Level")
        #expect(note3.title == "Third Level")
    }

    @Test func testTitleUntitledWhenEmpty() {
        let note = NoteFile(content: "")
        #expect(note.title == "Untitled")
    }

    @Test func testTitleUntitledWhenOnlyWhitespace() {
        let note = NoteFile(content: "   \n  \n  ")
        #expect(note.title == "Untitled")
    }

    @Test func testTitleUntitledWhenOnlyHashes() {
        let note = NoteFile(content: "###")
        #expect(note.title == "Untitled")
    }

    @Test func testDefaultValues() {
        let note = NoteFile()
        #expect(note.content == "")
        #expect(note.title == "Untitled")
        #expect(note.id != UUID())
    }
}
