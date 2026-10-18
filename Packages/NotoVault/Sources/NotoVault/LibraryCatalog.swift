import Foundation

public struct LibraryNote: Identifiable, Equatable, Sendable {
    public let note: VaultNoteRecord
    public let folderPath: String
    public let preview: String
    public let isPinned: Bool
    public var id: UUID { note.id }
}

public struct LibrarySnapshot: Sendable {
    public let notes: [LibraryNote]
    public let folders: [FolderSummary]
    public var pinned: [LibraryNote] {
        notes.filter(\.isPinned).sorted { LibraryCatalog.titleOrder($0.note, $1.note) }
    }
    /// Pinned notes already have their own section, so Recent avoids duplicates.
    public func recent(limit: Int = 7) -> [LibraryNote] { Array(notes.filter { !$0.isPinned }.prefix(max(0, limit))) }
}

public enum LibraryNoteSort: String, CaseIterable, Sendable {
    case recent = "Recent"
    case name = "Name"
    case oldest = "Oldest"
}

public struct LibraryNoteGroup: Identifiable, Sendable {
    public let title: String
    public let notes: [LibraryNote]
    public var id: String { title }
}

/// Read-only filesystem catalog for Library. It stays separate from the search index
/// so a newly saved or pinned note appears even while indexing is in progress.
public struct LibraryCatalog: Sendable {
    public let vaultRootURL: URL
    private let fileSystem: any VaultFileSystem

    public init(vaultRootURL: URL, fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem()) {
        self.vaultRootURL = vaultRootURL.standardizedFileURL
        self.fileSystem = fileSystem
    }

    public static func directorySummary(folderCount: Int, noteCount: Int) -> String {
        let folders = "\(folderCount) \(folderCount == 1 ? "folder" : "folders")"
        let notes = "\(noteCount) \(noteCount == 1 ? "note" : "notes")"
        return "\(folders) · \(notes)"
    }

    public func load() throws -> LibrarySnapshot {
        let loader = VaultDirectoryLoader(noteMetadataStrategy: .fileOnly)
        let rootItems = try loader.loadItems(in: vaultRootURL)
        var notes: [LibraryNote] = []
        func visit(_ directory: URL) throws {
            for item in try loader.loadItems(in: directory) {
                switch item {
                case .folder(let folder):
                    guard Self.isVisible(folder.folderURL, in: vaultRootURL) else { continue }
                    let isSymbolicLink = (try? folder.folderURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
                    if !isSymbolicLink { try visit(folder.folderURL) }
                case .note(let summary):
                    guard Self.isVisible(summary.fileURL, in: vaultRootURL) else { continue }
                    let markdown = fileSystem.readPrefix(from: summary.fileURL, maxBytes: 64 * 1024)
                        .map { String(decoding: $0, as: UTF8.self) } ?? ""
                    let record = VaultNoteRecord(
                        id: VaultMarkdown.idFromFrontmatter(markdown) ?? summary.id,
                        fileURL: summary.fileURL,
                        title: VaultMarkdown.displayTitle(for: summary.fileURL, content: markdown),
                        modifiedDate: summary.modifiedDate
                    )
                    let relative = VaultPathResolver(vaultRootURL: vaultRootURL).relativePath(for: summary.fileURL) ?? summary.fileURL.lastPathComponent
                    let folder = (relative as NSString).deletingLastPathComponent
                    let bodyLines = VaultMarkdown.stripFrontmatter(markdown).split(whereSeparator: \.isNewline)
                    notes.append(LibraryNote(note: record, folderPath: folder, preview: bodyLines.dropFirst().first.map(String.init) ?? "", isPinned: NotePinning.isPinned(in: markdown)))
                }
            }
        }
        try visit(vaultRootURL)
        notes.sort {
            $0.note.modifiedDate == $1.note.modifiedDate ? Self.titleOrder($0.note, $1.note) : $0.note.modifiedDate > $1.note.modifiedDate
        }
        let folders = rootItems.compactMap { item -> FolderSummary? in
            guard case .folder(let folder) = item, Self.isVisible(folder.folderURL, in: vaultRootURL) else { return nil }
            return folder
        }
        return LibrarySnapshot(notes: notes, folders: folders)
    }

    public static func groups(_ notes: [LibraryNote], sort: LibraryNoteSort = .recent, now: Date = Date(), calendar: Calendar = .current) -> [LibraryNoteGroup] {
        let ordered = notes.sorted {
            if sort == .name { return titleOrder($0.note, $1.note) }
            if $0.note.modifiedDate == $1.note.modifiedDate { return titleOrder($0.note, $1.note) }
            return sort == .oldest ? $0.note.modifiedDate < $1.note.modifiedDate : $0.note.modifiedDate > $1.note.modifiedDate
        }
        guard sort == .recent else { return ordered.isEmpty ? [] : [LibraryNoteGroup(title: "Notes", notes: ordered)] }
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let groups = [
            LibraryNoteGroup(title: "This week", notes: ordered.filter { $0.note.modifiedDate >= start }),
            LibraryNoteGroup(title: "Earlier", notes: ordered.filter { $0.note.modifiedDate < start })
        ]
        return groups.filter { !$0.notes.isEmpty }
    }

    public static func isVisible(_ url: URL, in vaultRootURL: URL) -> Bool {
        guard let path = VaultPathResolver(vaultRootURL: vaultRootURL).relativePath(for: url) else { return false }
        let components = path.split(separator: "/")
        return components.first?.lowercased() != "inbox" && !components.contains(where: { $0.hasPrefix(".") || $0 == "Attachments" })
    }

    static func titleOrder(_ lhs: VaultNoteRecord, _ rhs: VaultNoteRecord) -> Bool {
        let result = lhs.title.localizedStandardCompare(rhs.title)
        return result == .orderedSame ? lhs.fileURL.path < rhs.fileURL.path : result == .orderedAscending
    }
}
