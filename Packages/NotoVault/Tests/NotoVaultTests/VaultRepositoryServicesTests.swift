import Foundation
import Testing
import NotoVault

@Suite("Vault repository services")
struct VaultRepositoryServicesTests {
    @Test("NoteRepository creates, saves, renames, resolves, moves, and deletes notes")
    func noteRepositoryMutationSequence() throws {
        let vault = try makeTempVault()
        defer { removeDirectory(vault) }
        let repository = NoteRepository(directoryURL: vault, vaultRootURL: vault)

        let created = repository.createNote()
        #expect(FileManager.default.fileExists(atPath: created.fileURL.path))

        let content = VaultMarkdown.makeFrontmatter(id: created.id) + "# Renamed Note\n\nBody"
        let saved = repository.saveContent(content, for: created)
        #expect(saved.didWrite)
        #expect(saved.note.title == "Renamed Note")

        let renamed = repository.renameFileIfNeeded(for: saved.note)
        #expect(renamed.fileURL.lastPathComponent == "Renamed Note.md")
        #expect(repository.relativePath(for: renamed.fileURL) == "Renamed Note.md")
        #expect(repository.note(atVaultRelativePath: "Renamed%20Note.md")?.id == created.id)
        #expect(repository.note(withID: created.id)?.fileURL == renamed.fileURL)

        let archive = vault.appendingPathComponent("Archive", isDirectory: true)
        let moved = repository.moveNote(renamed, to: archive)
        #expect(moved.fileURL.deletingLastPathComponent() == archive.standardizedFileURL)

        #expect(repository.deleteNote(moved))
        #expect(!FileManager.default.fileExists(atPath: moved.fileURL.path))
    }

    @Test("FolderRepository creates, moves with conflict suffix, and deletes folders")
    func folderRepositoryMutationSequence() throws {
        let vault = try makeTempVault()
        defer { removeDirectory(vault) }
        let repository = FolderRepository(directoryURL: vault)
        let destination = vault.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("Projects"), withIntermediateDirectories: true)

        let folder = repository.createFolder(named: "Projects")
        let moved = repository.moveFolder(
            id: folder.id,
            folderURL: folder.folderURL,
            name: folder.name,
            modifiedDate: folder.modifiedDate,
            folderCount: folder.folderCount,
            itemCount: folder.itemCount,
            to: destination
        )

        #expect(moved.folderURL.lastPathComponent == "Projects(2)")
        #expect(repository.deleteFolder(at: moved.folderURL))
    }

    @Test("DailyNoteService creates daily note once and applies template retroactively")
    func dailyNoteServiceIsIdempotentAndAppliesTemplate() throws {
        let vault = try makeTempVault()
        defer { removeDirectory(vault) }
        let calendar = Calendar(identifier: .gregorian)
        let date = try #require(ISO8601DateFormatter().date(from: "2026-04-27T08:00:00Z"))
        let service = DailyNoteService(vaultRootURL: vault)

        let first = service.ensure(date: date, calendar: calendar)
        let second = service.ensure(date: date, calendar: calendar)

        #expect(first.didCreate)
        #expect(!second.didCreate)
        #expect(first.fileURL == second.fileURL)
        #expect((CoordinatedVaultFileSystem().readString(from: first.fileURL) ?? "").contains("## What did I do today?"))
    }

    @Test("VaultPathResolver rejects path traversal and non-markdown paths")
    func pathResolverRejectsInvalidRelativePaths() throws {
        let vault = try makeTempVault()
        defer { removeDirectory(vault) }
        let resolver = VaultPathResolver(vaultRootURL: vault)

        #expect(resolver.noteURL(forVaultRelativePath: "../Escape.md") == nil)
        #expect(resolver.noteURL(forVaultRelativePath: "Image.png") == nil)
        #expect(resolver.noteURL(forVaultRelativePath: "Folder/Note.md")?.path.hasSuffix("Folder/Note.md") == true)
    }

    @Test("AttachmentStore exposes deterministic markdown paths and filename cleanup")
    func attachmentHelpersNormalizeMarkdownPaths() {
        #expect(AttachmentStore.sanitizedStem(from: #"BadName?:*.png"#) == "BadName")
        #expect(AttachmentStore.markdownPath(for: ".attachments/My Image.png") == ".attachments/My%20Image.png")
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoVaultRepositoryServices-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    private func removeDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
