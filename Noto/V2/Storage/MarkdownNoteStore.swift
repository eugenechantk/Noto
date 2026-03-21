import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "MarkdownNoteStore")

/// Represents a single markdown note on disk.
struct MarkdownNote: Identifiable, Hashable {
    let id: UUID
    let fileURL: URL
    var title: String
    var modifiedDate: Date

    /// Derives title from the first line of content, stripping leading `# `.
    static func titleFrom(_ content: String) -> String {
        let firstLine = content.prefix(while: { $0 != "\n" })
        var title = String(firstLine).trimmingCharacters(in: .whitespaces)
        // Strip leading markdown heading prefix (# , ## , ### , or bare #)
        if let match = title.range(of: #"^#{1,3}\s*"#, options: .regularExpression) {
            title = String(title[match.upperBound...])
        }
        return title.isEmpty ? "Untitled" : title
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
                if let handle = try? FileHandle(forReadingFrom: url) {
                    let data = handle.readData(ofLength: 512)
                    handle.closeFile()
                    let snippet = String(data: data, encoding: .utf8) ?? ""
                    title = MarkdownNote.titleFrom(snippet)
                } else {
                    title = "Untitled"
                }

                let stem = url.deletingPathExtension().lastPathComponent
                let id = UUID(uuidString: stem) ?? UUID(uuid: UUID.nameToUUID(stem))
                loaded.append(.note(MarkdownNote(id: id, fileURL: url, title: title, modifiedDate: modDate)))
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
        let initialContent = "# "

        do {
            try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to create note: \(error)")
        }

        let note = MarkdownNote(id: id, fileURL: fileURL, title: "Untitled", modifiedDate: Date())
        items.insert(.note(note), at: folderCount)
        return note
    }

    func save(content: String, for note: MarkdownNote) {
        do {
            try content.write(to: note.fileURL, atomically: true, encoding: .utf8)
            if let idx = items.firstIndex(where: { $0.id == note.id }) {
                let updated = MarkdownNote(
                    id: note.id,
                    fileURL: note.fileURL,
                    title: MarkdownNote.titleFrom(content),
                    modifiedDate: Date()
                )
                items.remove(at: idx)
                items.insert(.note(updated), at: folderCount)
            }
        } catch {
            logger.error("Failed to save note: \(error)")
        }
    }

    func deleteNote(_ note: MarkdownNote) {
        do {
            try FileManager.default.removeItem(at: note.fileURL)
            items.removeAll { $0.id == note.id }
        } catch {
            logger.error("Failed to delete note: \(error)")
        }
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
