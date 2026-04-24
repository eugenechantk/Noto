import Foundation
import Testing
@testable import NotoVault

@Suite("VaultDirectoryLoader")
struct VaultDirectoryLoaderTests {
    @Test
    func loadItemsUsesSharedMarkdownTitleResolution() throws {
        let root = try makeVault { root in
            try makeFolder(root.appendingPathComponent("Projects"))
            let noteURL = root.appendingPathComponent("F28A576E-2004-4FBF-81C6-8F41DD03737C.md")
            try """
            ---
            id: F28A576E-2004-4FBF-81C6-8F41DD03737C
            created: 2026-04-20T00:00:00Z
            updated: 2026-04-20T00:00:00Z
            ---

            # Shared Title
            """.write(to: noteURL, atomically: true, encoding: .utf8)
        }

        let items = try VaultDirectoryLoader().loadItems(in: root)

        #expect(items.count == 2)
        guard case .folder(let folder) = items[0],
              case .note(let note) = items[1] else {
            Issue.record("Expected folder followed by note")
            return
        }
        #expect(folder.name == "Projects")
        #expect(note.title == "Shared Title")
        #expect(note.id.uuidString == "F28A576E-2004-4FBF-81C6-8F41DD03737C")
    }

    @Test
    func loadItemsResolvesMetadataFromPrefixForLargeNotes() throws {
        let noteID = "F28A576E-2004-4FBF-81C6-8F41DD03737C"
        let root = try makeVault { root in
            let noteURL = root.appendingPathComponent("Large.md")
            let markdown = """
            ---
            id: \(noteID)
            created: 2026-04-20T00:00:00Z
            updated: 2026-04-20T00:00:00Z
            ---

            # Large Note

            \(String(repeating: "Body line\n", count: 20_000))
            """
            try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
        }

        let items = try VaultDirectoryLoader().loadItems(in: root)

        guard case .note(let note) = items.first else {
            Issue.record("Expected a note")
            return
        }
        #expect(note.title == "Large Note")
        #expect(note.id.uuidString == noteID)
    }

    @Test
    func uuidNoteWithoutTitleDisplaysUntitled() throws {
        let root = try makeVault { root in
            let noteURL = root.appendingPathComponent("F28A576E-2004-4FBF-81C6-8F41DD03737C.md")
            try "# ".write(to: noteURL, atomically: true, encoding: .utf8)
        }

        let items = try VaultDirectoryLoader().loadItems(in: root)

        guard case .note(let note) = items.first else {
            Issue.record("Expected a note")
            return
        }
        #expect(note.title == "Untitled")
    }

    @Test
    func foldersIncludeImmediateFolderAndItemCounts() throws {
        let root = try makeVault { root in
            let projects = root.appendingPathComponent("Projects")
            try makeFolder(projects)
            try makeFolder(projects.appendingPathComponent("Drafts"))
            try makeFolder(projects.appendingPathComponent("Archive"))
            try "# Brief".write(to: projects.appendingPathComponent("Brief.md"), atomically: true, encoding: .utf8)
            try "# Notes".write(to: projects.appendingPathComponent("Notes.MD"), atomically: true, encoding: .utf8)
            try "ignore".write(to: projects.appendingPathComponent("image.png"), atomically: true, encoding: .utf8)
        }

        let items = try VaultDirectoryLoader().loadItems(in: root)

        guard case .folder(let folder) = items.first else {
            Issue.record("Expected a folder")
            return
        }
        #expect(folder.name == "Projects")
        #expect(folder.folderCount == 2)
        #expect(folder.itemCount == 2)
    }

    private func makeVault(_ build: (URL) throws -> Void) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoVaultTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try build(root)
        return root
    }

    private func makeFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
