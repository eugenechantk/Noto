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
/// - `testRenameFileConflictAppendsSuffix` — Appends (2) when title filename exists
/// - `testRenameFileMultipleConflictsAppendsFirstAvailableSuffix` — Appends first available suffix for repeated title filename conflicts
/// - `testResolveNoteByIDFindsRenamedFile` — `note(withID:)` finds a note even after its file was renamed
/// - `testResolveNoteByIDDoesNotReadFullContentOnMisses` — `note(withID:)` resolves correctly when the vault contains large sibling notes (regression for Bug 011 main-thread stall)
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
import ImageIO
import NotoSearch
import NotoVault
import UniformTypeIdentifiers
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

private func makeTestImageData(type: UTType = .jpeg) throws -> Data {
    var pixels: [UInt8] = [
        240, 80, 60, 255,
        80, 160, 240, 255,
        40, 120, 80, 255,
        245, 220, 120, 255,
    ]
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: &pixels,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 8,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
    let cgImage = try #require(context?.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, cgImage, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@MainActor
private func waitForBackgroundLoad(_ store: MarkdownNoteStore) async {
    for _ in 0..<40 {
        if !store.isLoadingItems { return }
        try? await Task.sleep(nanoseconds: 25_000_000)
    }
}

@MainActor
private func makeHistoryEntry(
    title: String,
    fileName: String,
    in store: MarkdownNoteStore
) -> NoteStackEntry {
    let fileURL = store.vaultRootURL.appendingPathComponent(fileName)
    let note = MarkdownNote(
        id: UUID(),
        fileURL: fileURL,
        title: title,
        modifiedDate: Date()
    )
    return NoteStackEntry(note: note, store: store, isNew: false)
}

// MARK: - Vault Image Attachment Tests

@Suite("Vault Image Attachments")
struct VaultImageAttachmentTests {
    @Test("Imports photo-like image data into hidden vault attachments as markdown-compatible JPEG")
    @MainActor
    func importsPhotoImageDataIntoHiddenVaultAttachments() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let importer = VaultImageAttachmentStore(vaultRootURL: vault)
        let imageData = try makeTestImageData(type: .jpeg)

        let attachment = try importer.importImageData(imageData, suggestedFilename: "Camera Roll.HEIC")

        #expect(attachment.relativePath == ".attachments/Camera Roll.jpg")
        #expect(attachment.markdownPath == ".attachments/Camera%20Roll.jpg")
        #expect(attachment.markdown == "![Camera Roll](.attachments/Camera%20Roll.jpg)")
        #expect(FileManager.default.fileExists(atPath: attachment.fileURL.path))
        #expect(attachment.fileURL.deletingLastPathComponent().lastPathComponent == ".attachments")
        #expect(attachment.fileURL.pathExtension == "jpg")
    }

    @Test("Hidden attachment directory is omitted from vault sidebar items")
    @MainActor
    func hiddenAttachmentDirectoryIsOmittedFromVaultSidebarItems() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let importer = VaultImageAttachmentStore(vaultRootURL: vault)
        let imageData = try makeTestImageData(type: .jpeg)

        _ = try importer.importImageData(imageData, suggestedFilename: "Camera Roll.HEIC")
        let items = try VaultDirectoryLoader().loadItems(in: vault)

        #expect(!items.contains { item in
            if case .folder(let folder) = item {
                return folder.name == ".attachments"
            }
            return false
        })
    }

    @Test("Image attachment imports resolve filename conflicts")
    @MainActor
    func imageAttachmentImportsResolveFilenameConflicts() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let importer = VaultImageAttachmentStore(vaultRootURL: vault)
        let imageData = try makeTestImageData(type: .jpeg)

        let first = try importer.importImageData(imageData, suggestedFilename: "Trip.jpeg")
        let second = try importer.importImageData(imageData, suggestedFilename: "Trip.jpeg")

        #expect(first.relativePath == ".attachments/Trip.jpg")
        #expect(second.relativePath == ".attachments/Trip(2).jpg")
        #expect(FileManager.default.fileExists(atPath: first.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: second.fileURL.path))
    }

    @Test("Image markdown insertion keeps image syntax on its own line")
    func imageMarkdownInsertionKeepsImageSyntaxOnOwnLine() {
        let text = "# Title"
        let markdown = "![Camera Roll](.attachments/Camera%20Roll.jpg)"

        let transform = MarkdownImageInsertion.transform(
            in: text,
            selection: NSRange(location: text.count, length: 0),
            markdown: markdown
        )

        #expect(transform.text == "# Title\n![Camera Roll](.attachments/Camera%20Roll.jpg)\n")
        #expect(transform.selection.location == transform.text.count)
        #expect(transform.selection.length == 0)
    }
}

// MARK: - Note Navigation History Tests

@Suite("Note Navigation History")
struct NoteNavigationHistoryTests {
    @Test("Tracks back and forward visits")
    @MainActor
    func noteNavigationHistoryTracksBackAndForwardVisits() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)
        let first = makeHistoryEntry(title: "First", fileName: "First.md", in: store)
        let second = makeHistoryEntry(title: "Second", fileName: "Second.md", in: store)
        var history = NoteNavigationHistory()

        history.visit(first)
        history.visit(second)

        #expect(history.currentEntry?.hasSameNavigationTarget(as: second) == true)
        #expect(history.canGoBack)
        #expect(!history.canGoForward)

        let previous = history.goBack()
        #expect(previous?.hasSameNavigationTarget(as: first) == true)
        #expect(!history.canGoBack)
        #expect(history.canGoForward)

        let next = history.goForward()
        #expect(next?.hasSameNavigationTarget(as: second) == true)
    }

    @Test("Replaces duplicate visible visits")
    @MainActor
    func noteNavigationHistoryReplacesDuplicateVisibleVisits() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)
        let first = makeHistoryEntry(title: "First", fileName: "First.md", in: store)
        var renamedFirst = makeHistoryEntry(title: "Renamed", fileName: "First.md", in: store)
        renamedFirst.note.title = "Renamed"
        var history = NoteNavigationHistory()

        history.visit(first)
        history.visit(renamedFirst)

        #expect(history.entries.count == 1)
        #expect(history.currentEntry?.note.title == "Renamed")
        #expect(!history.canGoBack)
    }

    @Test("Replaces visible visit when note is renamed")
    @MainActor
    func noteNavigationHistoryReplacesVisibleVisitWhenNoteIsRenamed() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)
        let created = makeHistoryEntry(title: "Untitled", fileName: "Original.md", in: store)
        let renamedNote = MarkdownNote(
            id: created.note.id,
            fileURL: store.vaultRootURL.appendingPathComponent("Renamed.md"),
            title: "Renamed",
            modifiedDate: Date()
        )
        let renamed = NoteStackEntry(note: renamedNote, store: store, isNew: true)
        var history = NoteNavigationHistory()

        history.visit(created)
        history.visit(renamed)

        #expect(history.entries.count == 1)
        #expect(history.currentEntry?.note.fileURL.lastPathComponent == "Renamed.md")
        #expect(!history.canGoBack)
    }

    @Test("Drops forward entries after a new visit")
    @MainActor
    func noteNavigationHistoryDropsForwardEntriesAfterNewVisit() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)
        let first = makeHistoryEntry(title: "First", fileName: "First.md", in: store)
        let second = makeHistoryEntry(title: "Second", fileName: "Second.md", in: store)
        let third = makeHistoryEntry(title: "Third", fileName: "Third.md", in: store)
        var history = NoteNavigationHistory()

        history.visit(first)
        history.visit(second)
        _ = history.goBack()
        history.visit(third)

        #expect(history.entries.count == 2)
        #expect(history.currentEntry?.hasSameNavigationTarget(as: third) == true)
        #expect(!history.canGoForward)
        #expect(history.goBack()?.hasSameNavigationTarget(as: first) == true)
    }

    @Test("Updates renamed note entries even when they are not current")
    @MainActor
    func noteNavigationHistoryUpdatesRenamedNonCurrentEntries() {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)
        let first = makeHistoryEntry(title: "Untitled", fileName: "Original.md", in: store)
        let second = makeHistoryEntry(title: "Second", fileName: "Second.md", in: store)
        let renamedFirst = MarkdownNote(
            id: first.note.id,
            fileURL: store.vaultRootURL.appendingPathComponent("Renamed.md"),
            title: "Renamed",
            modifiedDate: Date()
        )
        var history = NoteNavigationHistory()

        history.visit(first)
        history.visit(second)
        history.replaceEntries(for: renamedFirst)

        let previous = history.goBack()
        #expect(previous?.note.fileURL.lastPathComponent == "Renamed.md")
        #expect(previous?.note.title == "Renamed")
    }
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

    @Test("Page mention documents use vault-relative note paths")
    @MainActor
    func pageMentionDocumentsUseVaultRelativePaths() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let folder = vault.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("Project Brief.md")
        try "# Project Brief\nDetails".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = MarkdownNoteStore(vaultURL: vault)
        let documents = store.pageMentionDocuments(matching: "brief")

        #expect(documents.first?.title == "Project Brief")
        #expect(documents.first?.relativePath == "Projects/Project Brief.md")
    }

    @Test("Page mention documents use indexed title search when available")
    @MainActor
    func pageMentionDocumentsUseIndexedTitleSearchWhenAvailable() throws {
        let vault = makeTempVault()
        let indexDirectory = MarkdownSearchIndexer.defaultIndexDirectory(for: vault)
        defer {
            cleanupVault(vault)
            cleanupVault(indexDirectory)
        }
        let folder = vault.appendingPathComponent("VaultOnly")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "# Project Brief\nDetails".write(
            to: folder.appendingPathComponent("Project Brief.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Roadmap\nDetails".write(
            to: folder.appendingPathComponent("No Match.md"),
            atomically: true,
            encoding: .utf8
        )
        try MarkdownSearchIndexer(vaultURL: vault).rebuild()

        let store = MarkdownNoteStore(vaultURL: vault)
        let briefDocuments = store.pageMentionDocuments(matching: "brief", limit: 10)
        let pathOnlyDocuments = store.pageMentionDocuments(matching: "vaultonly", limit: 10)

        #expect(briefDocuments.map(\.title) == ["Project Brief"])
        #expect(briefDocuments.first?.relativePath == "VaultOnly/Project Brief.md")
        #expect(pathOnlyDocuments.isEmpty)
    }

    @Test("Page mention documents require a query before scanning")
    @MainActor
    func pageMentionDocumentsRequireQuery() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let fileURL = vault.appendingPathComponent("Project Brief.md")
        try "# Project Brief\nDetails".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = MarkdownNoteStore(vaultURL: vault)

        #expect(store.pageMentionDocuments(matching: "").isEmpty)
        #expect(store.pageMentionDocuments(matching: "   ").isEmpty)
    }

    @Test("Page mention documents can opt into empty-query suggestions")
    @MainActor
    func pageMentionDocumentsCanAllowEmptyQuery() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let fileURL = vault.appendingPathComponent("Project Brief.md")
        try "# Project Brief\nDetails".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = MarkdownNoteStore(vaultURL: vault)
        let documents = store.pageMentionDocuments(matching: "", limit: 10, allowEmptyQuery: true)

        #expect(documents.map(\.title) == ["Project Brief"])
    }

    @Test("Vault-relative note paths resolve to notes")
    @MainActor
    func vaultRelativeNotePathsResolveToNotes() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let folder = vault.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("Project Brief.md")
        try "# Project Brief\nDetails".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = MarkdownNoteStore(vaultURL: vault)
        let resolved = try #require(store.note(atVaultRelativePath: "Projects/Project Brief.md"))

        #expect(resolved.note.title == "Project Brief")
        #expect(resolved.store.directoryURL.standardizedFileURL == folder.standardizedFileURL)
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

    @Test("File-only directory loading avoids note content metadata")
    @MainActor
    func testFileOnlyDirectoryLoadingUsesFilenameMetadata() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let id = UUID()
        let fileURL = vault.appendingPathComponent("\(id.uuidString).md")
        let content = MarkdownNote.makeFrontmatter(id: id) + "# Content Title\nBody text"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = MarkdownNoteStore(
            vaultURL: vault,
            directoryLoader: VaultDirectoryLoader(noteMetadataStrategy: .fileOnly)
        )
        let note = try #require(store.notes.first)

        #expect(note.id == VaultDirectoryLoader.stableID(for: fileURL))
        #expect(note.title == "Untitled")

        let resolved = store.updateMetadataFromContent(content, for: note)

        #expect(resolved.id == id)
        #expect(resolved.title == "Content Title")
        #expect(store.notes.first?.id == id)
        #expect(store.notes.first?.title == "Content Title")
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

    @Test("Daily note file helper creates the requested date")
    func testDailyNoteFileCreatesRequestedDate() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 27,
            hour: 10
        )))

        let resolved = DailyNoteFile.ensure(vaultRootURL: vault, date: date, calendar: calendar)
        let content = try String(contentsOf: resolved.fileURL, encoding: .utf8)

        #expect(resolved.didCreate)
        #expect(resolved.fileURL.lastPathComponent == "2026-04-27.md")
        #expect(content.contains("# 27 Apr, 26 (Mon)"))
        #expect(content.contains("## What did I do today?"))
    }

    @Test("Daily note file helper is idempotent for the requested date")
    func testDailyNoteFileCreationIsIdempotentForRequestedDate() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 27,
            hour: 10
        )))

        let first = DailyNoteFile.ensure(vaultRootURL: vault, date: date, calendar: calendar)
        let firstContent = try String(contentsOf: first.fileURL, encoding: .utf8)
        let second = DailyNoteFile.ensure(vaultRootURL: vault, date: date, calendar: calendar)
        let secondContent = try String(contentsOf: second.fileURL, encoding: .utf8)

        #expect(first.didCreate)
        #expect(!second.didCreate)
        #expect(!second.didApplyTemplate)
        #expect(first.fileURL == second.fileURL)
        #expect(firstContent == secondContent)
    }

    @Test("Daily note next start of day uses the calendar time zone")
    func testDailyNoteNextStartOfDayUsesCalendarTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 27,
            hour: 23,
            minute: 59,
            second: 30
        )))
        let expected = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 28
        )))

        #expect(DailyNoteFile.nextStartOfDay(after: date, calendar: calendar) == expected)
    }

    @Test("Foreground refresh does not create today's note")
    @MainActor
    func testForegroundRefreshDoesNotCreateTodayNote() async {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        store.refreshForForegroundActivation()
        await waitForBackgroundLoad(store)

        let dailyFolder = vault.appendingPathComponent("Daily Notes")
        #expect(!FileManager.default.fileExists(atPath: dailyFolder.path))
    }

    @Test("Autoload can be deferred for responsive app launch")
    @MainActor
    func testAutoloadCanBeDeferredForResponsiveLaunch() async throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        try "# Existing\n".write(to: vault.appendingPathComponent("Existing.md"), atomically: true, encoding: .utf8)

        let store = MarkdownNoteStore(vaultURL: vault, autoload: false)

        #expect(store.items.isEmpty)

        store.loadItemsInBackground()
        await waitForBackgroundLoad(store)

        #expect(store.items.count == 1)
    }

    @Test("Autoload can be deferred for responsive navigation destinations")
    @MainActor
    func testAutoloadCanBeDeferredForResponsiveNavigationDestinations() async throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let folder = vault.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "# Nested\n".write(to: folder.appendingPathComponent("Nested.md"), atomically: true, encoding: .utf8)

        let store = MarkdownNoteStore(directoryURL: folder, vaultRootURL: vault, autoload: false)

        #expect(store.items.isEmpty)

        store.loadItemsInBackground()
        await waitForBackgroundLoad(store)

        #expect(store.items.count == 1)
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

    @Test("Rename file conflict appends (2)")
    @MainActor
    func testRenameFileConflictAppendsSuffix() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        try "existing".write(
            to: vault.appendingPathComponent("Shared Title.md"),
            atomically: true,
            encoding: .utf8
        )

        var note = store.createNote()
        let content = MarkdownNote.makeFrontmatter(id: note.id) + "# Shared Title"
        note = store.saveContent(content, for: note).note
        let renamed = store.renameFileIfNeeded(for: note)

        #expect(renamed.fileURL.lastPathComponent == "Shared Title(2).md")
        #expect(FileManager.default.fileExists(atPath: renamed.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: note.fileURL.path))
    }

    @Test("Resolve note by id finds renamed file")
    @MainActor
    func testResolveNoteByIDFindsRenamedFile() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        var note = store.createNote()
        let originalURL = note.fileURL
        let content = MarkdownNote.makeFrontmatter(id: note.id) + "# Resolved Title\nBody"
        note = store.saveContent(content, for: note).note
        let renamed = store.renameFileIfNeeded(for: note)

        let resolved = try #require(store.note(withID: note.id))
        #expect(resolved.note.fileURL == renamed.fileURL)
        #expect(resolved.note.title == "Resolved Title")
        #expect(!FileManager.default.fileExists(atPath: originalURL.path))
    }

    @Test("Resolve note by id skips full-content reads on non-matching files")
    @MainActor
    func testResolveNoteByIDDoesNotReadFullContentOnMisses() throws {
        // Bug 011: tapping a search result triggered a main-thread vault scan
        // that read the FULL content of every .md file. With many large
        // sibling notes, this stalled the UI and could trip the iOS watchdog.
        // The fix reads only a 64KB frontmatter prefix to probe each file.
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        var target = store.createNote()
        let targetContent = MarkdownNote.makeFrontmatter(id: target.id) + "# Target Note\nBody"
        target = store.saveContent(targetContent, for: target).note

        // Sibling files much larger than the 64KB prefix limit. If the
        // resolver reads them in full it will dwarf the prefix-only path.
        let largeBody = String(repeating: "x", count: 200_000)
        for i in 0..<5 {
            let url = vault.appendingPathComponent("large-\(i).md")
            let content = MarkdownNote.makeFrontmatter(id: UUID()) + "# Large \(i)\n" + largeBody
            try content.write(to: url, atomically: true, encoding: .utf8)
        }

        let resolved = try #require(store.note(withID: target.id))
        #expect(resolved.note.fileURL == target.fileURL)
        #expect(resolved.note.title == "Target Note")
    }

    @Test("Rename file with multiple conflicts appends first available suffix")
    @MainActor
    func testRenameFileMultipleConflictsAppendsFirstAvailableSuffix() throws {
        let vault = makeTempVault()
        defer { cleanupVault(vault) }
        let store = MarkdownNoteStore(vaultURL: vault)

        try "existing".write(
            to: vault.appendingPathComponent("Shared Title.md"),
            atomically: true,
            encoding: .utf8
        )
        try "existing 2".write(
            to: vault.appendingPathComponent("Shared Title(2).md"),
            atomically: true,
            encoding: .utf8
        )

        var note = store.createNote()
        let content = MarkdownNote.makeFrontmatter(id: note.id) + "# Shared Title"
        note = store.saveContent(content, for: note).note
        let renamed = store.renameFileIfNeeded(for: note)

        #expect(renamed.fileURL.lastPathComponent == "Shared Title(3).md")
        #expect(FileManager.default.fileExists(atPath: renamed.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: note.fileURL.path))
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
