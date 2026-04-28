import Foundation
import NotoSearch
import NotoVault
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "MarkdownNoteStore")

/// Represents a single markdown note on disk.
struct MarkdownNote: Identifiable, Hashable {
    let id: UUID
    let fileURL: URL
    var title: String
    var modifiedDate: Date

    /// Derives title from content, skipping YAML frontmatter and stripping heading prefix.
    static func titleFrom(_ content: String) -> String {
        VaultMarkdown.title(from: content)
    }

    /// Strips YAML frontmatter (--- ... ---) from the beginning of content.
    static func stripFrontmatter(_ content: String) -> String {
        VaultMarkdown.stripFrontmatter(content)
    }

    /// Extracts the UUID from YAML frontmatter, if present.
    static func idFromFrontmatter(_ content: String) -> UUID? {
        VaultMarkdown.idFromFrontmatter(content)
    }

    /// Generates YAML frontmatter block for a new note.
    static func makeFrontmatter(id: UUID, createdAt: Date = Date()) -> String {
        VaultMarkdown.makeFrontmatter(id: id, createdAt: createdAt)
    }

    /// Updates the `updated` timestamp in existing frontmatter content.
    static func updateTimestamp(in content: String) -> String {
        VaultMarkdown.updateTimestamp(in: content)
    }
}

struct PageMentionDocument: Identifiable, Equatable {
    let id: UUID
    let title: String
    let relativePath: String
    let fileURL: URL
}

typealias VaultImageAttachment = NotoVault.VaultImageAttachment
typealias VaultImageAttachmentStore = NotoVault.AttachmentStore

struct DailyNoteFile {
    struct Resolution {
        let dailyFolderURL: URL
        let fileURL: URL
        let displayTitle: String
        let id: UUID
        let modifiedDate: Date
        let didCreate: Bool
        let didApplyTemplate: Bool
    }

    static func ensure(
        vaultRootURL: URL,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> Resolution {
        let resolved = DailyNoteService(vaultRootURL: vaultRootURL)
            .ensure(date: date, calendar: calendar)
        return Resolution(
            dailyFolderURL: resolved.dailyFolderURL,
            fileURL: resolved.fileURL,
            displayTitle: resolved.displayTitle,
            id: resolved.id,
            modifiedDate: resolved.modifiedDate,
            didCreate: resolved.didCreate,
            didApplyTemplate: resolved.didApplyTemplate
        )
    }

    static func nextStartOfDay(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        DailyNoteService.nextStartOfDay(after: date, calendar: calendar)
    }
}

/// Represents a folder on disk.
struct NotoFolder: Identifiable, Hashable {
    let id: UUID
    let folderURL: URL
    var name: String
    var modifiedDate: Date
    var folderCount: Int
    var itemCount: Int
}

/// An item in a directory listing — either a folder or a note.
enum DirectoryItem: Identifiable, Hashable {
    case folder(NotoFolder)
    case note(MarkdownNote)

    var id: UUID {
        switch self {
        case .folder(let f): return f.id
        case .note(let n): return n.id
        }
    }

    var modifiedDate: Date {
        switch self {
        case .folder(let f): return f.modifiedDate
        case .note(let n): return n.modifiedDate
        }
    }
}

extension MarkdownNote {
    init(summary: NoteSummary) {
        self.init(
            id: summary.id,
            fileURL: summary.fileURL,
            title: summary.title,
            modifiedDate: summary.modifiedDate
        )
    }

    init(record: VaultNoteRecord) {
        self.init(
            id: record.id,
            fileURL: record.fileURL,
            title: record.title,
            modifiedDate: record.modifiedDate
        )
    }

    var vaultRecord: VaultNoteRecord {
        VaultNoteRecord(id: id, fileURL: fileURL, title: title, modifiedDate: modifiedDate)
    }
}

extension NotoFolder {
    init(summary: FolderSummary) {
        self.init(
            id: summary.id,
            folderURL: summary.folderURL,
            name: summary.name,
            modifiedDate: summary.modifiedDate,
            folderCount: summary.folderCount,
            itemCount: summary.itemCount
        )
    }

    init(record: VaultFolderRecord) {
        self.init(
            id: record.id,
            folderURL: record.folderURL,
            name: record.name,
            modifiedDate: record.modifiedDate,
            folderCount: record.folderCount,
            itemCount: record.itemCount
        )
    }
}

extension DirectoryItem {
    init(item: VaultListItem) {
        switch item {
        case .folder(let folder):
            self = .folder(NotoFolder(summary: folder))
        case .note(let note):
            self = .note(MarkdownNote(summary: note))
        }
    }
}

/// File-based note storage. Reads/writes .md files and folders in a vault directory.
@MainActor
@Observable
final class MarkdownNoteStore {
    struct SaveResult {
        let note: MarkdownNote
        let didWrite: Bool
    }

    private(set) var items: [DirectoryItem] = []
    private(set) var isLoadingItems = false

    @ObservationIgnored
    private var loadItemsTask: Task<Void, Never>?

    let directoryURL: URL
    let vaultRootURL: URL
    let directoryLoader: VaultDirectoryLoader

    private var noteRepository: NoteRepository {
        NoteRepository(directoryURL: directoryURL, vaultRootURL: vaultRootURL)
    }

    private var folderRepository: FolderRepository {
        FolderRepository(directoryURL: directoryURL)
    }

    /// Initialize for a specific directory within the vault.
    init(
        directoryURL: URL,
        vaultRootURL: URL? = nil,
        autoload: Bool = true,
        directoryLoader: VaultDirectoryLoader = VaultDirectoryLoader()
    ) {
        self.directoryURL = directoryURL
        self.vaultRootURL = vaultRootURL ?? directoryURL
        self.directoryLoader = directoryLoader
        ensureDirectoryExists()
        if autoload {
            loadItems()
        }
    }

    /// Convenience: initialize for the vault root.
    convenience init(
        vaultURL: URL,
        autoload: Bool = true,
        directoryLoader: VaultDirectoryLoader = VaultDirectoryLoader()
    ) {
        self.init(
            directoryURL: vaultURL,
            vaultRootURL: vaultURL,
            autoload: autoload,
            directoryLoader: directoryLoader
        )
    }

    deinit {
        loadItemsTask?.cancel()
    }

    private func ensureDirectoryExists() {
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            noteRepository.ensureDirectoryExists()
            logger.info("Created directory at \(self.directoryURL.path)")
        }
    }

    func loadItems() {
        loadItemsTask?.cancel()
        isLoadingItems = true
        defer { isLoadingItems = false }

        do {
            items = try directoryLoader
                .loadItems(in: directoryURL)
                .map { DirectoryItem(item: $0) }
        } catch {
            logger.error("Failed to list directory contents")
            items = []
        }
    }

    func refreshForForegroundActivation() {
        loadItemsInBackground()
    }

    func loadItemsInBackground() {
        loadItemsTask?.cancel()

        let directoryURL = directoryURL
        let directoryLoader = directoryLoader
        isLoadingItems = true

        loadItemsTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try directoryLoader.loadItems(in: directoryURL)
                }
            }.value

            guard !Task.isCancelled else { return }

            switch result {
            case .success(let loadedItems):
                self?.items = loadedItems.map { DirectoryItem(item: $0) }
            case .failure:
                logger.error("Failed to list directory contents")
                self?.items = []
            }
            self?.isLoadingItems = false
        }
    }

    // MARK: - Notes

    var notes: [MarkdownNote] {
        items.compactMap { if case .note(let n) = $0 { return n } else { return nil } }
    }

    func readContent(of note: MarkdownNote) -> String {
        let content = noteRepository.readContent(of: note.vaultRecord)
        DebugTrace.record("store read note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(content))")
        return content
    }

    func importImageAttachment(data: Data, suggestedFilename: String?) throws -> VaultImageAttachment {
        try VaultImageAttachmentStore(vaultRootURL: vaultRootURL)
            .importImageData(data, suggestedFilename: suggestedFilename)
    }

    func importImageAttachment(fileURL: URL) throws -> VaultImageAttachment {
        try VaultImageAttachmentStore(vaultRootURL: vaultRootURL)
            .importImageFile(at: fileURL)
    }

    func vaultRelativePath(for fileURL: URL) -> String? {
        noteRepository.relativePath(for: fileURL)
    }

    func note(atVaultRelativePath relativePath: String) -> (store: MarkdownNoteStore, note: MarkdownNote)? {
        guard let record = noteRepository.note(atVaultRelativePath: relativePath) else { return nil }
        let note = MarkdownNote(record: record)
        let noteStore = MarkdownNoteStore(
            directoryURL: record.fileURL.deletingLastPathComponent(),
            vaultRootURL: vaultRootURL,
            autoload: false,
            directoryLoader: directoryLoader
        )
        return (noteStore, note)
    }

    func note(withID noteID: UUID) -> (store: MarkdownNoteStore, note: MarkdownNote)? {
        guard let record = noteRepository.note(withID: noteID) else { return nil }
        let noteStore = MarkdownNoteStore(
            directoryURL: record.fileURL.deletingLastPathComponent(),
            vaultRootURL: vaultRootURL,
            autoload: false,
            directoryLoader: directoryLoader
        )
        return (noteStore, MarkdownNote(record: record))
    }

    func pageMentionDocuments(
        matching query: String,
        excluding excludedURL: URL? = nil,
        limit: Int = 5,
        allowEmptyQuery: Bool = false
    ) -> [PageMentionDocument] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            guard allowEmptyQuery else { return [] }
            return Array(allPageMentionDocuments(excludingPath: excludedURL?.standardizedFileURL.path).prefix(limit))
        }

        let excludedPath = excludedURL?.standardizedFileURL.path
        if let indexedDocuments = indexedPageMentionDocuments(
            matching: query,
            excludingPath: excludedPath,
            limit: limit
        ) {
            return indexedDocuments
        }

        let documents = allPageMentionDocuments(excludingPath: excludedPath)
        return Array(documents
            .filter { document in
                document.title.lowercased().contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                let lhsTitle = lhs.title.lowercased()
                let rhsTitle = rhs.title.lowercased()

                let lhsTitlePrefix = lhsTitle.hasPrefix(normalizedQuery)
                let rhsTitlePrefix = rhsTitle.hasPrefix(normalizedQuery)
                if lhsTitlePrefix != rhsTitlePrefix { return lhsTitlePrefix }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(limit))
    }

    func createNote() -> MarkdownNote {
        let note = MarkdownNote(record: noteRepository.createNote())
        if FileManager.default.fileExists(atPath: note.fileURL.path) {
            refreshSearchIndexFileImmediately(note.fileURL)
        } else {
            logger.error("Failed to create note at \(note.fileURL.lastPathComponent)")
        }
        items.insert(.note(note), at: folderCount)
        return note
    }

    @discardableResult
    func updateTitleFromContent(_ content: String, for note: MarkdownNote) -> MarkdownNote {
        updateMetadataFromContent(content, for: note)
    }

    @discardableResult
    func updateMetadataFromContent(_ content: String, for note: MarkdownNote) -> MarkdownNote {
        let newTitle = MarkdownNote.titleFrom(content)
        let newID = MarkdownNote.idFromFrontmatter(content) ?? note.id
        guard newTitle != note.title || newID != note.id else { return note }

        let updated = MarkdownNote(
            id: newID,
            fileURL: note.fileURL,
            title: newTitle,
            modifiedDate: note.modifiedDate
        )

        if let idx = items.firstIndex(where: { item in
            switch item {
            case .note(let candidate):
                candidate.id == note.id || candidate.fileURL.standardizedFileURL == note.fileURL.standardizedFileURL
            case .folder:
                false
            }
        }) {
            items[idx] = .note(updated)
        }

        return updated
    }

    /// Saves content immediately (writes file + updates list title). Does NOT rename.
    /// Only writes to disk and updates the `updated` timestamp if the content body has actually changed.
    @discardableResult
    func saveContent(_ content: String, for note: MarkdownNote) -> SaveResult {
        let existingContent = noteRepository.readContent(of: note.vaultRecord)
        let existingBody = MarkdownNote.stripFrontmatter(existingContent)
        let newBody = MarkdownNote.stripFrontmatter(content)

        DebugTrace.record("store save begin note=\(note.fileURL.lastPathComponent) existingBodyLen=\(existingBody.count) newBodyLen=\(newBody.count)")

        guard existingBody != newBody else {
            // No body change — don't write, don't update timestamp, don't touch items
            DebugTrace.record("store save skipped unchanged note=\(note.fileURL.lastPathComponent)")
            return SaveResult(note: note, didWrite: false)
        }

        let result = noteRepository.saveContent(content, for: note.vaultRecord)
        DebugTrace.record("store write result note=\(note.fileURL.lastPathComponent) success=\(result.didWrite)")
        guard result.didWrite else {
            logger.error("Failed to save note \(note.fileURL.lastPathComponent)")
            return SaveResult(note: note, didWrite: false)
        }
        scheduleSearchIndexRefresh(for: note.fileURL)

        let updated = MarkdownNote(record: result.note)

        if let idx = items.firstIndex(where: { $0.id == note.id }) {
            items.remove(at: idx)
            items.insert(.note(updated), at: folderCount)
        }

        DebugTrace.record("store save end note=\(updated.fileURL.lastPathComponent) title=\(updated.title)")
        return SaveResult(note: updated, didWrite: true)
    }

    /// Renames the file to match the note title. Returns updated note with new fileURL.
    @discardableResult
    func renameFileIfNeeded(for note: MarkdownNote) -> MarkdownNote {
        let renamed = MarkdownNote(record: noteRepository.renameFileIfNeeded(for: note.vaultRecord))
        guard renamed.fileURL != note.fileURL else {
            return note
        }

        logger.info("Renamed note to \(renamed.fileURL.lastPathComponent)")

        if let idx = items.firstIndex(where: { $0.id == note.id }) {
            items.remove(at: idx)
            items.insert(.note(renamed), at: folderCount)
        }

        replaceSearchIndexFile(oldFileURL: note.fileURL, newFileURL: renamed.fileURL)
        return renamed
    }

    /// Sanitize a string for use as a filename.
    private static func sanitizeFilename(_ name: String) -> String {
        VaultMarkdown.sanitizeFilename(name)
    }

    @discardableResult
    func deleteNote(_ note: MarkdownNote) -> Bool {
        if noteRepository.deleteNote(note.vaultRecord) {
            items.removeAll { $0.id == note.id }
            removeSearchIndexFile(note.fileURL)
            return true
        }

        logger.error("Failed to delete note \(note.fileURL.lastPathComponent)")
        return false
    }

    // MARK: - Move

    /// Moves a note to a different directory. Creates the destination if needed.
    /// On filename conflict, appends (2), (3), etc. Returns the moved note.
    @discardableResult
    func moveNote(_ note: MarkdownNote, to destinationDirectory: URL) -> MarkdownNote {
        let moved = MarkdownNote(record: noteRepository.moveNote(note.vaultRecord, to: destinationDirectory))
        guard moved.fileURL != note.fileURL else {
            return note
        }

        items.removeAll { $0.id == note.id }
        logger.info("Moved note to \(moved.fileURL.path)")

        replaceSearchIndexFile(oldFileURL: note.fileURL, newFileURL: moved.fileURL)
        return moved
    }

    /// Moves a folder to a different directory. Creates the destination if needed.
    /// On name conflict, appends (2), (3), etc. Returns the moved folder.
    @discardableResult
    func moveFolder(_ folder: NotoFolder, to destinationDirectory: URL) -> NotoFolder {
        let moved = NotoFolder(record: folderRepository.moveFolder(
            id: folder.id,
            folderURL: folder.folderURL,
            name: folder.name,
            modifiedDate: folder.modifiedDate,
            folderCount: folder.folderCount,
            itemCount: folder.itemCount,
            to: destinationDirectory
        ))
        guard moved.folderURL != folder.folderURL else {
            return folder
        }

        items.removeAll { $0.id == folder.id }
        logger.info("Moved folder to \(moved.folderURL.path)")

        return moved
    }

    /// Resolves filename conflicts by appending (2), (3), etc.
    private static func resolveConflict(for filename: String, in directory: URL) -> URL {
        VaultMarkdown.resolveFileConflict(for: filename, in: directory, fileSystem: CoordinatedVaultFileSystem())
    }

    /// Resolves folder name conflicts by appending (2), (3), etc.
    private static func resolveConflictForFolder(named name: String, in directory: URL) -> URL {
        VaultMarkdown.resolveFolderConflict(named: name, in: directory, fileSystem: CoordinatedVaultFileSystem())
    }

    // MARK: - Today's Note

    /// Returns today's note, creating the Daily Notes folder and note file if needed.
    /// Today's note lives at `Daily Notes/YYYY-MM-DD.md`.
    func todayNote() -> (store: MarkdownNoteStore, note: MarkdownNote) {
        let resolved = DailyNoteFile.ensure(vaultRootURL: vaultRootURL)
        if resolved.didCreate {
            refreshSearchIndexFileImmediately(resolved.fileURL)
        } else if resolved.didApplyTemplate {
            scheduleSearchIndexRefresh(for: resolved.fileURL)
        }

        let note = MarkdownNote(
            id: resolved.id,
            fileURL: resolved.fileURL,
            title: resolved.displayTitle,
            modifiedDate: resolved.modifiedDate
        )

        let dailyStore = MarkdownNoteStore(
            directoryURL: resolved.dailyFolderURL,
            vaultRootURL: vaultRootURL,
            autoload: false,
            directoryLoader: directoryLoader
        )
        return (dailyStore, note)
    }

    // MARK: - Folders

    var folders: [NotoFolder] {
        items.compactMap { if case .folder(let f) = $0 { return f } else { return nil } }
    }

    private var folderCount: Int {
        items.prefix(while: { if case .folder = $0 { return true }; return false }).count
    }

    private func allPageMentionDocuments(excludingPath: String?) -> [PageMentionDocument] {
        guard let enumerator = FileManager.default.enumerator(
            at: vaultRootURL.standardizedFileURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var documents: [PageMentionDocument] = []
        for case let fileURL as URL in enumerator {
            let normalizedURL = fileURL.standardizedFileURL
            guard normalizedURL.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame,
                  normalizedURL.path != excludingPath,
                  let relativePath = vaultRelativePath(for: normalizedURL) else {
                continue
            }

            documents.append(PageMentionDocument(
                id: VaultDirectoryLoader.stableID(for: normalizedURL),
                title: Self.pageMentionTitle(for: normalizedURL),
                relativePath: relativePath,
                fileURL: normalizedURL
            ))
        }

        return documents.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func indexedPageMentionDocuments(
        matching query: String,
        excludingPath: String?,
        limit: Int
    ) -> [PageMentionDocument]? {
        let indexer = MarkdownSearchIndexer(vaultURL: vaultRootURL)
        let databaseURL = indexer.indexDirectory.appendingPathComponent("search.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        do {
            let engine = MarkdownSearchEngine(store: try indexer.openStore(), vaultURL: vaultRootURL)
            let results = try engine.search(query, scope: .title, limit: limit)
            return results.compactMap { result in
                let fileURL = result.fileURL.standardizedFileURL
                guard fileURL.path != excludingPath,
                      let relativePath = vaultRelativePath(for: fileURL) else {
                    return nil
                }
                return PageMentionDocument(
                    id: result.noteID,
                    title: result.title,
                    relativePath: relativePath,
                    fileURL: fileURL
                )
            }
        } catch {
            DebugTrace.record("page mention indexed search failed query=\(query) error=\(String(describing: error))")
            return nil
        }
    }

    private static func displayTitle(for fileURL: URL, content: String) -> String {
        let title = MarkdownNote.titleFrom(content)
        if title == "Untitled" {
            let fallback = fileURL.deletingPathExtension().lastPathComponent
            return fallback.isEmpty ? title : fallback
        }
        return title
    }

    private static func pageMentionTitle(for fileURL: URL) -> String {
        let title = fileURL.deletingPathExtension().lastPathComponent
        return title.isEmpty ? "Untitled" : title
    }

    func createFolder(name: String) -> NotoFolder {
        let folder = NotoFolder(record: folderRepository.createFolder(named: name))

        // Insert in alphabetical order among existing folders
        let insertIdx = folders.firstIndex { $0.name.localizedCaseInsensitiveCompare(name) == .orderedDescending } ?? folderCount
        items.insert(.folder(folder), at: insertIdx)
        return folder
    }

    func deleteFolder(_ folder: NotoFolder) {
        if folderRepository.deleteFolder(at: folder.folderURL) {
            items.removeAll { $0.id == folder.id }
        } else {
            logger.error("Failed to delete folder \(folder.name)")
        }
    }

    func deleteItem(_ item: DirectoryItem) {
        switch item {
        case .folder(let f): deleteFolder(f)
        case .note(let n): deleteNote(n)
        }
    }
}

private extension MarkdownNoteStore {
    func refreshSearchIndexFileImmediately(_ fileURL: URL) {
        let vaultURL = vaultRootURL
        Task.detached(priority: .utility) {
            do {
                _ = try await SearchIndexController.shared.refreshFile(vaultURL: vaultURL, fileURL: fileURL)
            } catch {
                DebugTrace.record("search index single-file refresh failed file=\(fileURL.lastPathComponent) error=\(String(describing: error))")
            }
        }
    }

    func scheduleSearchIndexRefresh(for fileURL: URL) {
        let vaultURL = vaultRootURL
        Task.detached(priority: .utility) {
            await SearchIndexController.shared.scheduleRefreshFile(vaultURL: vaultURL, fileURL: fileURL)
        }
    }

    func replaceSearchIndexFile(oldFileURL: URL, newFileURL: URL) {
        let vaultURL = vaultRootURL
        Task.detached(priority: .utility) {
            do {
                _ = try await SearchIndexController.shared.replaceFile(
                    vaultURL: vaultURL,
                    oldFileURL: oldFileURL,
                    newFileURL: newFileURL
                )
            } catch {
                DebugTrace.record("search index file replace failed file=\(newFileURL.lastPathComponent) error=\(String(describing: error))")
            }
        }
    }

    func removeSearchIndexFile(_ fileURL: URL) {
        let vaultURL = vaultRootURL
        Task.detached(priority: .utility) {
            do {
                _ = try await SearchIndexController.shared.removeFile(vaultURL: vaultURL, fileURL: fileURL)
            } catch {
                DebugTrace.record("search index file removal failed file=\(fileURL.lastPathComponent) error=\(String(describing: error))")
            }
        }
    }

    func deleteWithoutCoordination(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }

        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            logger.error("Fallback delete failed for \(url.lastPathComponent): \(error)")
            return false
        }
    }
}
