import Foundation
import os.log

/// Manages reading and writing note markdown files in a vault directory.
/// Each note is a `.md` file named by its UUID.
/// The vault directory structure:
/// ```
/// Noto/
///   {uuid}.md
///   {uuid}.md
///   ...
/// ```
public final class VaultManager: Sendable {
    public let rootURL: URL
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.noto", category: "VaultManager")

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// Ensures the vault directory exists. Call once at startup.
    public func ensureVaultExists() throws {
        if !fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            logger.info("Created vault directory at \(self.rootURL.path)")
        }
    }

    /// Lists all notes in the vault, sorted by modified date descending.
    public func listNotes() throws -> [NoteFile] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }

        let contents = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let mdFiles = contents.filter { $0.pathExtension == "md" }

        var notes: [NoteFile] = []
        for fileURL in mdFiles {
            if let note = try? readNote(at: fileURL) {
                notes.append(note)
            }
        }

        return notes.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Creates a new note with the given content and writes it to disk.
    @discardableResult
    public func createNote(content: String = "") throws -> NoteFile {
        let now = Date()
        let note = NoteFile(id: UUID(), content: content, createdAt: now, modifiedAt: now)
        try writeNote(note)
        logger.info("Created note \(note.id.uuidString)")
        return note
    }

    /// Updates an existing note's content and modified date, then writes to disk.
    @discardableResult
    public func updateNote(id: UUID, content: String) throws -> NoteFile {
        let fileURL = urlForNote(id: id)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw VaultError.noteNotFound(id)
        }

        let existing = try readNote(at: fileURL)
        let updated = NoteFile(id: existing.id, content: content, createdAt: existing.createdAt, modifiedAt: Date())
        try writeNote(updated)
        logger.info("Updated note \(id.uuidString)")
        return updated
    }

    /// Reads a single note by ID.
    public func readNote(id: UUID) throws -> NoteFile {
        let fileURL = urlForNote(id: id)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw VaultError.noteNotFound(id)
        }
        return try readNote(at: fileURL)
    }

    /// Deletes a note by ID.
    public func deleteNote(id: UUID) throws {
        let fileURL = urlForNote(id: id)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw VaultError.noteNotFound(id)
        }
        try fileManager.removeItem(at: fileURL)
        logger.info("Deleted note \(id.uuidString)")
    }

    // MARK: - Private

    private func urlForNote(id: UUID) -> URL {
        rootURL.appendingPathComponent("\(id.uuidString).md")
    }

    private func readNote(at url: URL) throws -> NoteFile {
        let markdown = try String(contentsOf: url, encoding: .utf8)
        let (metadata, body) = Frontmatter.parse(markdown)

        guard let meta = metadata else {
            throw VaultError.invalidFrontmatter(url.lastPathComponent)
        }

        return NoteFile(id: meta.id, content: body, createdAt: meta.createdAt, modifiedAt: meta.modifiedAt)
    }

    private func writeNote(_ note: NoteFile) throws {
        try ensureVaultExists()
        let fileURL = urlForNote(id: note.id)
        let markdown = Frontmatter.serialize(note)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

public enum VaultError: Error, Equatable {
    case noteNotFound(UUID)
    case invalidFrontmatter(String)
}
