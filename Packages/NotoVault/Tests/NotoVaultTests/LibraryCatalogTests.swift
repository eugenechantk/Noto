import Foundation
import Testing
@testable import NotoVault

struct LibraryCatalogTests {
    @Test func directorySummaryInflectsFolderAndNoteCountsIndependently() {
        for (folders, notes, expected) in [
            (0, 0, "0 folders · 0 notes"),
            (1, 1, "1 folder · 1 note"),
            (1, 2, "1 folder · 2 notes"),
            (2, 1, "2 folders · 1 note"),
            (2, 2, "2 folders · 2 notes")
        ] {
            #expect(LibraryCatalog.directorySummary(folderCount: folders, noteCount: notes) == expected)
        }
    }

    @Test func homeListsNestedRecentAndFoldersButHidesCaptures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["Projects/Noto", "Daily Notes", "inbox", "Attachments", ".hidden"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for (path, markdown, date) in [
            ("Projects/Noto/roadmap.md", "---\npinned: true\n---\n# Roadmap\nNext thing", 30.0),
            ("Projects/recent.md", "# Recent\nA useful preview", 20.0),
            ("root.md", "# Older\nOlder preview", 10.0),
            ("inbox/capture.md", "# Capture", 50.0),
            ("Attachments/hidden.md", "# Hidden", 60.0),
            (".hidden/hidden.md", "# Hidden", 60.0)
        ] {
            let url = root.appendingPathComponent(path)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: date)], ofItemAtPath: url.path)
        }
        let snapshot = try LibraryCatalog(vaultRootURL: root).load()
        #expect(snapshot.notes.map(\.note.title) == ["Roadmap", "Recent", "Older"])
        #expect(snapshot.pinned.map(\.folderPath) == ["Projects/Noto"])
        #expect(snapshot.recent().map(\.note.title) == ["Recent", "Older"])
        #expect(snapshot.recent(limit: 1).first?.preview == "A useful preview")
        #expect(snapshot.folders.map(\.name) == ["Daily Notes", "Projects"])
        #expect(snapshot.folders.first(where: { $0.name == "Projects" })?.folderCount == 1)
    }

    @Test func groupingUsesCalendarWeekAndSortsNamesNaturally() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18))!
        func note(_ title: String, daysAgo: Int) -> LibraryNote {
            LibraryNote(note: VaultNoteRecord(id: UUID(), fileURL: URL(fileURLWithPath: "/\(title).md"), title: title, modifiedDate: calendar.date(byAdding: .day, value: -daysAgo, to: now)!), folderPath: "", preview: "", isPinned: false)
        }
        let notes = [note("Note 10", daysAgo: 1), note("Note 2", daysAgo: 20)]
        #expect(LibraryCatalog.groups(notes, now: now, calendar: calendar).map(\.title) == ["This week", "Earlier"])
        #expect(LibraryCatalog.groups(notes, sort: .name).first?.notes.map(\.note.title) == ["Note 2", "Note 10"])
        #expect(LibraryCatalog.groups(notes, sort: .oldest).first?.notes.first?.note.title == "Note 2")
    }
}

extension LibraryCatalogTests {
    /// SC9 (noto2-library-cache): folder pages read their notes from the shared snapshot.
    @Test func snapshotListsNotesForExactlyOneDirectory() {
        let vault = URL(fileURLWithPath: "/tmp/LibraryVault", isDirectory: true)
        func note(_ path: String) -> LibraryNote {
            let url = vault.appendingPathComponent(path)
            return LibraryNote(
                note: VaultNoteRecord(id: VaultDirectoryLoader.stableID(for: url), fileURL: url, title: url.deletingPathExtension().lastPathComponent, modifiedDate: Date()),
                folderPath: (path as NSString).deletingLastPathComponent,
                preview: "",
                isPinned: false
            )
        }
        let snapshot = LibrarySnapshot(notes: [note("root.md"), note("Projects/plan.md"), note("Projects/Noto/roadmap.md")], folders: [])

        #expect(snapshot.notes(inDirectory: vault.appendingPathComponent("Projects", isDirectory: true)).map(\.note.title) == ["plan"])
        #expect(snapshot.notes(inDirectory: vault.appendingPathComponent("Projects")).map(\.note.title) == ["plan"])
        #expect(snapshot.notes(inDirectory: vault).map(\.note.title) == ["root"])
    }
}

/// SC11–SC15 (noto2-library-cache): a rescan lists every file with its date but reads
/// only notes that are new or changed since the last snapshot, with the plain reader.
extension LibraryCatalogTests {
    @Test func firstScanReadsEveryNoteWithThePlainReader() throws {
        let vault = try IncrementalVault()
        defer { vault.cleanUp() }
        let fileSystem = PreviewRecordingFileSystem()

        let snapshot = try LibraryCatalog(vaultRootURL: vault.root, fileSystem: fileSystem).load()

        #expect(snapshot.notes.count == 3)
        #expect(Set(fileSystem.previewReads) == Set(["a.md", "b.md", "Projects/c.md"]))
        #expect(fileSystem.coordinatedReads.isEmpty)
    }

    @Test func rescanReadsOnlyNewOrChangedNotes() throws {
        let vault = try IncrementalVault()
        defer { vault.cleanUp() }
        let first = try LibraryCatalog(vaultRootURL: vault.root).load()
        try vault.write("a.md", "# Alpha renamed\nNew body", minutesAgo: 1)
        try vault.write("Projects/d.md", "# Delta\nFresh", minutesAgo: 0)
        let fileSystem = PreviewRecordingFileSystem()

        let second = try LibraryCatalog(vaultRootURL: vault.root, fileSystem: fileSystem).load(previous: first)

        #expect(Set(fileSystem.previewReads) == Set(["a.md", "Projects/d.md"]))
        #expect(second.notes.map(\.note.title) == ["Delta", "Alpha renamed", "Bravo", "Charlie"])
    }

    @Test func unchangedRescanReadsNothing() throws {
        let vault = try IncrementalVault()
        defer { vault.cleanUp() }
        let first = try LibraryCatalog(vaultRootURL: vault.root).load()
        let fileSystem = PreviewRecordingFileSystem()

        let second = try LibraryCatalog(vaultRootURL: vault.root, fileSystem: fileSystem).load(previous: first)

        #expect(fileSystem.previewReads.isEmpty)
        #expect(second == first)
    }

    @Test func rescanDropsDeletedNotes() throws {
        let vault = try IncrementalVault()
        defer { vault.cleanUp() }
        let first = try LibraryCatalog(vaultRootURL: vault.root).load()
        try FileManager.default.removeItem(at: vault.root.appendingPathComponent("b.md"))

        let second = try LibraryCatalog(vaultRootURL: vault.root).load(previous: first)

        #expect(second.notes.map(\.note.title) == ["Alpha", "Charlie"])
    }

    @Test func pinAddedOutsideTheAppAppearsOnRescan() throws {
        let vault = try IncrementalVault()
        defer { vault.cleanUp() }
        let first = try LibraryCatalog(vaultRootURL: vault.root).load()
        #expect(first.pinned.isEmpty)
        try vault.write("Projects/c.md", "---\npinned: true\n---\n# Charlie\nPinned on the Mac", minutesAgo: 1)

        let second = try LibraryCatalog(vaultRootURL: vault.root).load(previous: first)

        #expect(second.pinned.map(\.note.title) == ["Charlie"])
    }

    @Test func offloadedNoteKeepsSavedDetailsAndIsReadOnceDownloaded() throws {
        let vault = try IncrementalVault()
        defer { vault.cleanUp() }
        try vault.write("b.md", "---\npinned: true\n---\n# Bravo\nSaved preview", minutesAgo: 20)
        let first = try LibraryCatalog(vaultRootURL: vault.root).load()
        // Changed on another device, and still offloaded on this one.
        try vault.write("b.md", "---\npinned: true\n---\n# Bravo v2\nNewer preview", minutesAgo: 1)
        let offloaded = PreviewRecordingFileSystem(offloaded: ["b.md"])

        let second = try LibraryCatalog(vaultRootURL: vault.root, fileSystem: offloaded).load(previous: first)
        let bravo = try #require(second.notes.first { $0.note.fileURL.lastPathComponent == "b.md" })
        #expect(bravo.note.title == "Bravo")
        #expect(bravo.preview == "Saved preview")
        #expect(bravo.isPinned)
        #expect(second.notes.first?.note.fileURL.lastPathComponent == "b.md") // sorted by its new date
        #expect(offloaded.coordinatedReads.isEmpty)

        // Once downloaded, the next rescan reads it even though its date did not change again.
        let downloaded = PreviewRecordingFileSystem()
        let third = try LibraryCatalog(vaultRootURL: vault.root, fileSystem: downloaded).load(previous: second)
        #expect(downloaded.previewReads == ["b.md"])
        #expect(third.notes.first?.note.title == "Bravo v2")
    }

    @Test func newOffloadedNoteShowsItsFilename() throws {
        let vault = try IncrementalVault()
        defer { vault.cleanUp() }
        try vault.write("Echo idea.md", "# Echo\nBody", minutesAgo: 0)

        let snapshot = try LibraryCatalog(vaultRootURL: vault.root, fileSystem: PreviewRecordingFileSystem(offloaded: ["Echo idea.md"])).load()

        #expect(snapshot.notes.first?.note.title == "Echo idea")
    }
}

/// A temp vault: a.md "Alpha" (10 min ago), b.md "Bravo" (20), Projects/c.md "Charlie" (30).
private struct IncrementalVault {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Incremental-" + UUID().uuidString, isDirectory: true)
    private let now = Date()

    init() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        try write("a.md", "# Alpha\nFirst", minutesAgo: 10)
        try write("b.md", "# Bravo\nSecond", minutesAgo: 20)
        try write("Projects/c.md", "# Charlie\nThird", minutesAgo: 30)
    }

    func write(_ path: String, _ markdown: String, minutesAgo: Double) throws {
        let url = root.appendingPathComponent(path)
        try markdown.write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-minutesAgo * 60)], ofItemAtPath: url.path)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

/// The real file system, recording reads by vault-relative path; `offloaded` notes
/// return nothing from the plain reader, the way iCloud placeholders do.
private final class PreviewRecordingFileSystem: VaultFileSystem, @unchecked Sendable {
    private let base = CoordinatedVaultFileSystem()
    private let lock = NSLock()
    private let offloaded: Set<String>
    private var previews: [String] = []
    private var coordinated: [String] = []

    init(offloaded: Set<String> = []) { self.offloaded = offloaded }

    var previewReads: [String] { lock.withLock { previews } }
    var coordinatedReads: [String] { lock.withLock { coordinated } }

    /// "a.md" for a root note, "Projects/c.md" for one in the fixture's one subfolder.
    private func name(_ url: URL) -> String {
        url.deletingLastPathComponent().lastPathComponent == "Projects" ? "Projects/" + url.lastPathComponent : url.lastPathComponent
    }

    func readLocalPreview(from url: URL, maxBytes: Int) -> Data? {
        lock.withLock { previews.append(name(url)) }
        return offloaded.contains(name(url)) ? nil : base.readLocalPreview(from: url, maxBytes: maxBytes)
    }
    func readPrefix(from url: URL, maxBytes: Int) -> Data? {
        lock.withLock { coordinated.append(name(url)) }
        return base.readPrefix(from: url, maxBytes: maxBytes)
    }
    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func isReadableFile(at url: URL) -> Bool { base.isReadableFile(at: url) }
    func readString(from url: URL) -> String? { base.readString(from: url) }
    func readData(from url: URL) -> Data? { base.readData(from: url) }
    func writeString(_ content: String, to url: URL) -> Bool { base.writeString(content, to: url) }
    func writeData(_ data: Data, to url: URL) -> Bool { base.writeData(data, to: url) }
    func delete(at url: URL) -> Bool { base.delete(at: url) }
    func move(from sourceURL: URL, to destinationURL: URL) -> Bool { base.move(from: sourceURL, to: destinationURL) }
    func createDirectory(at url: URL) -> Bool { base.createDirectory(at: url) }
    func isDownloaded(at url: URL) -> Bool { !offloaded.contains(name(url)) }
    func startDownloading(at url: URL) {}
}
