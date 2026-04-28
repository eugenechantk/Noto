import Foundation

public struct VaultNoteRecord: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let fileURL: URL
    public let title: String
    public let modifiedDate: Date

    public init(id: UUID, fileURL: URL, title: String, modifiedDate: Date) {
        self.id = id
        self.fileURL = fileURL
        self.title = title
        self.modifiedDate = modifiedDate
    }
}

public struct VaultNoteSaveResult: Sendable, Equatable {
    public let note: VaultNoteRecord
    public let didWrite: Bool

    public init(note: VaultNoteRecord, didWrite: Bool) {
        self.note = note
        self.didWrite = didWrite
    }
}

public struct NoteRepository: Sendable {
    public let vaultRootURL: URL
    public let directoryURL: URL
    public let fileSystem: any VaultFileSystem
    public let pathResolver: VaultPathResolver

    public init(
        directoryURL: URL,
        vaultRootURL: URL? = nil,
        fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem()
    ) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.vaultRootURL = (vaultRootURL ?? directoryURL).standardizedFileURL
        self.fileSystem = fileSystem
        self.pathResolver = VaultPathResolver(vaultRootURL: self.vaultRootURL)
    }

    public func ensureDirectoryExists() {
        if !fileSystem.fileExists(at: directoryURL) {
            _ = fileSystem.createDirectory(at: directoryURL)
        }
    }

    public func readContent(of note: VaultNoteRecord) -> String {
        fileSystem.readString(from: note.fileURL) ?? ""
    }

    public func createNote(createdAt: Date = Date()) -> VaultNoteRecord {
        let id = UUID()
        let fileURL = directoryURL.appendingPathComponent("\(id.uuidString).md")
        let initialContent = VaultMarkdown.makeFrontmatter(id: id, createdAt: createdAt) + "# "
        _ = fileSystem.writeString(initialContent, to: fileURL)
        return VaultNoteRecord(id: id, fileURL: fileURL, title: "Untitled", modifiedDate: createdAt)
    }

    public func note(atVaultRelativePath relativePath: String) -> VaultNoteRecord? {
        guard let fileURL = pathResolver.noteURL(forVaultRelativePath: relativePath),
              fileSystem.fileExists(at: fileURL) else {
            return nil
        }
        return noteRecord(at: fileURL)
    }

    public func note(withID noteID: UUID) -> VaultNoteRecord? {
        guard fileSystem.fileExists(at: vaultRootURL),
              let enumerator = FileManager.default.enumerator(
                at: vaultRootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        let frontmatterByteLimit = 64 * 1024
        for case let fileURL as URL in enumerator {
            let normalizedURL = fileURL.standardizedFileURL
            guard normalizedURL.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame,
                  let prefixData = fileSystem.readPrefix(from: normalizedURL, maxBytes: frontmatterByteLimit) else {
                continue
            }
            let prefix = String(decoding: prefixData, as: UTF8.self)
            guard VaultMarkdown.idFromFrontmatter(prefix) == noteID else { continue }
            return noteRecord(at: normalizedURL, idOverride: noteID)
        }
        return nil
    }

    @discardableResult
    public func saveContent(_ content: String, for note: VaultNoteRecord, date: Date = Date()) -> VaultNoteSaveResult {
        let existingContent = fileSystem.readString(from: note.fileURL) ?? ""
        let existingBody = VaultMarkdown.stripFrontmatter(existingContent)
        let newBody = VaultMarkdown.stripFrontmatter(content)

        guard existingBody != newBody else {
            return VaultNoteSaveResult(note: note, didWrite: false)
        }

        let contentToSave = VaultMarkdown.updateTimestamp(in: content, date: date)
        guard fileSystem.writeString(contentToSave, to: note.fileURL) else {
            return VaultNoteSaveResult(note: note, didWrite: false)
        }

        let updated = VaultNoteRecord(
            id: note.id,
            fileURL: note.fileURL,
            title: VaultMarkdown.title(from: content),
            modifiedDate: date
        )
        return VaultNoteSaveResult(note: updated, didWrite: true)
    }

    @discardableResult
    public func renameFileIfNeeded(for note: VaultNoteRecord) -> VaultNoteRecord {
        let currentStem = note.fileURL.deletingPathExtension().lastPathComponent
        let sanitized = VaultMarkdown.sanitizeFilename(note.title)

        guard !VaultMarkdown.isDailyNoteFileStem(currentStem),
              !sanitized.isEmpty,
              sanitized != "Untitled",
              sanitized != currentStem else {
            return note
        }

        let newURL = VaultMarkdown.resolveFileConflict(
            for: "\(sanitized).md",
            in: note.fileURL.deletingLastPathComponent(),
            fileSystem: fileSystem
        )
        guard fileSystem.move(from: note.fileURL, to: newURL) else {
            return note
        }

        return VaultNoteRecord(id: note.id, fileURL: newURL, title: note.title, modifiedDate: note.modifiedDate)
    }

    @discardableResult
    public func deleteNote(_ note: VaultNoteRecord) -> Bool {
        fileSystem.delete(at: note.fileURL) || deleteWithoutCoordination(note.fileURL)
    }

    @discardableResult
    public func moveNote(_ note: VaultNoteRecord, to destinationDirectory: URL) -> VaultNoteRecord {
        let normalizedDestination = destinationDirectory.standardizedFileURL
        if note.fileURL.deletingLastPathComponent().standardizedFileURL == normalizedDestination {
            return note
        }

        if !fileSystem.fileExists(at: normalizedDestination),
           !fileSystem.createDirectory(at: normalizedDestination) {
            return note
        }

        let destinationURL = VaultMarkdown.resolveFileConflict(
            for: note.fileURL.lastPathComponent,
            in: normalizedDestination,
            fileSystem: fileSystem
        )
        guard fileSystem.move(from: note.fileURL, to: destinationURL) else {
            return note
        }

        return VaultNoteRecord(
            id: note.id,
            fileURL: destinationURL,
            title: note.title,
            modifiedDate: note.modifiedDate
        )
    }

    public func relativePath(for fileURL: URL) -> String? {
        pathResolver.relativePath(for: fileURL)
    }

    private func noteRecord(at fileURL: URL, idOverride: UUID? = nil) -> VaultNoteRecord? {
        let content = fileSystem.readString(from: fileURL) ?? ""
        let id = idOverride ?? VaultMarkdown.idFromFrontmatter(content) ?? VaultDirectoryLoader.stableID(for: fileURL)
        let modifiedDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return VaultNoteRecord(
            id: id,
            fileURL: fileURL,
            title: VaultMarkdown.displayTitle(for: fileURL, content: content),
            modifiedDate: modifiedDate
        )
    }

    private func deleteWithoutCoordination(_ url: URL) -> Bool {
        guard fileSystem.fileExists(at: url) else { return true }

        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }
}
