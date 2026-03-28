import Foundation
import os.log
import NotoVault

@MainActor
final class NoteEditorViewModel: ObservableObject {
    @Published var content: String
    let noteId: UUID

    private let vault: VaultManager
    private let logger = Logger(subsystem: "com.noto", category: "NoteEditorViewModel")

    init(note: NoteFile, vault: VaultManager) {
        self.noteId = note.id
        self.content = note.content
        self.vault = vault
    }

    func save() {
        do {
            _ = try vault.updateNote(id: noteId, content: content)
        } catch {
            logger.error("Failed to save note: \(error)")
        }
    }
}
