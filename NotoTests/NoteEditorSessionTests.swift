import Foundation
import Testing
@testable import Noto

@Suite("Note Editor Session")
struct NoteEditorSessionTests {

    @Test("Final snapshot renames a note even when edits were already saved")
    @MainActor
    func finalSnapshotRenamesAlreadySavedNote() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let editedContent = MarkdownNote.makeFrontmatter(id: note.id) + "# First Sentence"
        let session = NoteEditorSession(store: store, note: note, isNew: true)

        session.handleEditorChange(editedContent)
        #expect(session.note.title == "First Sentence")
        #expect(session.note.fileURL.lastPathComponent == note.fileURL.lastPathComponent)

        session.cancelBackgroundWork()
        session.persistFinalSnapshotIfNeeded(isExternallyDeleting: false)

        #expect(session.note.fileURL.lastPathComponent == "First Sentence.md")
        #expect(FileManager.default.fileExists(atPath: session.note.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: note.fileURL.path))
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
