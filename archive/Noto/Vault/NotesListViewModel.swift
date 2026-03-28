import Foundation
import os.log
import NotoVault

@MainActor
final class NotesListViewModel: ObservableObject {
    @Published var notes: [NoteFile] = []

    private let vault: VaultManager
    private let logger = Logger(subsystem: "com.noto", category: "NotesListViewModel")

    init(vault: VaultManager) {
        self.vault = vault
    }

    func loadNotes() {
        do {
            notes = try vault.listNotes()
        } catch {
            logger.error("Failed to load notes: \(error)")
        }
    }

    func createNote() -> NoteFile? {
        do {
            let note = try vault.createNote()
            loadNotes()
            return note
        } catch {
            logger.error("Failed to create note: \(error)")
            return nil
        }
    }

    func deleteNote(_ note: NoteFile) {
        do {
            try vault.deleteNote(id: note.id)
            loadNotes()
        } catch {
            logger.error("Failed to delete note: \(error)")
        }
    }
}
