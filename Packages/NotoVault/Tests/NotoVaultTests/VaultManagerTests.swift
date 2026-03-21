import Testing
import Foundation
@testable import NotoVault

// MARK: - Test Index
// testEnsureVaultExists — Creates the vault directory if it doesn't exist
// testCreateNote — Creates a note and writes a .md file to disk
// testCreateNoteWithContent — Created note has the provided content
// testListNotesEmpty — Empty vault returns an empty list
// testListNotesSortedByModifiedDate — Notes are listed most-recently-modified first
// testReadNoteById — Can read back a note by its ID
// testReadNoteNotFound — Reading a non-existent note throws noteNotFound
// testUpdateNote — Updating a note changes content and modifiedAt
// testUpdateNotePreservesCreatedAt — Updating a note does not change createdAt
// testUpdateNoteNotFound — Updating a non-existent note throws noteNotFound
// testDeleteNote — Deleting a note removes the file from disk
// testDeleteNoteNotFound — Deleting a non-existent note throws noteNotFound
// testCreateMultipleNotes — Multiple notes can be created and listed

@Suite("VaultManager")
struct VaultManagerTests {

    private func makeTempVault() -> (VaultManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoVaultTests-\(UUID().uuidString)")
        let manager = VaultManager(rootURL: tempDir)
        return (manager, tempDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func testEnsureVaultExists() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        #expect(!FileManager.default.fileExists(atPath: tempDir.path))
        try manager.ensureVaultExists()
        #expect(FileManager.default.fileExists(atPath: tempDir.path))
    }

    @Test func testCreateNote() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        let note = try manager.createNote()

        #expect(note.content == "")
        #expect(note.title == "Untitled")

        // File should exist on disk
        let fileURL = tempDir.appendingPathComponent("\(note.id.uuidString).md")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func testCreateNoteWithContent() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        let note = try manager.createNote(content: "# My Note\n\nHello world")

        #expect(note.content == "# My Note\n\nHello world")
        #expect(note.title == "My Note")
    }

    @Test func testListNotesEmpty() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        try manager.ensureVaultExists()
        let notes = try manager.listNotes()
        #expect(notes.isEmpty)
    }

    @Test func testListNotesSortedByModifiedDate() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        try manager.ensureVaultExists()

        // Write files with explicit different timestamps to avoid ISO8601 rounding issues
        let id1 = UUID()
        let id2 = UUID()
        let older = Date(timeIntervalSince1970: 1_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000)

        let note1 = NoteFile(id: id1, content: "First", createdAt: older, modifiedAt: older)
        let note2 = NoteFile(id: id2, content: "Second", createdAt: newer, modifiedAt: newer)

        // Write directly using Frontmatter serialization
        let md1 = Frontmatter.serialize(note1)
        let md2 = Frontmatter.serialize(note2)
        try md1.write(to: tempDir.appendingPathComponent("\(id1.uuidString).md"), atomically: true, encoding: .utf8)
        try md2.write(to: tempDir.appendingPathComponent("\(id2.uuidString).md"), atomically: true, encoding: .utf8)

        let notes = try manager.listNotes()
        #expect(notes.count == 2)
        #expect(notes[0].id == id2) // newer first
        #expect(notes[1].id == id1)
    }

    @Test func testReadNoteById() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        let created = try manager.createNote(content: "Read me back")
        let read = try manager.readNote(id: created.id)

        #expect(read.id == created.id)
        #expect(read.content == "Read me back")
    }

    @Test func testReadNoteNotFound() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        try manager.ensureVaultExists()
        let fakeId = UUID()
        #expect(throws: VaultError.noteNotFound(fakeId)) {
            _ = try manager.readNote(id: fakeId)
        }
    }

    @Test func testUpdateNote() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        let note = try manager.createNote(content: "Original")
        Thread.sleep(forTimeInterval: 0.05)
        let updated = try manager.updateNote(id: note.id, content: "Updated content")

        #expect(updated.content == "Updated content")
        #expect(updated.modifiedAt > note.modifiedAt)
        #expect(updated.id == note.id)
    }

    @Test func testUpdateNotePreservesCreatedAt() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        let note = try manager.createNote(content: "Original")
        Thread.sleep(forTimeInterval: 0.05)
        let updated = try manager.updateNote(id: note.id, content: "Changed")

        // createdAt should be the same (within 1 second tolerance for ISO8601 rounding)
        let diff = abs(updated.createdAt.timeIntervalSince(note.createdAt))
        #expect(diff < 1.0)
    }

    @Test func testUpdateNoteNotFound() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        try manager.ensureVaultExists()
        let fakeId = UUID()
        #expect(throws: VaultError.noteNotFound(fakeId)) {
            _ = try manager.updateNote(id: fakeId, content: "nope")
        }
    }

    @Test func testDeleteNote() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        let note = try manager.createNote(content: "Delete me")
        try manager.deleteNote(id: note.id)

        let fileURL = tempDir.appendingPathComponent("\(note.id.uuidString).md")
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func testDeleteNoteNotFound() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        try manager.ensureVaultExists()
        let fakeId = UUID()
        #expect(throws: VaultError.noteNotFound(fakeId)) {
            try manager.deleteNote(id: fakeId)
        }
    }

    @Test func testCreateMultipleNotes() throws {
        let (manager, tempDir) = makeTempVault()
        defer { cleanup(tempDir) }

        _ = try manager.createNote(content: "Note A")
        _ = try manager.createNote(content: "Note B")
        _ = try manager.createNote(content: "Note C")

        let notes = try manager.listNotes()
        #expect(notes.count == 3)
    }
}
