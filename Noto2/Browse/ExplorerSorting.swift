import Foundation

/// Ordering for every Browse directory: folders first (by name), then notes by
/// most-recently edited. Equal-date notes use natural title/path tie-breakers.
/// Pure.
enum ExplorerSorting {
    static func sorted(_ items: [DirectoryItem]) -> [DirectoryItem] {
        let folders = items.compactMap { item -> NotoFolder? in
            if case .folder(let folder) = item { return folder }
            return nil
        }
        let notes = items.compactMap { item -> MarkdownNote? in
            if case .note(let note) = item { return note }
            return nil
        }
        let sortedFolders = folders.sorted { compare($0.name, $1.name) }
        let sortedNotes = notes.sorted(by: notesAreOrdered)
        return sortedFolders.map(DirectoryItem.folder) + sortedNotes.map(DirectoryItem.note)
    }

    static func displayTitle(_ note: MarkdownNote) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? note.fileURL.deletingPathExtension().lastPathComponent : title
    }

    private static func compare(_ lhs: String, _ rhs: String) -> Bool {
        let comparison = lhs.localizedStandardCompare(rhs)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhs < rhs
    }

    private static func notesAreOrdered(_ lhs: MarkdownNote, _ rhs: MarkdownNote) -> Bool {
        if lhs.modifiedDate != rhs.modifiedDate {
            return lhs.modifiedDate > rhs.modifiedDate
        }

        let lhsTitle = displayTitle(lhs)
        let rhsTitle = displayTitle(rhs)
        let titleComparison = lhsTitle.localizedStandardCompare(rhsTitle)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        let lhsPath = lhs.fileURL.standardizedFileURL.path
        let rhsPath = rhs.fileURL.standardizedFileURL.path
        return compare(lhsPath, rhsPath)
    }
}
