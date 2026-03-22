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
final class MarkdownNoteStore: ObservableObject {
    @Published private(set) var items: [DirectoryItem] = []

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
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            do {
                try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                logger.info("Created directory at \(self.directoryURL.path)")
            } catch {
                logger.error("Failed to create directory: \(error)")
            }
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
                let title: String
                let noteId: UUID
                if let handle = try? FileHandle(forReadingFrom: url) {
                    let data = handle.readData(ofLength: 1024)
                    handle.closeFile()
                    let snippet = String(data: data, encoding: .utf8) ?? ""
                    title = MarkdownNote.titleFrom(snippet)
                    noteId = MarkdownNote.idFromFrontmatter(snippet)
                        ?? UUID(uuid: UUID.nameToUUID(url.path))
                } else {
                    title = "Untitled"
                    noteId = UUID(uuid: UUID.nameToUUID(url.path))
                }

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
        (try? String(contentsOf: note.fileURL, encoding: .utf8)) ?? ""
    }

    func createNote() -> MarkdownNote {
        let id = UUID()
        let filename = "\(id.uuidString).md"
        let fileURL = directoryURL.appendingPathComponent(filename)
        let initialContent = MarkdownNote.makeFrontmatter(id: id) + "# "

        do {
            try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to create note: \(error)")
        }

        let note = MarkdownNote(id: id, fileURL: fileURL, title: "Untitled", modifiedDate: Date())
        items.insert(.note(note), at: folderCount)
        return note
    }

    /// Saves content immediately (writes file + updates list title). Does NOT rename.
    @discardableResult
    func saveContent(_ content: String, for note: MarkdownNote) -> MarkdownNote {
        do {
            let contentToSave = MarkdownNote.updateTimestamp(in: content)
            try contentToSave.write(to: note.fileURL, atomically: true, encoding: .utf8)

            let newTitle = MarkdownNote.titleFrom(content)
            logger.info("[saveContent] title='\(newTitle)' file=\(note.fileURL.lastPathComponent) contentLen=\(content.count)")
            logger.info("[saveContent] first100='\(String(content.prefix(100)))'")

            let updated = MarkdownNote(
                id: note.id,
                fileURL: note.fileURL,
                title: newTitle,
                modifiedDate: Date()
            )

            if let idx = items.firstIndex(where: { $0.id == note.id }) {
                items.remove(at: idx)
                items.insert(.note(updated), at: folderCount)
                logger.info("[saveContent] updated items at idx=\(idx)")
            } else {
                logger.warning("[saveContent] note id=\(note.id) NOT FOUND in items (count=\(self.items.count))")
            }

            return updated
        } catch {
            logger.error("Failed to save note: \(error)")
            return note
        }
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

        do {
            try FileManager.default.moveItem(at: note.fileURL, to: newURL)
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
        } catch {
            logger.error("Failed to rename note: \(error)")
            return note
        }
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

    func deleteNote(_ note: MarkdownNote) {
        do {
            try FileManager.default.removeItem(at: note.fileURL)
            items.removeAll { $0.id == note.id }
        } catch {
            logger.error("Failed to delete note: \(error)")
        }
    }

    // MARK: - Today's Note

    /// Returns today's note, creating the Daily Notes folder and note file if needed.
    /// Today's note lives at `Daily Notes/YYYY-MM-DD.md`.
    func todayNote() -> (store: MarkdownNoteStore, note: MarkdownNote) {
        let dailyFolderURL = vaultRootURL.appendingPathComponent("Daily Notes")
        let fm = FileManager.default
        if !fm.fileExists(atPath: dailyFolderURL.path) {
            try? fm.createDirectory(at: dailyFolderURL, withIntermediateDirectories: true)
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

        if !fm.fileExists(atPath: fileURL.path) {
            let id = UUID()
            let template = NoteTemplate.dailyNote
            let content = MarkdownNote.makeFrontmatter(id: id) + "# \(displayDate)\n\(template.body)"
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Read ID from frontmatter of existing file
        let id: UUID
        if let data = try? Data(contentsOf: fileURL),
           let snippet = String(data: data, encoding: .utf8),
           let fmId = MarkdownNote.idFromFrontmatter(snippet) {
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
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create folder: \(error)")
        }

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
        do {
            try FileManager.default.removeItem(at: folder.folderURL)
            items.removeAll { $0.id == folder.id }
        } catch {
            logger.error("Failed to delete folder: \(error)")
        }
    }

    func deleteItem(_ item: DirectoryItem) {
        switch item {
        case .folder(let f): deleteFolder(f)
        case .note(let n): deleteNote(n)
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
