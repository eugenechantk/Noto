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
