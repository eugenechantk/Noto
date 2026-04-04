import Foundation
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
        let body = stripFrontmatter(content)
        let firstLine = body.prefix(while: { $0 != "\n" })
        var title = String(firstLine).trimmingCharacters(in: .whitespaces)
        if let match = title.range(of: #"^#{1,3}\s*"#, options: .regularExpression) {
            title = String(title[match.upperBound...])
        }
        return title.isEmpty ? "Untitled" : title
    }

    /// Strips YAML frontmatter (--- ... ---) from the beginning of content.
    static func stripFrontmatter(_ content: String) -> String {
        guard content.hasPrefix("---") else { return content }
        // Find the closing ---
        let searchRange = content.index(content.startIndex, offsetBy: 3)..<content.endIndex
        guard let closeRange = content.range(of: "\n---", range: searchRange) else { return content }
        let afterFrontmatter = content[closeRange.upperBound...]
        // Skip leading newlines after frontmatter
        return String(afterFrontmatter.drop(while: { $0 == "\n" }))
    }

    /// Extracts the UUID from YAML frontmatter, if present.
    static func idFromFrontmatter(_ content: String) -> UUID? {
        guard content.hasPrefix("---") else { return nil }
        let searchRange = content.index(content.startIndex, offsetBy: 3)..<content.endIndex
        guard let closeRange = content.range(of: "\n---", range: searchRange) else { return nil }
        let frontmatter = String(content[content.startIndex..<closeRange.upperBound])
        // Find id: line
        for line in frontmatter.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("id:") {
                let value = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                return UUID(uuidString: value)
            }
        }
        return nil
    }

    /// Generates YAML frontmatter block for a new note.
    static func makeFrontmatter(id: UUID, createdAt: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = formatter.string(from: createdAt)
        return """
        ---
        id: \(id.uuidString)
        created: \(now)
        updated: \(now)
        ---

        """
    }

    /// Updates the `updated` timestamp in existing frontmatter content.
    static func updateTimestamp(in content: String) -> String {
        guard content.hasPrefix("---") else { return content }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = formatter.string(from: Date())

        let lines = content.components(separatedBy: "\n")
        var updated = lines
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("updated:") {
                updated[i] = "updated: \(now)"
                break
            }
        }
        return updated.joined(separator: "\n")
    }
}

/// Represents a folder on disk.
struct NotoFolder: Identifiable, Hashable {
    let id: UUID
    let folderURL: URL
    var name: String
    var modifiedDate: Date
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

/// File-based note storage. Reads/writes .md files and folders in a vault directory.
@MainActor
@Observable
final class MarkdownNoteStore {
    struct SaveResult {
        let note: MarkdownNote
        let didWrite: Bool
    }

    private(set) var items: [DirectoryItem] = []

    let directoryURL: URL
    let vaultRootURL: URL

    /// Initialize for a specific directory within the vault.
    init(directoryURL: URL, vaultRootURL: URL? = nil) {
        self.directoryURL = directoryURL
        self.vaultRootURL = vaultRootURL ?? directoryURL
        ensureDirectoryExists()
        loadItems()
    }

    /// Convenience: initialize for the vault root.
    convenience init(vaultURL: URL) {
        self.init(directoryURL: vaultURL, vaultRootURL: vaultURL)
    }

    private func ensureDirectoryExists() {
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            CoordinatedFileManager.createDirectory(at: directoryURL)
            logger.info("Created directory at \(self.directoryURL.path)")
        }
    }

    func loadItems() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.error("Failed to list directory contents")
            return
        }

        var loaded: [DirectoryItem] = []

        for url in contents {
            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  let modDate = attrs.contentModificationDate,
                  let isDir = attrs.isDirectory else { continue }

            if isDir {
                let name = url.lastPathComponent
                let id = UUID(uuid: UUID.nameToUUID(url.path))
                loaded.append(.folder(NotoFolder(id: id, folderURL: url, name: name, modifiedDate: modDate)))
            } else if url.pathExtension == "md" {
                // Derive title from filename for fast listing — no file I/O needed.
                // Full content (frontmatter ID, etc.) is read when the note is opened.
                let stem = url.deletingPathExtension().lastPathComponent
                let title = stem.isEmpty ? "Untitled" : stem
                let noteId = UUID(uuid: UUID.nameToUUID(url.path))

                loaded.append(.note(MarkdownNote(id: noteId, fileURL: url, title: title, modifiedDate: modDate)))
            }
        }

        // Folders first (alphabetical), then notes (by modification date descending)
        let folders = loaded.filter {
            if case .folder = $0 { return true }; return false
        }.sorted {
            if case .folder(let a) = $0, case .folder(let b) = $1 { return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
            return false
        }
        let notes = loaded.filter {
            if case .note = $0 { return true }; return false
        }.sorted { $0.modifiedDate > $1.modifiedDate }

        items = folders + notes
        for item in items {
            if case .note(let n) = item {
                logger.info("[loadItems] note title='\(n.title)' file=\(n.fileURL.lastPathComponent)")
            }
        }
    }

    // MARK: - Notes

    var notes: [MarkdownNote] {
        items.compactMap { if case .note(let n) = $0 { return n } else { return nil } }
    }

    func readContent(of note: MarkdownNote) -> String {
        let content = CoordinatedFileManager.readString(from: note.fileURL) ?? ""
        DebugTrace.record("store read note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(content))")
        return content
    }

    func createNote() -> MarkdownNote {
        let id = UUID()
        let filename = "\(id.uuidString).md"
        let fileURL = directoryURL.appendingPathComponent(filename)
        let initialContent = MarkdownNote.makeFrontmatter(id: id) + "# "

        if !CoordinatedFileManager.writeString(initialContent, to: fileURL) {
            logger.error("Failed to create note at \(fileURL.lastPathComponent)")
        }

        let note = MarkdownNote(id: id, fileURL: fileURL, title: "Untitled", modifiedDate: Date())
        items.insert(.note(note), at: folderCount)
        return note
    }

    @discardableResult
    func updateTitleFromContent(_ content: String, for note: MarkdownNote) -> MarkdownNote {
        let newTitle = MarkdownNote.titleFrom(content)
        guard newTitle != note.title else { return note }

        let updated = MarkdownNote(
            id: note.id,
            fileURL: note.fileURL,
            title: newTitle,
            modifiedDate: note.modifiedDate
        )

        if let idx = items.firstIndex(where: { $0.id == note.id }) {
            items[idx] = .note(updated)
        }

        return updated
    }

    /// Saves content immediately (writes file + updates list title). Does NOT rename.
    /// Only writes to disk and updates the `updated` timestamp if the content body has actually changed.
    @discardableResult
    func saveContent(_ content: String, for note: MarkdownNote) -> SaveResult {
        // Check if the body (non-frontmatter) content actually changed
        let existingContent = CoordinatedFileManager.readString(from: note.fileURL) ?? ""
        let existingBody = MarkdownNote.stripFrontmatter(existingContent)
        let newBody = MarkdownNote.stripFrontmatter(content)

        DebugTrace.record("store save begin note=\(note.fileURL.lastPathComponent) existingBodyLen=\(existingBody.count) newBodyLen=\(newBody.count)")

        guard existingBody != newBody else {
            // No body change — don't write, don't update timestamp, don't touch items
            DebugTrace.record("store save skipped unchanged note=\(note.fileURL.lastPathComponent)")
            return SaveResult(note: note, didWrite: false)
        }

        let contentToSave = MarkdownNote.updateTimestamp(in: content)
        let writeSucceeded = CoordinatedFileManager.writeString(contentToSave, to: note.fileURL)
        DebugTrace.record("store write result note=\(note.fileURL.lastPathComponent) success=\(writeSucceeded)")
        guard writeSucceeded else {
            logger.error("Failed to save note \(note.fileURL.lastPathComponent)")
            return SaveResult(note: note, didWrite: false)
        }

        let newTitle = MarkdownNote.titleFrom(content)

        let updated = MarkdownNote(
            id: note.id,
            fileURL: note.fileURL,
            title: newTitle,
            modifiedDate: Date()
        )

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
        let currentStem = note.fileURL.deletingPathExtension().lastPathComponent
        let isDailyNote = currentStem.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        let sanitized = Self.sanitizeFilename(note.title)

        guard !isDailyNote && !sanitized.isEmpty && sanitized != "Untitled" && sanitized != currentStem else {
            return note
        }

        let newURL = note.fileURL.deletingLastPathComponent()
            .appendingPathComponent(sanitized)
            .appendingPathExtension("md")

        guard !FileManager.default.fileExists(atPath: newURL.path) else { return note }

        guard CoordinatedFileManager.move(from: note.fileURL, to: newURL) else {
            logger.error("Failed to rename note to \(sanitized).md")
            return note
        }

        logger.info("Renamed note to \(sanitized).md")

        let updated = MarkdownNote(
            id: note.id,
            fileURL: newURL,
            title: note.title,
            modifiedDate: note.modifiedDate
        )

        if let idx = items.firstIndex(where: { $0.id == note.id }) {
            items.remove(at: idx)
            items.insert(.note(updated), at: folderCount)
        }

        return updated
    }

    /// Sanitize a string for use as a filename.
    private static func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?\"<>|*")
        var sanitized = name.components(separatedBy: illegal).joined()
        sanitized = sanitized.trimmingCharacters(in: .whitespaces)
        // Limit length
        if sanitized.count > 100 {
            sanitized = String(sanitized.prefix(100))
        }
        return sanitized
    }

    @discardableResult
    func deleteNote(_ note: MarkdownNote) -> Bool {
        if CoordinatedFileManager.delete(at: note.fileURL) || deleteWithoutCoordination(note.fileURL) {
            items.removeAll { $0.id == note.id }
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
        // No-op if already in the destination
        if note.fileURL.deletingLastPathComponent().standardizedFileURL == destinationDirectory.standardizedFileURL {
            return note
        }

        // Create destination if needed
        if !FileManager.default.fileExists(atPath: destinationDirectory.path) {
            guard CoordinatedFileManager.createDirectory(at: destinationDirectory) else {
                logger.error("Failed to create destination directory")
                return note
            }
        }

        let destURL = Self.resolveConflict(
            for: note.fileURL.lastPathComponent,
            in: destinationDirectory
        )

        guard CoordinatedFileManager.move(from: note.fileURL, to: destURL) else {
            logger.error("Failed to move note to \(destURL.lastPathComponent)")
            return note
        }

        items.removeAll { $0.id == note.id }
        logger.info("Moved note to \(destURL.path)")

        return MarkdownNote(
            id: note.id,
            fileURL: destURL,
            title: note.title,
            modifiedDate: note.modifiedDate
        )
    }

    /// Moves a folder to a different directory. Creates the destination if needed.
    /// On name conflict, appends (2), (3), etc. Returns the moved folder.
    @discardableResult
    func moveFolder(_ folder: NotoFolder, to destinationDirectory: URL) -> NotoFolder {
        // No-op if already in the destination
        if folder.folderURL.deletingLastPathComponent().standardizedFileURL == destinationDirectory.standardizedFileURL {
            return folder
        }

        // Create destination if needed
        if !FileManager.default.fileExists(atPath: destinationDirectory.path) {
            guard CoordinatedFileManager.createDirectory(at: destinationDirectory) else {
                logger.error("Failed to create destination directory")
                return folder
            }
        }

        let destURL = Self.resolveConflictForFolder(
            named: folder.name,
            in: destinationDirectory
        )

        guard CoordinatedFileManager.move(from: folder.folderURL, to: destURL) else {
            logger.error("Failed to move folder to \(destURL.lastPathComponent)")
            return folder
        }

        items.removeAll { $0.id == folder.id }
        logger.info("Moved folder to \(destURL.path)")

        return NotoFolder(
            id: folder.id,
            folderURL: destURL,
            name: destURL.lastPathComponent,
            modifiedDate: folder.modifiedDate
        )
    }

    /// Resolves filename conflicts by appending (2), (3), etc.
    private static func resolveConflict(for filename: String, in directory: URL) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(filename)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(stem)(\(counter))" : "\(stem)(\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    /// Resolves folder name conflicts by appending (2), (3), etc.
    private static func resolveConflictForFolder(named name: String, in directory: URL) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name)(\(counter))")
            counter += 1
        }
        return candidate
    }

    // MARK: - Today's Note

    /// Returns today's note, creating the Daily Notes folder and note file if needed.
    /// Today's note lives at `Daily Notes/YYYY-MM-DD.md`.
    func todayNote() -> (store: MarkdownNoteStore, note: MarkdownNote) {
        let dailyFolderURL = vaultRootURL.appendingPathComponent("Daily Notes")
        if !FileManager.default.fileExists(atPath: dailyFolderURL.path) {
            CoordinatedFileManager.createDirectory(at: dailyFolderURL)
        }

        // Filename uses ISO date for chronological sorting
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        let isoDate = isoFormatter.string(from: Date())
        let filename = "\(isoDate).md"
        let fileURL = dailyFolderURL.appendingPathComponent(filename)

        // Display title: "22 Mar, 26 (Sat)"
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "dd MMM, yy (EEE)"
        let displayDate = displayFormatter.string(from: Date())

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let id = UUID()
            let template = NoteTemplate.dailyNote
            let content = MarkdownNote.makeFrontmatter(id: id) + "# \(displayDate)\n\(template.body)"
            CoordinatedFileManager.writeString(content, to: fileURL)
        }

        // Read existing file content
        let existingContent = CoordinatedFileManager.readString(from: fileURL) ?? ""

        // Retroactively apply template to pre-existing daily notes that don't have it
        let template = NoteTemplate.dailyNote
        if let updated = template.applyRetroactively(to: existingContent) {
            CoordinatedFileManager.writeString(updated, to: fileURL)
        }

        // Read ID from frontmatter
        let id: UUID
        if let fmId = MarkdownNote.idFromFrontmatter(existingContent) {
            id = fmId
        } else {
            id = UUID(uuid: UUID.nameToUUID(fileURL.path))
        }
        let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        let note = MarkdownNote(
            id: id,
            fileURL: fileURL,
            title: displayDate,
            modifiedDate: attrs?.contentModificationDate ?? Date()
        )

        let dailyStore = MarkdownNoteStore(directoryURL: dailyFolderURL, vaultRootURL: vaultRootURL)
        return (dailyStore, note)
    }

    // MARK: - Folders

    var folders: [NotoFolder] {
        items.compactMap { if case .folder(let f) = $0 { return f } else { return nil } }
    }

    private var folderCount: Int {
        items.prefix(while: { if case .folder = $0 { return true }; return false }).count
    }

    func createFolder(name: String) -> NotoFolder {
        let folderURL = directoryURL.appendingPathComponent(name)
        CoordinatedFileManager.createDirectory(at: folderURL)

        let folder = NotoFolder(
            id: UUID(uuid: UUID.nameToUUID(folderURL.path)),
            folderURL: folderURL,
            name: name,
            modifiedDate: Date()
        )

        // Insert in alphabetical order among existing folders
        let insertIdx = folders.firstIndex { $0.name.localizedCaseInsensitiveCompare(name) == .orderedDescending } ?? folderCount
        items.insert(.folder(folder), at: insertIdx)
        return folder
    }

    func deleteFolder(_ folder: NotoFolder) {
        if CoordinatedFileManager.delete(at: folder.folderURL) {
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

// MARK: - UUID Helper

private extension UUID {
    static func nameToUUID(_ name: String) -> uuid_t {
        var hasher = Hasher()
        hasher.combine(name)
        let hash = hasher.finalize()
        let u = UInt64(bitPattern: Int64(hash))
        return (
            UInt8(truncatingIfNeeded: u), UInt8(truncatingIfNeeded: u >> 8),
            UInt8(truncatingIfNeeded: u >> 16), UInt8(truncatingIfNeeded: u >> 24),
            UInt8(truncatingIfNeeded: u >> 32), UInt8(truncatingIfNeeded: u >> 40),
            UInt8(truncatingIfNeeded: u >> 48), UInt8(truncatingIfNeeded: u >> 56),
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }
}
