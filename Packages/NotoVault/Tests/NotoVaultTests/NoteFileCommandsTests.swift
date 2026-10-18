import Foundation
import Testing
@testable import NotoVault

@Suite("Desktop file commands")
struct NoteFileCommandsTests {
    @Test func librarySortingAndDescendantsRespectFolderBoundaries() {
        let root = URL(fileURLWithPath: "/tmp/vault")
        let notes = [("Zulu", "Projects/Zulu.md", 1.0), ("Alpha", "Projects/Sub/Alpha.md", 2.0), ("Bravo", "ProjectsTwo/Bravo.md", 3.0)].map { title, path, time in
            VaultLibraryNote(record: VaultNoteRecord(id: UUID(), fileURL: root.appendingPathComponent(path), title: title, modifiedDate: Date(timeIntervalSince1970: time)), relativePath: path, content: "# " + title, isAvailable: true)
        }
        #expect(VaultLibrarySortOrder.newest.sorted(notes).map(\.title) == ["Bravo", "Alpha", "Zulu"])
        #expect(VaultLibrarySortOrder.oldest.sorted(notes).map(\.title) == ["Zulu", "Alpha", "Bravo"])
        #expect(VaultLibrarySortOrder.title.sorted(notes).map(\.title) == ["Alpha", "Bravo", "Zulu"])
        let library = VaultLibrarySnapshot(notes: notes, folders: [])
        #expect(library.notes(in: root.appendingPathComponent("Projects")).map(\.title) == ["Zulu"])
        #expect(library.notes(in: root.appendingPathComponent("Projects"), includingDescendants: true).map(\.title) == ["Zulu", "Alpha"])
    }

    @Test func renamePreservesMetadataAndFollowingBody() {
        let source = "---\nid: unchanged\ntags: [work]\n---\n\n# Old title\n\nBody with # marks.\n"
        #expect(VaultMarkdown.renamingTitle(in: source, to: "New title") == source.replacingOccurrences(of: "# Old title", with: "# New title"))
        #expect(VaultMarkdown.renamingTitle(in: "", to: "First") == "# First")
        #expect(VaultMarkdown.renamingTitle(in: source, to: "  ") == source)
    }

    @Test func duplicateKeepsSourceAndCreatesIndependentIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = NoteRepository(directoryURL: root)
        let note = repo.createNote()
        let source = NoteFrontmatter.setting("tags", to: "[work]", in: repo.readContent(of: note)) + "Title\n\nBody.\n"
        let original = repo.saveContent(source, for: note).note
        let saved = repo.readContent(of: original)
        let first = try repo.duplicate(original)
        let second = try repo.duplicate(original)
        #expect(first.id != original.id && second.id != first.id)
        #expect(first.fileURL != second.fileURL)
        #expect(repo.readContent(of: original) == saved)
        #expect(VaultMarkdown.stripFrontmatter(repo.readContent(of: first)) == VaultMarkdown.stripFrontmatter(saved))
        #expect(NoteFrontmatter.value(for: "tags", in: repo.readContent(of: first)) == "[work]")
        #expect(VaultMarkdown.idFromFrontmatter(repo.readContent(of: first)) == first.id)
    }
}
