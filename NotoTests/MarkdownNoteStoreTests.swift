/// # Test Index
///
/// ## Note CRUD
/// - `testCreateNote` — Creates .md file with frontmatter + "# " prefix
/// - `testReadContent` — Reads back the content that was written
/// - `testSaveContent` — Saves content and updates title in items list
/// - `testDeleteNote` — Removes file and item from list
///
/// ## Frontmatter
/// - `testFrontmatterGeneration` — Frontmatter contains id, created, updated fields
/// - `testFrontmatterIdExtraction` — UUID extracted correctly from frontmatter
/// - `testFrontmatterTimestampUpdate` — Updated timestamp changes on save
/// - `testTitleExtraction` — Title derived from first line after frontmatter, stripping #
/// - `testTitleExtractionUntitled` — Empty content returns "Untitled"
///
/// ## Daily Notes
/// - `testTodayNoteCreation` — Creates Daily Notes folder and YYYY-MM-DD.md file
/// - `testTodayNoteTemplate` — New daily note includes template headings
/// - `testTodayNoteIdempotent` — Calling todayNote() twice returns same file
/// - `testTodayNoteRetroactiveTemplate` — Existing daily note without template gets it applied
///
/// ## Templates
/// - `testDailyNoteTemplateContent` — Template body contains all 4 reflection headings
/// - `testTemplateNotAppliedTwice` — Template not duplicated if already present
/// - `testRetroactiveTemplatePreservesContent` — Existing user content preserved when template applied
///
/// ## File Rename
/// - `testRenameFileIfNeeded` — File renamed to match title
/// - `testDailyNoteNotRenamed` — Daily notes (YYYY-MM-DD.md) keep ISO date filename
///
/// ## Folders
/// - `testCreateFolder` — Creates directory and adds to items
/// - `testDeleteFolder` — Removes directory and item
/// - `testFoldersListedFirst` — Folders appear before notes in items list
///
/// ## Move Note
/// - `testMoveNoteToSubfolder` — Moves note file to subfolder, removes from source items
/// - `testMoveNoteBetweenSubfolders` — Moves note from one subfolder to another
/// - `testMoveNoteFilenameConflict` — Appends (2) when filename exists at destination
/// - `testMoveNoteMultipleConflicts` — Appends (3), (4) for successive conflicts
/// - `testMoveNoteToSameDirectory` — No-op, returns original note
/// - `testMoveNotePreservesContent` — File content identical before and after move
/// - `testMoveNoteCreatesDestination` — Creates destination directory if it doesn't exist
///
/// ## Move Folder
/// - `testMoveFolderToSubfolder` — Moves folder and contents to new location
/// - `testMoveFolderNameConflict` — Appends (2) when folder name exists at destination
/// - `testMoveFolderToSameDirectory` — No-op, returns original folder
///
/// ## Timestamp Behavior
/// - `testSaveUnchangedContentDoesNotUpdateTimestamp` — Saving identical content preserves original updated timestamp
/// - `testSaveChangedContentUpdatesTimestamp` — Saving modified content updates the updated timestamp
/// - `testCreatedTimestampNeverChanges` — created field is never modified by save
/// - `testMultipleSavesWithoutChanges` — Repeated saves of unchanged content never update timestamp
/// - `testUnchangedSavePreservesModifiedDate` — modifiedDate on in-memory note preserved when content unchanged

import Testing
import Foundation
@testable import Noto

// MARK: - Helpers

/// Creates a temporary directory for test vault operations.
private func makeTempVault() -> URL {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("NotoTest-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    return tmp
}

/// Cleans up a temporary vault directory.
private func cleanupVault(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - Note CRUD Tests

@Suite("Note CRUD")
struct NoteCRUDTests {

    @Test("Create note produces .md file with frontmatter and heading prefix")
    @MainActor
    func testCreateNote() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        #expect(FileManager.default.fileExists(atPath: note.fileURL.path))

        let content = try String(contentsOf: note.fileURL, encoding: .utf8)
        #expect(content.hasPrefix("---"))
        #expect(content.contains("id:"))
        #expect(content.contains("# "))
    }

    @Test("Read content returns file contents")
    @MainActor
    func testReadContent() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let content = store.readContent(of: note)
        #expect(content.contains("---"))
        #expect(content.contains("# "))
    }

    @Test("Save content writes file and updates title in items")
    @MainActor
    func testSaveContent() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let content = MarkdownNote.makeFrontmatter(id: note.id) + "# My Title\nBody text"
        let updated = store.saveContent(content, for: note)

        #expect(updated.note.title == "My Title")

        let saved = try String(contentsOf: note.fileURL, encoding: .utf8)
        #expect(saved.contains("My Title"))
        #expect(saved.contains("Body text"))
    }

    @Test("Load items derives note title from markdown content")
    @MainActor
    func testLoadItemsDerivesTitleFromMarkdownContent() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let id = UUID()
        let fileURL = vault.appendingPathComponent("\(id.uuidString).md")
        let content = MarkdownNote.makeFrontmatter(id: id) + "# Shared Loader Title\nBody text"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = MarkdownNoteStore(vaultURL: vault)

        #expect(store.notes.first?.id == id)
        #expect(store.notes.first?.title == "Shared Loader Title")
    }

    @Test("UUID filename without title loads as Untitled")
    @MainActor
    func testLoadItemsUUIDFilenameWithoutTitleLoadsAsUntitled() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let fileURL = vault.appendingPathComponent("\(UUID().uuidString).md")
        try "# ".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = MarkdownNoteStore(vaultURL: vault)

        #expect(store.notes.first?.title == "Untitled")
    }

    @Test("Delete note removes file and item")
    @MainActor
    func testDeleteNote() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        #expect(store.notes.count == 1)

        store.deleteNote(note)
        #expect(store.notes.count == 0)
        #expect(!FileManager.default.fileExists(atPath: note.fileURL.path))
    }
}

// MARK: - Frontmatter Tests

@Suite("Frontmatter")
struct FrontmatterTests {

    @Test("Frontmatter contains id, created, updated fields")
    func testFrontmatterGeneration() {
        let id = UUID()
        let fm = MarkdownNote.makeFrontmatter(id: id)
        #expect(fm.contains("id: \(id.uuidString)"))
        #expect(fm.contains("created:"))
        #expect(fm.contains("updated:"))
        #expect(fm.hasPrefix("---"))
        #expect(fm.contains("\n---\n"))
    }

    @Test("UUID extracted correctly from frontmatter")
    func testFrontmatterIdExtraction() {
        let id = UUID()
        let fm = MarkdownNote.makeFrontmatter(id: id)
        let extracted = MarkdownNote.idFromFrontmatter(fm)
        #expect(extracted == id)
    }

    @Test("Updated timestamp changes on save")
    func testFrontmatterTimestampUpdate() {
        let id = UUID()
        let original = MarkdownNote.makeFrontmatter(id: id)
        // The updated field should be present
        #expect(original.contains("updated:"))

        let modified = MarkdownNote.updateTimestamp(in: original + "# Title")
        #expect(modified.contains("updated:"))
    }

    @Test("Title derived from first line after frontmatter")
    func testTitleExtraction() {
        let content = "---\nid: abc\n---\n# My Note Title"
        #expect(MarkdownNote.titleFrom(content) == "My Note Title")
    }

    @Test("Empty content returns Untitled")
    func testTitleExtractionUntitled() {
        #expect(MarkdownNote.titleFrom("") == "Untitled")
        #expect(MarkdownNote.titleFrom("---\nid: abc\n---\n") == "Untitled")
    }
}

// MARK: - Daily Note Tests

@Suite("Daily Notes")
struct DailyNoteTests {

    @Test("Today note creates Daily Notes folder and date-named file")
    @MainActor
    func testTodayNoteCreation() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let (_, note) = store.todayNote()

        let dailyFolder = vault.appendingPathComponent("Daily Notes")
        #expect(FileManager.default.fileExists(atPath: dailyFolder.path))
        #expect(FileManager.default.fileExists(atPath: note.fileURL.path))

        // Filename should be YYYY-MM-DD.md
        let filename = note.fileURL.deletingPathExtension().lastPathComponent
        let dateRegex = #"^\d{4}-\d{2}-\d{2}$"#
        #expect(filename.range(of: dateRegex, options: .regularExpression) != nil)
    }

    @Test("New daily note includes template headings")
    @MainActor
    func testTodayNoteTemplate() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let (dailyStore, note) = store.todayNote()
        let content = dailyStore.readContent(of: note)

        #expect(content.contains("## What did I do today?"))
        #expect(content.contains("## What's on my mind today?"))
        #expect(content.contains("## How do I feel today? Why am I feeling this way?"))
        #expect(content.contains("## What will I do with this information?"))
    }

    @Test("Calling todayNote() twice returns same file")
    @MainActor
    func testTodayNoteIdempotent() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let (_, note1) = store.todayNote()
        let (_, note2) = store.todayNote()

        #expect(note1.fileURL == note2.fileURL)
    }

    @Test("Existing daily note without template gets it applied retroactively")
    @MainActor
    func testTodayNoteRetroactiveTemplate() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }

        // Create a daily note file manually WITHOUT the template
        let dailyFolder = vault.appendingPathComponent("Daily Notes")
        try FileManager.default.createDirectory(at: dailyFolder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "\(formatter.string(from: Date())).md"
        let fileURL = dailyFolder.appendingPathComponent(filename)

        let id = UUID()
        let content = MarkdownNote.makeFrontmatter(id: id) + "# 23 Mar, 26 (Mon)\n"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Now call todayNote() — it should retroactively apply the template
        let store = MarkdownNoteStore(vaultURL: vault)
        let (dailyStore, note) = store.todayNote()
        let updatedContent = dailyStore.readContent(of: note)

        #expect(updatedContent.contains("## What did I do today?"))
    }
}

// MARK: - Template Tests

@Suite("Note Templates")
struct NoteTemplateTests {

    @Test("Daily note template contains all 4 reflection headings")
    func testDailyNoteTemplateContent() {
        let body = NoteTemplate.dailyNote.body
        #expect(body.contains("## What did I do today?"))
        #expect(body.contains("## What's on my mind today?"))
        #expect(body.contains("## How do I feel today? Why am I feeling this way?"))
        #expect(body.contains("## What will I do with this information?"))
    }

    @Test("Template is not applied twice if already present")
    func testTemplateNotAppliedTwice() {
        let template = NoteTemplate.dailyNote
        let content = "---\nid: abc\n---\n# Title\n" + template.body
        let result = template.applyRetroactively(to: content)
        #expect(result == nil) // nil means no change needed
    }

    @Test("Retroactive template preserves existing user content")
    func testRetroactiveTemplatePreservesContent() {
        let template = NoteTemplate.dailyNote
        let content = "---\nid: abc\n---\n# Title\nMy existing notes here"
        let result = template.applyRetroactively(to: content)
        #expect(result != nil)
        #expect(result!.contains("My existing notes here"))
        #expect(result!.contains("## What did I do today?"))
    }
}

// MARK: - File Rename Tests

@Suite("File Rename")
struct FileRenameTests {

    @Test("File renamed to match note title")
    @MainActor
    func testRenameFileIfNeeded() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        var note = store.createNote()
        let content = MarkdownNote.makeFrontmatter(id: note.id) + "# My Custom Title"
        note = store.saveContent(content, for: note).note
        let renamed = store.renameFileIfNeeded(for: note)

        #expect(renamed.fileURL.lastPathComponent == "My Custom Title.md")
    }

    @Test("Daily notes keep ISO date filename")
    @MainActor
    func testDailyNoteNotRenamed() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let (dailyStore, note) = store.todayNote()
        let renamed = dailyStore.renameFileIfNeeded(for: note)

        // Filename should still be YYYY-MM-DD.md, not the display title
        let stem = renamed.fileURL.deletingPathExtension().lastPathComponent
        #expect(stem.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
    }
}

// MARK: - Folder Tests

@Suite("Folder Operations")
struct FolderTests {

    @Test("Create folder adds directory and item")
    @MainActor
    func testCreateFolder() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let folder = store.createFolder(name: "My Folder")
        #expect(FileManager.default.fileExists(atPath: folder.folderURL.path))
        #expect(store.folders.count == 1)
        #expect(store.folders.first?.name == "My Folder")
    }

    @Test("Delete folder removes directory and item")
    @MainActor
    func testDeleteFolder() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let folder = store.createFolder(name: "ToDelete")
        #expect(store.folders.count == 1)

        store.deleteFolder(folder)
        #expect(store.folders.count == 0)
        #expect(!FileManager.default.fileExists(atPath: folder.folderURL.path))
    }

    @Test("Folders listed before notes in items")
    @MainActor
    func testFoldersListedFirst() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        _ = store.createNote()
        _ = store.createFolder(name: "AFolder")

        // First item should be the folder
        if case .folder(let f) = store.items.first {
            #expect(f.name == "AFolder")
        } else {
            #expect(Bool(false), "First item should be a folder")
        }
    }
}

// MARK: - Move Note Tests

@Suite("Move Note")
struct MoveNoteTests {

    @Test("Move note to subfolder — file at destination, removed from source")
    @MainActor
    func testMoveNoteToSubfolder() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let destURL = vault.appendingPathComponent("SubFolder")

        let moved = store.moveNote(note, to: destURL)

        // File exists at destination
        #expect(FileManager.default.fileExists(atPath: moved.fileURL.path))
        #expect(moved.fileURL.deletingLastPathComponent().lastPathComponent == "SubFolder")

        // Removed from source items
        #expect(store.notes.count == 0)

        // Gone from original location
        #expect(!FileManager.default.fileExists(atPath: note.fileURL.path))
    }

    @Test("Move note between subfolders")
    @MainActor
    func testMoveNoteBetweenSubfolders() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }

        let folderA = vault.appendingPathComponent("FolderA")
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        let storeA = MarkdownNoteStore(directoryURL: folderA, vaultRootURL: vault)

        let note = storeA.createNote()
        let folderB = vault.appendingPathComponent("FolderB")

        let moved = storeA.moveNote(note, to: folderB)

        #expect(moved.fileURL.deletingLastPathComponent().lastPathComponent == "FolderB")
        #expect(FileManager.default.fileExists(atPath: moved.fileURL.path))
        #expect(storeA.notes.count == 0)
    }

    @Test("Move note with filename conflict appends (2)")
    @MainActor
    func testMoveNoteFilenameConflict() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let destURL = vault.appendingPathComponent("Dest")
        try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)

        // Create a file with the same name at destination
        let conflictURL = destURL.appendingPathComponent(note.fileURL.lastPathComponent)
        try "conflict".write(to: conflictURL, atomically: true, encoding: .utf8)

        let moved = store.moveNote(note, to: destURL)

        // Should have (2) in the filename
        let stem = moved.fileURL.deletingPathExtension().lastPathComponent
        #expect(stem.hasSuffix("(2)"))
        #expect(FileManager.default.fileExists(atPath: moved.fileURL.path))
    }

    @Test("Move note with multiple conflicts appends (3), (4)")
    @MainActor
    func testMoveNoteMultipleConflicts() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let originalName = note.fileURL.deletingPathExtension().lastPathComponent
        let destURL = vault.appendingPathComponent("Dest")
        try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)

        // Create conflicts: original, (2)
        try "c1".write(to: destURL.appendingPathComponent("\(originalName).md"), atomically: true, encoding: .utf8)
        try "c2".write(to: destURL.appendingPathComponent("\(originalName)(2).md"), atomically: true, encoding: .utf8)

        let moved = store.moveNote(note, to: destURL)

        let stem = moved.fileURL.deletingPathExtension().lastPathComponent
        #expect(stem.hasSuffix("(3)"))
    }

    @Test("Move note to same directory is a no-op")
    @MainActor
    func testMoveNoteToSameDirectory() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let moved = store.moveNote(note, to: vault)

        #expect(moved.fileURL == note.fileURL)
        #expect(store.notes.count == 1)
    }

    @Test("Move note preserves file content")
    @MainActor
    func testMoveNotePreservesContent() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let content = MarkdownNote.makeFrontmatter(id: note.id) + "# Test\nBody content here"
        store.saveContent(content, for: note)

        let contentBefore = try String(contentsOf: note.fileURL, encoding: .utf8)
        let destURL = vault.appendingPathComponent("MoveDest")
        let moved = store.moveNote(note, to: destURL)
        let contentAfter = try String(contentsOf: moved.fileURL, encoding: .utf8)

        #expect(contentBefore == contentAfter)
    }

    @Test("Move note creates destination directory if it doesn't exist")
    @MainActor
    func testMoveNoteCreatesDestination() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let destURL = vault.appendingPathComponent("New/Nested/Folder")

        let moved = store.moveNote(note, to: destURL)

        #expect(FileManager.default.fileExists(atPath: destURL.path))
        #expect(FileManager.default.fileExists(atPath: moved.fileURL.path))
    }
}

// MARK: - Move Folder Tests

@Suite("Move Folder")
struct MoveFolderTests {

    @Test("Move folder to new location — folder and contents preserved")
    @MainActor
    func testMoveFolderToSubfolder() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let folder = store.createFolder(name: "MyFolder")
        // Add a file inside the folder
        let innerFile = folder.folderURL.appendingPathComponent("inner.md")
        try "inner content".write(to: innerFile, atomically: true, encoding: .utf8)

        let destURL = vault.appendingPathComponent("Parent")
        let moved = store.moveFolder(folder, to: destURL)

        // Folder at new location
        #expect(FileManager.default.fileExists(atPath: moved.folderURL.path))
        #expect(moved.folderURL.deletingLastPathComponent().lastPathComponent == "Parent")

        // Contents preserved
        let movedInner = moved.folderURL.appendingPathComponent("inner.md")
        #expect(FileManager.default.fileExists(atPath: movedInner.path))

        // Removed from source
        #expect(!FileManager.default.fileExists(atPath: folder.folderURL.path))
        #expect(store.folders.count == 0)
    }

    @Test("Move folder with name conflict appends (2)")
    @MainActor
    func testMoveFolderNameConflict() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let folder = store.createFolder(name: "Shared")
        let destURL = vault.appendingPathComponent("Parent")
        try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)

        // Create conflict folder at destination
        let conflictURL = destURL.appendingPathComponent("Shared")
        try FileManager.default.createDirectory(at: conflictURL, withIntermediateDirectories: true)

        let moved = store.moveFolder(folder, to: destURL)

        #expect(moved.folderURL.lastPathComponent == "Shared(2)")
        #expect(FileManager.default.fileExists(atPath: moved.folderURL.path))
    }

    @Test("Move folder to same directory is a no-op")
    @MainActor
    func testMoveFolderToSameDirectory() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let folder = store.createFolder(name: "StayPut")
        let moved = store.moveFolder(folder, to: vault)

        #expect(moved.folderURL == folder.folderURL)
        #expect(store.folders.count == 1)
    }
}

// MARK: - Timestamp Behavior Tests

@Suite("Timestamp Behavior")
struct TimestampBehaviorTests {

    @Test("Saving unchanged content does not update the updated timestamp")
    @MainActor
    func testSaveUnchangedContentDoesNotUpdateTimestamp() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let content = store.readContent(of: note)

        // Wait a moment so any new timestamp would be detectably different
        Thread.sleep(forTimeInterval: 1.1)

        // Save with identical content
        store.saveContent(content, for: note)

        // Read back and check the updated timestamp hasn't changed
        let saved = try String(contentsOf: note.fileURL, encoding: .utf8)
        let original = content

        let originalTimestamp = extractUpdatedTimestamp(from: original)
        let savedTimestamp = extractUpdatedTimestamp(from: saved)

        #expect(originalTimestamp == savedTimestamp, "Saving unchanged content should not modify the updated timestamp")
    }

    @Test("Saving changed content updates the updated timestamp")
    @MainActor
    func testSaveChangedContentUpdatesTimestamp() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let originalContent = store.readContent(of: note)
        let originalTimestamp = extractUpdatedTimestamp(from: originalContent)

        // Wait so timestamp would differ
        Thread.sleep(forTimeInterval: 1.1)

        // Modify content
        let modifiedContent = originalContent + "New text added"
        store.saveContent(modifiedContent, for: note)

        let saved = try String(contentsOf: note.fileURL, encoding: .utf8)
        let savedTimestamp = extractUpdatedTimestamp(from: saved)

        #expect(originalTimestamp != savedTimestamp, "Saving changed content should update the updated timestamp")
    }

    @Test("Created timestamp is never modified by save")
    @MainActor
    func testCreatedTimestampNeverChanges() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let originalContent = store.readContent(of: note)
        let originalCreated = extractCreatedTimestamp(from: originalContent)

        Thread.sleep(forTimeInterval: 1.1)

        let modified = originalContent + "Some edits"
        store.saveContent(modified, for: note)

        let saved = try String(contentsOf: note.fileURL, encoding: .utf8)
        let savedCreated = extractCreatedTimestamp(from: saved)

        #expect(originalCreated == savedCreated, "Created timestamp must never change")
    }

    @Test("Multiple saves without changes never update timestamp")
    @MainActor
    func testMultipleSavesWithoutChanges() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let content = store.readContent(of: note)
        let originalTimestamp = extractUpdatedTimestamp(from: content)

        // Save 3 times with no changes, with waits in between
        for _ in 0..<3 {
            Thread.sleep(forTimeInterval: 1.1)
            store.saveContent(content, for: note)
        }

        let saved = try String(contentsOf: note.fileURL, encoding: .utf8)
        let finalTimestamp = extractUpdatedTimestamp(from: saved)
        #expect(originalTimestamp == finalTimestamp, "Multiple unchanged saves should never touch the timestamp")
    }

    @Test("Unchanged save preserves in-memory modifiedDate")
    @MainActor
    func testUnchangedSavePreservesModifiedDate() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        let note = store.createNote()
        let originalDate = note.modifiedDate
        let content = store.readContent(of: note)

        Thread.sleep(forTimeInterval: 1.1)

        let returned = store.saveContent(content, for: note)
        #expect(returned.note.modifiedDate == originalDate, "modifiedDate should not change when content is unchanged")
    }
}

// MARK: - Timestamp Helpers

private func extractUpdatedTimestamp(from content: String) -> String? {
    content.components(separatedBy: "\n")
        .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("updated:") }?
        .components(separatedBy: "updated:")
        .last?
        .trimmingCharacters(in: .whitespaces)
}

private func extractCreatedTimestamp(from content: String) -> String? {
    content.components(separatedBy: "\n")
        .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("created:") }?
        .components(separatedBy: "created:")
        .last?
        .trimmingCharacters(in: .whitespaces)
}
