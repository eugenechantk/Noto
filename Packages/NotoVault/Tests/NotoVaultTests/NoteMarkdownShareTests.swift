import Foundation
import Testing
@testable import NotoVault

@Suite("Note Markdown text export")
struct NoteMarkdownShareTests {
    @Test("Shares the complete Markdown body while removing template and frontmatter metadata")
    func preservesEntireBodyWithoutMetadata() async throws {
        let body = "# Note\n\n**Bold** and [link](https://example.com)\n- [ ] Task\n```swift\nlet x = 1\n```\n" + String(repeating: "Long note 中文\n", count: 10_000)
        let text = "---\nid: example\ntags: [分享]\ntemplate: private-template\ncreated: 2026-10-23\n---\n" + body
        let actual = try await NoteMarkdownShare(markdown: text).loadText()
        #expect(Array(actual.utf8) == Array(body.utf8))
    }

    @Test("Reads the chosen file at export time instead of sharing its URL or a preview")
    func readsChosenFileLazily() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Chosen.md")
        try "# Old".write(to: url, atomically: true, encoding: .utf8)
        let item = NoteMarkdownShare(fileURL: url)
        try "---\ntemplate: hidden\nid: chosen\n---\n# Chosen\n\n- **Latest**\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(try await item.loadText() == "# Chosen\n\n- **Latest**\n")
    }

    @Test("Missing files fail instead of sharing a blank placeholder")
    func missingFileFails() async {
        let item = NoteMarkdownShare(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        await #expect(throws: (any Error).self) { try await item.loadText() }
    }

    @Test("Ordinary Markdown and horizontal rules inside the body stay unchanged")
    func preservesMarkdownWithoutMetadata() async throws {
        let body = "# Template instructions\n\nKeep this body text.\n\n---\n\n**End**\n"
        #expect(try await NoteMarkdownShare(markdown: body).loadText() == body)
    }

    @Test("Metadata-only notes share an empty body")
    func metadataOnlyNote() async throws {
        #expect(try await NoteMarkdownShare(markdown: "---\ntemplate: private\nid: example\n---\n").loadText() == "")
    }

    @Test("An edited Inbox body preserves leading Markdown rules without adding metadata")
    func preservesEditedInboxBody() async throws {
        let body = "---\n\n**Unsaved 中文**\n\n---\n\n- [ ] Task\n"
        #expect(try await NoteMarkdownShare(body: body).loadText() == body)
    }

    @Test("An intentionally empty document remains empty")
    func emptyDocument() async throws {
        #expect(try await NoteMarkdownShare(markdown: "").loadText() == "")
    }

}
