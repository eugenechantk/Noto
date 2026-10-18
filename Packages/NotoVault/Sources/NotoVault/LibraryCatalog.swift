import Foundation

public struct LibraryNote: Identifiable, Equatable, Sendable, Codable {
    public let note: VaultNoteRecord
    public let folderPath: String
    public let preview: String
    public let isPinned: Bool
    /// The title, preview and pin come from an older version of the file, because
    /// it was offloaded to iCloud when scanned. The next scan reads it again.
    public var isStale = false
    public var id: UUID { note.id }
    /// A raw capture in `inbox/`. Library lists it in the inbox folder, but the
    /// Recent lists show filed notes; the Inbox tab is where captures are reviewed.
    public var isCapture: Bool { folderPath.split(separator: "/").first?.lowercased() == "inbox" }
}

extension LibraryNote {
    /// The saved details of a note that changed while offloaded: sorted by its new
    /// date, but marked stale so the next scan reads it once it is downloaded.
    func offloaded(modifiedDate: Date) -> LibraryNote {
        var copy = LibraryNote(
            note: VaultNoteRecord(id: note.id, fileURL: note.fileURL, title: note.title, modifiedDate: modifiedDate),
            folderPath: folderPath,
            preview: preview,
            isPinned: isPinned
        )
        copy.isStale = true
        return copy
    }
}

public struct LibrarySnapshot: Sendable, Equatable, Codable {
    public let notes: [LibraryNote]
    public let folders: [FolderSummary]
    public var pinned: [LibraryNote] {
        notes.filter(\.isPinned).sorted { LibraryCatalog.titleOrder($0.note, $1.note) }
    }
    /// Every note except raw captures, newest first.
    public var filedNotes: [LibraryNote] { notes.filter { !$0.isCapture } }
    /// Pinned notes already have their own section, so Recent avoids duplicates.
    public func recent(limit: Int = 7) -> [LibraryNote] { Array(filedNotes.filter { !$0.isPinned }.prefix(max(0, limit))) }
    /// The notes directly inside `directoryURL` (not its subfolders), for a folder page.
    public func notes(inDirectory directoryURL: URL) -> [LibraryNote] {
        let directory = directoryURL.standardizedFileURL.path
        return notes.filter { $0.note.fileURL.deletingLastPathComponent().standardizedFileURL.path == directory }
    }
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

    /// Lists every visible note with its modified date, and reads only the notes that
    /// are new or changed since `previous` (all of them when there is none). Reads use
    /// the plain local reader: an offloaded iCloud note is never downloaded just to be
    /// listed; it keeps what `previous` knew, or shows its filename.
    public func load(previous: LibrarySnapshot? = nil) throws -> LibrarySnapshot {
        let loader = VaultDirectoryLoader(noteMetadataStrategy: .fileOnly)
        let rootItems = try loader.loadItems(in: vaultRootURL)
        let saved = Dictionary((previous?.notes ?? []).map { ($0.note.fileURL.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
        var notes: [LibraryNote] = []
        // A raw listing with prefetched dates: an unchanged note costs one lookup, so
        // full details (stable id, title, preview) are built only for notes read now.
        // Hidden, inbox and Attachments folders are skipped whole, so their notes
        // never need a per-note visibility check.
        // Never prefetch `ubiquitousItemDownloadingStatusKey` here: it costs a
        // file-provider round trip per file. The reader checks offloading itself.
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        func visit(_ directory: URL) throws {
            for child in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
                let values = try? child.resourceValues(forKeys: Set(keys))
                let url = child.standardizedFileURL
                if values?.isDirectory == true {
                    guard Self.isVisible(url, in: vaultRootURL), values?.isSymbolicLink != true else { continue }
                    try visit(url)
                    continue
                }
                guard url.pathExtension == "md" else { continue }
                let modifiedDate = values?.contentModificationDate ?? .distantPast
                let earlier = saved[url.path]
                if let earlier, !earlier.isStale, Self.sameDate(earlier.note.modifiedDate, modifiedDate) {
                    notes.append(earlier)
                    continue
                }
                let summary = NoteSummary(id: VaultDirectoryLoader.stableID(for: url), fileURL: url, title: "", modifiedDate: modifiedDate)
                if let data = fileSystem.readLocalPreview(from: url, maxBytes: 64 * 1024) {
                    notes.append(entry(for: summary, markdown: String(decoding: data, as: UTF8.self)))
                } else if let earlier {
                    notes.append(earlier.offloaded(modifiedDate: modifiedDate))
                } else {
                    var placeholder = entry(for: summary, markdown: "")
                    placeholder.isStale = true
                    notes.append(placeholder)
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

    private func entry(for summary: NoteSummary, markdown: String) -> LibraryNote {
        let record = VaultNoteRecord(
            id: VaultMarkdown.idFromFrontmatter(markdown) ?? summary.id,
            fileURL: summary.fileURL,
            title: VaultMarkdown.displayTitle(for: summary.fileURL, content: markdown),
            modifiedDate: summary.modifiedDate
        )
        let relative = VaultPathResolver(vaultRootURL: vaultRootURL).relativePath(for: summary.fileURL) ?? summary.fileURL.lastPathComponent
        let folder = (relative as NSString).deletingLastPathComponent
        // Only the title line and the preview line are needed; splitting the whole
        // 64 KB prefix into lines took half the first scan on a real vault.
        let bodyLines = VaultMarkdown.stripFrontmatter(markdown).split(maxSplits: 2, whereSeparator: \.isNewline)
        return LibraryNote(note: record, folderPath: folder, preview: bodyLines.dropFirst().first.map(String.init) ?? "", isPinned: NotePinning.isPinned(in: markdown))
    }

    /// Dates survive the cache as Doubles; allow for rounding.
    private static func sameDate(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 0.001
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

    /// Library shows everything in the vault, `inbox/` included (Eugene, 2026-10-18).
    /// Only hidden folders and media `Attachments` folders stay out: they hold no notes.
    public static func isVisible(_ url: URL, in vaultRootURL: URL) -> Bool {
        guard let path = VaultPathResolver(vaultRootURL: vaultRootURL).relativePath(for: url) else { return false }
        return !path.split(separator: "/").contains(where: { $0.hasPrefix(".") || $0 == "Attachments" })
    }

    static func titleOrder(_ lhs: VaultNoteRecord, _ rhs: VaultNoteRecord) -> Bool {
        let result = lhs.title.localizedStandardCompare(rhs.title)
        return result == .orderedSame ? lhs.fileURL.path < rhs.fileURL.path : result == .orderedAscending
    }
}
