import Foundation
import Testing
@testable import Noto2

/// Test case index
/// 1. foldersFirstThenNotesByMostRecentlyEdited — folders precede notes; folders sort by name and notes by modified date descending
/// 2. equalDatesUseTitleThenPath — equal-date pages have deterministic natural title/path tie-breakers
/// 3. untitledNotesFallBackToFilename — an empty title displays and tie-breaks by its filename
/// 4. inputOrderDoesNotAffectResult — reversing the source items cannot reorder equal-date pages
struct ExplorerSortingTests {
    private let root = URL(fileURLWithPath: "/tmp/vault", isDirectory: true)
    private let older = Date(timeIntervalSince1970: 100)
    private let middle = Date(timeIntervalSince1970: 200)
    private let newer = Date(timeIntervalSince1970: 300)

    private func folder(_ name: String) -> DirectoryItem {
        .folder(NotoFolder(id: UUID(), folderURL: root.appendingPathComponent(name), name: name, modifiedDate: Date(), folderCount: 0, itemCount: 0))
    }

    private func note(_ title: String, file: String? = nil, modifiedDate: Date) -> DirectoryItem {
        .note(MarkdownNote(
            id: UUID(),
            fileURL: root.appendingPathComponent("\(file ?? title).md"),
            title: title,
            modifiedDate: modifiedDate
        ))
    }

    private func labels(_ items: [DirectoryItem]) -> [String] {
        items.map { item in
            switch item {
            case .folder(let f): return "D:" + f.name
            case .note(let n): return "N:" + ExplorerSorting.displayTitle(n)
            }
        }
    }

    @Test func foldersFirstThenNotesByMostRecentlyEdited() {
        let items = [
            note("Alphabetically First", modifiedDate: older),
            folder("Projects"),
            note("Newest", modifiedDate: newer),
            folder("archive"),
            note("Middle", modifiedDate: middle)
        ]

        #expect(labels(ExplorerSorting.sorted(items)) == [
            "D:archive",
            "D:Projects",
            "N:Newest",
            "N:Middle",
            "N:Alphabetically First"
        ])
    }

    @Test func equalDatesUseTitleThenPath() {
        let items = [
            note("note 10", modifiedDate: middle),
            note("Same", file: "Same B", modifiedDate: middle),
            note("note 2", modifiedDate: middle),
            note("Same", file: "Same A", modifiedDate: middle)
        ]

        let paths = ExplorerSorting.sorted(items).compactMap { item -> String? in
            guard case .note(let note) = item else { return nil }
            return note.fileURL.lastPathComponent
        }
        #expect(paths == ["note 2.md", "note 10.md", "Same A.md", "Same B.md"])
    }

    @Test func untitledNotesFallBackToFilename() {
        let items = [
            note("", file: "2026-08-23-abcd1234", modifiedDate: older),
            note("Alpha", modifiedDate: older)
        ]
        #expect(labels(ExplorerSorting.sorted(items)) == ["N:2026-08-23-abcd1234", "N:Alpha"])
    }

    @Test func inputOrderDoesNotAffectResult() {
        let items = [
            note("note 10", modifiedDate: newer),
            note("note 2", modifiedDate: newer),
            note("Older", modifiedDate: older)
        ]

        #expect(labels(ExplorerSorting.sorted(items)) == labels(ExplorerSorting.sorted(Array(items.reversed()))))
    }
}
