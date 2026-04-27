import Foundation
import Testing
@testable import Noto

@Suite("Note Editor Session")
struct NoteEditorSessionTests {

    @Test("Title edit debounces note rename")
    @MainActor
    func titleEditDebouncesNoteRename() async {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let editedContent = MarkdownNote.makeFrontmatter(id: note.id) + "# First Sentence"
        let session = NoteEditorSession(store: store, note: note, isNew: true)

        session.handleEditorChange(editedContent)
        #expect(session.note.title == "First Sentence")
        #expect(session.note.fileURL.lastPathComponent == note.fileURL.lastPathComponent)

        try? await Task.sleep(for: .milliseconds(900))

        #expect(session.note.fileURL.lastPathComponent == "First Sentence.md")
        #expect(FileManager.default.fileExists(atPath: session.note.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: note.fileURL.path))
    }

    @Test("Final snapshot does not rename note on disappear")
    @MainActor
    func finalSnapshotDoesNotRenameOnDisappear() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let editedContent = MarkdownNote.makeFrontmatter(id: note.id) + "# First Sentence"
        let session = NoteEditorSession(store: store, note: note, isNew: true)

        session.handleEditorChange(editedContent)
        session.cancelBackgroundWork()
        session.persistFinalSnapshotIfNeeded(isExternallyDeleting: false)

        #expect(session.note.fileURL.lastPathComponent == note.fileURL.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: note.fileURL.path))
    }

    @Test("Editor autosave is debounced while typing")
    @MainActor
    func editorAutosaveIsDebouncedWhileTyping() async {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let editedContent = MarkdownNote.makeFrontmatter(id: note.id) + "# \nDelayed body"
        let session = NoteEditorSession(store: store, note: note, isNew: true)

        session.handleEditorChange(editedContent)
        let immediateContent = CoordinatedFileManager.readString(from: note.fileURL) ?? ""
        #expect(!immediateContent.contains("Delayed body"))

        try? await Task.sleep(for: .milliseconds(650))

        let savedContent = CoordinatedFileManager.readString(from: note.fileURL) ?? ""
        #expect(savedContent.contains("Delayed body"))
    }

    @Test("Load note content reads existing file into session")
    @MainActor
    func loadNoteContentReadsExistingFileIntoSession() async {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        var note = store.createNote()
        let content = MarkdownNote.makeFrontmatter(id: note.id) + "# Loaded Title\nBody"
        note = store.saveContent(content, for: note).note
        let session = NoteEditorSession(store: store, note: note)

        await session.loadNoteContent()

        #expect(session.hasLoaded)
        #expect(!session.isDownloading)
        #expect(!session.downloadFailed)
        #expect(session.content == content)
        #expect(session.latestEditorText == content)
        #expect(session.lastPersistedText == content)
        #expect(session.note.title == "Loaded Title")
    }

    @Test("Load note content marks unreadable current files as failed")
    @MainActor
    func loadNoteContentMarksUnreadableCurrentFileAsFailed() async {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let missingURL = vault.appendingPathComponent("missing.md")
        let note = MarkdownNote(
            id: UUID(),
            fileURL: missingURL,
            title: "Missing",
            modifiedDate: Date()
        )
        let session = NoteEditorSession(store: store, note: note)

        await session.loadNoteContent()

        #expect(!session.hasLoaded)
        #expect(!session.isDownloading)
        #expect(session.downloadFailed)
        #expect(session.content.isEmpty)
    }
}

private func makeTempVault() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("NotoSessionTest-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cleanupVault(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}
