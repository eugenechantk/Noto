import Foundation
import Testing
@testable import NotoVault

struct VaultMediaLibraryTests {
    private let root = URL(fileURLWithPath: "/tmp/media-vault")

    @Test func extractsKindsAndPreservesSource() {
        let markdown = """
        # Design collection
        ![A room](.attachments/room%20one.jpg)
        ![](.attachments/film.MP4)
        [Interview](.attachments/voice.m4a)
        [Research](.attachments/paper.pdf)
        ![Remote](https://example.com/image?id=1)
        [Website](https://example.com)
        """
        let items = VaultMediaLibrary.items(in: markdown, noteURL: root.appendingPathComponent("inbox/a.md"), vaultURL: root)
        #expect(items.map(\.kind) == [.image, .video, .audio, .pdf, .image])
        #expect(items[0].mediaURL.path == "/tmp/media-vault/.attachments/room one.jpg")
        #expect(items.allSatisfy { $0.noteRelativePath == "inbox/a.md" && $0.noteTitle == "Design collection" })
        #expect(items.last?.mediaURL.absoluteString == "https://example.com/image?id=1")
    }

    @Test func ignoresCodeFrontmatterAndUnsafePaths() {
        let markdown = """
        ---
        cover: ![](metadata.png)
        ---
        # Note
        ```md
        ![](example.png)
        ```
        `![](inline.png)` ![real](.attachments/real.png)
        ![](%2E%2E/outside.png)
        ![](/etc/private.png)
        ![](file:///etc/private.png)
        ![](data:image/png;base64,AAAA)
        \\![escaped](escaped.png)
        """
        let items = VaultMediaLibrary.items(in: markdown, noteURL: root.appendingPathComponent("a.md"), vaultURL: root)
        #expect(items.map(\.caption) == ["real"])
    }

    @Test func deduplicatesWithinNoteButKeepsOtherSources() {
        let text = "# Note\n![first](.attachments/a.png)\n![again](.attachments/a.png)"
        let first = VaultMediaLibrary.items(in: text, noteURL: root.appendingPathComponent("a.md"), vaultURL: root)
        let second = VaultMediaLibrary.items(in: text, noteURL: root.appendingPathComponent("b.md"), vaultURL: root)
        #expect(first.count == 1)
        #expect(first[0].id != second[0].id)
    }

    @Test func sharedLinkTitlesBecomeReadableCaptions() {
        let text = "[A **beautiful** place](https://example.com/post)\n\n![](.attachments/photo.jpg)"
        let items = VaultMediaLibrary.items(in: text, noteURL: root.appendingPathComponent("inbox/shared.md"), vaultURL: root)
        #expect(items.first?.noteTitle == "A beautiful place")
        #expect(items.first?.noteRelativePath == "inbox/shared.md")
    }

    @Test func supportsAngleTargetsTitlesAndParentheses() {
        let text = #"![one](<.attachments/a b.jpg>) ![two](.attachments/a(1).png "Title")"#
        let items = VaultMediaLibrary.items(in: text, noteURL: root.appendingPathComponent("a.md"), vaultURL: root)
        #expect(items.map(\.mediaURL.lastPathComponent) == ["a b.jpg", "a(1).png"])
    }

    @Test func filtersByKindAndAllSearchTerms() {
        let items = VaultMediaLibrary.items(in: "# Café ideas\n![Green chair](.attachments/chair.jpg)\n![](.attachments/tour.mp4)", noteURL: root.appendingPathComponent("Design/a.md"), vaultURL: root)
        #expect(VaultMediaLibrary.filtered(items, query: "cafe chair", kind: .image).count == 1)
        #expect(VaultMediaLibrary.filtered(items, query: "design", kind: .video).count == 1)
        #expect(VaultMediaLibrary.filtered(items, query: "missing").isEmpty)
    }

    @Test func searchesFullBodySavedMetadataAndCombinedFields() {
        let markdown = "---\nauthor: Renée Chen\nsource: https://journal.example.org/essay\n---\n# Collection\n\nA study of bioluminescent **ocean** life.\n![](.attachments/photo.jpg)\n![](.attachments/clip.mp4)"
        let items = VaultMediaLibrary.items(in: markdown, noteURL: root.appendingPathComponent("a.md"), vaultURL: root)
        #expect(VaultMediaLibrary.filtered(items, query: "BIOLUMINESCENT").count == 2)
        #expect(VaultMediaLibrary.filtered(items, query: "renee ocean", kind: .video).count == 1)
        #expect(VaultMediaLibrary.filtered(items, query: "journal.example.org").count == 2)
        #expect(VaultMediaLibrary.filtered(items, query: "bioluminescent nonexistent").isEmpty)
    }

    @Test func searchesLinkedPreviewMetadataWithoutLeakingToOtherNotes() {
        let previewURL = URL(string: "https://example.com/post")!
        let bareURL = URL(string: "https://example.org/bare")!
        let provider: @Sendable (URL) -> String? = { url in
            if url == previewURL { return "Hidden botanical atlas Ferns and moss Woodland Journal" }
            if url == bareURL { return "Mycology research" }
            return nil
        }
        let markdown = "# Collection\nRead [this](https://example.com/post) for more.\nhttps://example.org/bare\n![](.attachments/photo.jpg)\n![](.attachments/clip.mp4)"
        let items = VaultMediaLibrary.items(in: markdown, noteURL: root.appendingPathComponent("a.md"), vaultURL: root, linkSearchText: provider)
        let unrelated = VaultMediaLibrary.items(in: "# Unrelated\n![](.attachments/photo.jpg)", noteURL: root.appendingPathComponent("b.md"), vaultURL: root, linkSearchText: provider)
        #expect(VaultMediaLibrary.filtered(items + unrelated, query: "botanical moss").map(\.noteRelativePath) == ["a.md", "a.md"])
        #expect(VaultMediaLibrary.filtered(items, query: "mycology", kind: .image).count == 1)
        #expect(VaultMediaLibrary.filtered(items, query: "collection woodland", kind: .video).count == 1)
        #expect(VaultMediaLibrary.filtered(items, query: "  \n").count == 2)
    }

    @Test func rescanReplacesRemovedBodyAndUsesLatestLinkMetadata() throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let note = vault.appendingPathComponent("a.md")
        try "# Note\nOriginal unicorn\nhttps://example.com/post\n![](.attachments/a.jpg)".write(to: note, atomically: true, encoding: .utf8)
        let first = try VaultMediaLibrary(vaultURL: vault, linkSearchText: { _ in "Old preview" }).scan()
        #expect(VaultMediaLibrary.filtered(first.items, query: "unicorn old").count == 1)
        try "# Note\nUpdated narwhal\nhttps://example.com/post\n![](.attachments/a.jpg)".write(to: note, atomically: true, encoding: .utf8)
        let updated = try VaultMediaLibrary(vaultURL: vault, linkSearchText: { _ in "New preview" }).scan()
        #expect(VaultMediaLibrary.filtered(updated.items, query: "unicorn").isEmpty)
        #expect(VaultMediaLibrary.filtered(updated.items, query: "old").isEmpty)
        #expect(VaultMediaLibrary.filtered(updated.items, query: "narwhal new").count == 1)
        let noMetadata = try VaultMediaLibrary(vaultURL: vault).scan()
        #expect(VaultMediaLibrary.filtered(noMetadata.items, query: "narwhal").count == 1)
    }

    @Test func scanReflectsEditsMovesAndDeletes() throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("inbox"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let note = vault.appendingPathComponent("inbox/a.md")
        let other = vault.appendingPathComponent("older.md")
        try "# Older\n![](.attachments/old.png)".write(to: other, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: other.path)
        try "# Fresh\n![](.attachments/a.jpg)".write(to: note, atomically: true, encoding: .utf8)
        let library = VaultMediaLibrary(vaultURL: vault)
        let initial = try library.scan()
        #expect(initial.items.map(\.noteTitle) == ["Fresh", "Older"])
        #expect(initial.unavailableNoteCount == 0)
        try "# Edited\n![](.attachments/movie.mp4)".write(to: note, atomically: true, encoding: .utf8)
        let moved = vault.appendingPathComponent("moved.md")
        try FileManager.default.moveItem(at: note, to: moved)
        let refreshed = try library.scan()
        #expect(refreshed.items.first?.kind == .video)
        #expect(refreshed.items.first?.noteURL.standardizedFileURL == moved.standardizedFileURL)
        try FileManager.default.removeItem(at: moved)
        #expect(try library.scan().items.count == 1)
    }

    @Test func missingVaultThrowsAndSymlinksCannotEscape() throws {
        #expect(throws: (any Error).self) { try VaultMediaLibrary(vaultURL: root.appendingPathComponent(UUID().uuidString)).scan() }
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/tmp"))
        let items = VaultMediaLibrary.items(in: "![](escape/private.png)", noteURL: vault.appendingPathComponent("a.md"), vaultURL: vault)
        #expect(items.isEmpty)
    }

    @Test func identitySurvivesNoteRenameAndUnavailableNotesAreReported() throws {
        let text = "---\nid: 11111111-1111-4111-8111-111111111111\n---\n# Note\n![](.attachments/a.png)"
        let before = VaultMediaLibrary.items(in: text, noteURL: root.appendingPathComponent("before.md"), vaultURL: root)
        let after = VaultMediaLibrary.items(in: text, noteURL: root.appendingPathComponent("after.md"), vaultURL: root)
        #expect(before.first?.id == after.first?.id)
        #expect(after.first?.noteRelativePath == "after.md")
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        #expect(try VaultMediaLibrary(vaultURL: vault).scan().items.isEmpty)
        try Data([0xff, 0xfe, 0xff]).write(to: vault.appendingPathComponent("unreadable.md"))
        let result = try VaultMediaLibrary(vaultURL: vault).scan()
        #expect(result.items.isEmpty)
        #expect(result.unavailableNoteCount == 1)
    }
}
