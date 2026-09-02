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

    @Test("Editor changes track latest text without replacing bound content until save")
    @MainActor
    func editorChangesTrackLatestTextWithoutReplacingBoundContentUntilSave() async {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        var note = store.createNote()
        let loadedContent = MarkdownNote.makeFrontmatter(id: note.id) + "# Loaded\nBody"
        note = store.saveContent(loadedContent, for: note).note
        let loadedFromDisk = CoordinatedFileManager.readString(from: note.fileURL) ?? loadedContent
        let editedContent = loadedFromDisk.replacingOccurrences(of: "Body", with: "Body plus edit")
        let session = NoteEditorSession(store: store, note: note)

        await session.loadNoteContent()
        session.handleEditorChange(editedContent)

        #expect(session.content == loadedFromDisk)
        #expect(session.latestEditorText == editedContent)
        #expect(session.hasPendingLocalEdits)

        try? await Task.sleep(for: .milliseconds(650))

        #expect(session.content == editedContent)
        #expect(session.lastPersistedText == editedContent)
        #expect(!session.hasPendingLocalEdits)
    }

    @Test("Move note flushes pending edits and updates session file URL")
    @MainActor
    func moveNoteFlushesPendingEditsAndUpdatesSessionFileURL() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)
        let destinationURL = vault.appendingPathComponent("Archive")
        try! FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let note = store.createNote()
        let editedContent = MarkdownNote.makeFrontmatter(id: note.id) + "# Moved Title\nUnsaved body"
        let session = NoteEditorSession(store: store, note: note, isNew: true)

        session.handleEditorChange(editedContent)
        let moved = session.moveNote(to: destinationURL)

        #expect(moved.fileURL.deletingLastPathComponent().standardizedFileURL == destinationURL.standardizedFileURL)
        #expect(session.note.fileURL == moved.fileURL)
        #expect(!FileManager.default.fileExists(atPath: note.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: moved.fileURL.path))

        let movedContent = CoordinatedFileManager.readString(from: moved.fileURL) ?? ""
        #expect(movedContent.contains("Unsaved body"))
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

    @Test("Editor task ordering: switch-then-load shows incoming note even when the load task runs before onChange")
    @MainActor
    func switchThenLoadShowsIncomingNoteRegardlessOfCallbackOrder() async {
        // Regression for bug 024: on macOS, NoteEditorScreen's `.task(id:)`
        // restarts BEFORE `.onChange(of: note)` performs `switchTo`. The task
        // must therefore switch the session itself before deciding whether to
        // load, otherwise it sees the outgoing note's `hasLoaded == true`,
        // skips the load, and the subsequent switchTo leaves a blank editor.
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        var noteA = store.createNote()
        noteA = store.saveContent(MarkdownNote.makeFrontmatter(id: noteA.id) + "# Note A\nAlpha", for: noteA).note
        var noteB = store.createNote()
        let contentB = MarkdownNote.makeFrontmatter(id: noteB.id) + "# Note B\nBravo"
        noteB = store.saveContent(contentB, for: noteB).note

        let session = NoteEditorSession(store: store, note: noteA)
        await session.loadNoteContent()
        #expect(session.hasLoaded)

        // Mirror the fixed `.task(id:)` body, which runs while the session
        // still holds note A with hasLoaded == true.
        session.switchTo(note: noteB, store: store, isNew: false)
        if !session.hasLoaded {
            await session.loadNoteContent()
        }

        #expect(session.note.id == noteB.id)
        #expect(session.hasLoaded)
        #expect(session.content == contentB)
    }

    @Test("Switching to the same note id preserves loaded content")
    @MainActor
    func switchToSameNoteIDPreservesLoadedContent() async {
        // The fixed `.task(id:)` calls switchTo unconditionally on first
        // appear; a same-id switch must not clear the already-loaded content.
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        var note = store.createNote()
        let content = MarkdownNote.makeFrontmatter(id: note.id) + "# Same\nBody"
        note = store.saveContent(content, for: note).note

        let session = NoteEditorSession(store: store, note: note)
        await session.loadNoteContent()
        #expect(session.hasLoaded)

        session.switchTo(note: note, store: store, isNew: false)

        #expect(session.hasLoaded)
        #expect(session.content == content)
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
