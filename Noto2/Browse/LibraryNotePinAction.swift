import Foundation
import NotoVault

/// Bridges a surgical metadata write into the editor's existing snapshot path.
/// Flushing first and applying the returned snapshot prevents autosave from dropping a pin.
@MainActor
enum LibraryNotePinAction {
    static func toggle(session: NoteEditorSession) throws {
        session.persistFinalSnapshotIfNeeded(isExternallyDeleting: false)
        guard session.hasLoaded, !session.hasPendingLocalEdits else { throw NotePinning.PinError.writeFailed }
        let service = NotePinning(vaultRootURL: session.store.vaultRootURL)
        let markdown = try service.setPinned(!NotePinning.isPinned(in: session.content), at: session.note.fileURL)
        let snapshot = NoteSyncSnapshot(noteID: session.note.id, fileURL: session.note.fileURL, text: markdown, sourceEditorID: UUID(), savedAt: Date())
        session.handleRemoteSnapshot(snapshot)
        NoteSyncCenter.publish(snapshot)
    }
}
