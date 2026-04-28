import Foundation
import NotoSearch
import Testing
@testable import Noto

@Suite("VaultController")
struct VaultControllerTests {
    @MainActor
    @Test("Compatibility facade loads root and folder contents through current store behavior")
    func loadsRootAndFolderContents() throws {
        let vault = try VaultControllerTestFixture.makeTempVault()
        defer { VaultControllerTestFixture.cleanup(vault) }

        try VaultControllerTestFixture.writeMarkdown(
            title: "Root Note",
            body: "Root body",
            relativePath: "Root Note.md",
            in: vault
        )
        try VaultControllerTestFixture.writeMarkdown(
            title: "Nested Note",
            body: "Nested body",
            relativePath: "Projects/Nested Note.md",
            in: vault
        )

        let controller = VaultController(vaultURL: vault)
        controller.loadRoot()

        #expect(controller.rootItems.count == 2)
        let folder = try #require(controller.rootStore.folders.first { $0.name == "Projects" })
        let folderItems = controller.loadFolder(folder)

        #expect(folderItems.count == 1)
        #expect(folderItems.contains { item in
            if case .note(let note) = item {
                return note.title == "Nested Note"
            }
            return false
        })
    }

    @MainActor
    @Test("Compatibility facade creates saves renames resolves moves and deletes notes")
    func mutatesNotesThroughCurrentStoreBehavior() throws {
        let vault = try VaultControllerTestFixture.makeTempVault()
        defer { VaultControllerTestFixture.cleanup(vault) }

        let controller = VaultController(vaultURL: vault)
        let created = controller.createNote()
        let content = MarkdownNote.makeFrontmatter(id: created.note.id) + """
        # Controller Baseline

        Saved through VaultController facade.
        """

        var note = controller.save(content, for: created.note, in: created.store).note
        note = controller.renameIfNeeded(note, in: created.store)

        #expect(note.title == "Controller Baseline")
        #expect(note.fileURL.lastPathComponent == "Controller Baseline.md")
        #expect(controller.openNote(note, in: created.store).contains("Saved through VaultController facade."))

        let resolved = try #require(controller.note(withID: note.id))
        #expect(resolved.note.fileURL == note.fileURL)

        let archive = controller.createFolder(named: "Archive")
        let moved = controller.move(note, to: archive.folderURL, in: created.store)

        #expect(moved.fileURL.deletingLastPathComponent().lastPathComponent == "Archive")
        #expect(controller.vaultRelativePath(for: moved.fileURL) == "Archive/Controller Baseline.md")

        #expect(controller.delete(moved, in: controller.store(for: archive, autoload: false)))
        #expect(!FileManager.default.fileExists(atPath: moved.fileURL.path))
    }

    @MainActor
    @Test("Compatibility facade exposes today note and page mentions")
    func exposesTodayNoteAndPageMentions() throws {
        let vault = try VaultControllerTestFixture.makeTempVault()
        defer { VaultControllerTestFixture.cleanup(vault) }

        try VaultControllerTestFixture.writeMarkdown(
            title: "Mention Target",
            body: "Body",
            relativePath: "Projects/Mention Target.md",
            in: vault
        )

        let controller = VaultController(vaultURL: vault)
        let today = controller.todayNote()
        let todayContent = controller.openNote(today.note, in: today.store)

        #expect(today.note.fileURL.deletingLastPathComponent().lastPathComponent == "Daily Notes")
        #expect(todayContent.contains("## What did I do today?"))

        let mentions = controller.pageMentions(matching: "Mention", limit: 10)
        #expect(mentions.contains { $0.relativePath == "Projects/Mention Target.md" })
    }

    @MainActor
    @Test("Compatibility facade searches through the current NotoSearch index")
    func searchesCurrentIndex() async throws {
        let vault = try VaultControllerTestFixture.makeTempVault()
        defer { VaultControllerTestFixture.cleanup(vault) }
        defer { VaultControllerTestFixture.cleanup(MarkdownSearchIndexer(vaultURL: vault).indexDirectory) }

        let controller = VaultController(vaultURL: vault)
        let created = controller.createNote()
        let content = MarkdownNote.makeFrontmatter(id: created.note.id) + """
        # Controller Search

        Searchable controller phrase.
        """
        let note = controller.save(content, for: created.note, in: created.store).note
        _ = try await SearchIndexController.shared.refreshFile(vaultURL: vault, fileURL: note.fileURL)

        let results = try controller.search(query: "searchable controller phrase")

        #expect(results.contains { $0.title == "Controller Search" })
    }
}

private enum VaultControllerTestFixture {
    static func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoVaultControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func writeMarkdown(
        title: String,
        body: String,
        id: UUID = UUID(),
        relativePath: String,
        in vaultURL: URL
    ) throws {
        let fileURL = vaultURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let markdown = MarkdownNote.makeFrontmatter(id: id) + "# \(title)\n\n\(body)\n"
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
