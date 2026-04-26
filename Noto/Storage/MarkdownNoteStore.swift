import Foundation
import ImageIO
import NotoVault
import os.log
import UniformTypeIdentifiers

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

struct PageMentionDocument: Identifiable, Equatable {
    let id: UUID
    let title: String
    let relativePath: String
    let fileURL: URL
}

struct VaultImageAttachment: Equatable {
    let fileURL: URL
    let relativePath: String
    let markdownPath: String
    let altText: String

    var markdown: String {
        "![\(altText)](\(markdownPath))"
    }
}

struct VaultImageAttachmentStore {
    enum ImportError: Error, Equatable {
        case unsupportedImage
        case createAttachmentDirectoryFailed
        case writeFailed
    }

    static let attachmentDirectoryName = ".attachments"

    let vaultRootURL: URL
    var maxPixelSize: CGFloat = 2400
    var jpegCompressionQuality: CGFloat = 0.82

    func importImageFile(at sourceURL: URL) throws -> VaultImageAttachment {
        let data = try Data(contentsOf: sourceURL)
        return try importImageData(data, suggestedFilename: sourceURL.lastPathComponent)
    }

    func importImageData(_ data: Data, suggestedFilename: String?) throws -> VaultImageAttachment {
        let encoded = try encodeImage(data)
        let attachmentsURL = vaultRootURL.appendingPathComponent(Self.attachmentDirectoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: attachmentsURL.path) || CoordinatedFileManager.createDirectory(at: attachmentsURL) else {
            throw ImportError.createAttachmentDirectoryFailed
        }

        let stem = Self.sanitizedStem(from: suggestedFilename)
        let filename = "\(stem).\(encoded.fileExtension)"
        let destinationURL = Self.resolveConflict(for: filename, in: attachmentsURL)

        guard CoordinatedFileManager.writeData(encoded.data, to: destinationURL) else {
            throw ImportError.writeFailed
        }

        let relativePath = "\(Self.attachmentDirectoryName)/\(destinationURL.lastPathComponent)"
        return VaultImageAttachment(
            fileURL: destinationURL,
            relativePath: relativePath,
            markdownPath: Self.markdownPath(for: relativePath),
            altText: destinationURL.deletingPathExtension().lastPathComponent
        )
    }

    private func encodeImage(_ data: Data) throws -> (data: Data, fileExtension: String) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImportError.unsupportedImage
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImportError.unsupportedImage
        }

        let preservesAlpha = image.hasMeaningfulAlpha
        let outputType = preservesAlpha ? UTType.png : UTType.jpeg
        let outputExtension = preservesAlpha ? "png" : "jpg"
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            outputType.identifier as CFString,
            1,
            nil
        ) else {
            throw ImportError.unsupportedImage
        }

        let properties: [CFString: Any]
        if preservesAlpha {
            properties = [:]
        } else {
            properties = [kCGImageDestinationLossyCompressionQuality: jpegCompressionQuality]
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImportError.unsupportedImage
        }

        return (outputData as Data, outputExtension)
    }

    private static func sanitizedStem(from suggestedFilename: String?) -> String {
        let fallback = "Image"
        guard let suggestedFilename, !suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }

        let base = URL(fileURLWithPath: suggestedFilename).deletingPathExtension().lastPathComponent
        let illegal = CharacterSet(charactersIn: "/\\:?\"<>|*")
        let sanitized = base
            .components(separatedBy: illegal)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return fallback }
        return String(sanitized.prefix(80))
    }

    private static func markdownPath(for relativePath: String) -> String {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")
    }

    private static func resolveConflict(for filename: String, in directory: URL) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(filename)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)(\(counter)).\(ext)")
            counter += 1
        }
        return candidate
    }
}

private extension CGImage {
    var hasMeaningfulAlpha: Bool {
        switch alphaInfo {
        case .alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return false
        }
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
            CoordinatedFileManager.createDirectory(at: directoryURL)
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
        let content = CoordinatedFileManager.readString(from: note.fileURL) ?? ""
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
        let rootPath = vaultRootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }

    func note(atVaultRelativePath relativePath: String) -> (store: MarkdownNoteStore, note: MarkdownNote)? {
        let decodedPath = relativePath.removingPercentEncoding ?? relativePath
        let components = decodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }

        var fileURL = vaultRootURL
        for component in components {
            fileURL.appendPathComponent(component)
        }
        fileURL = fileURL.standardizedFileURL

        let rootPath = vaultRootURL.standardizedFileURL.path
        let filePath = fileURL.path
        guard filePath.hasPrefix(rootPath + "/"),
              fileURL.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame,
              FileManager.default.fileExists(atPath: filePath) else {
            return nil
        }

        let content = CoordinatedFileManager.readString(from: fileURL) ?? ""
        let id = MarkdownNote.idFromFrontmatter(content) ?? VaultDirectoryLoader.stableID(for: fileURL)
        let modifiedDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date()
        let note = MarkdownNote(
            id: id,
            fileURL: fileURL,
            title: Self.displayTitle(for: fileURL, content: content),
            modifiedDate: modifiedDate
        )
        let noteStore = MarkdownNoteStore(
            directoryURL: fileURL.deletingLastPathComponent(),
            vaultRootURL: vaultRootURL,
            autoload: false,
            directoryLoader: directoryLoader
        )
        return (noteStore, note)
    }

    func note(withID noteID: UUID) -> (store: MarkdownNoteStore, note: MarkdownNote)? {
        if FileManager.default.fileExists(atPath: vaultRootURL.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: vaultRootURL.standardizedFileURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }

            // Read only the frontmatter prefix to find the matching ID — reading
            // every full file on the main thread can stall for seconds on large
            // or iCloud-backed vaults and trip the iOS watchdog.
            let frontmatterByteLimit = 64 * 1024
            for case let fileURL as URL in enumerator {
                let normalizedURL = fileURL.standardizedFileURL
                guard normalizedURL.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame,
                      let prefixData = CoordinatedFileManager.readPrefix(from: normalizedURL, maxBytes: frontmatterByteLimit) else {
                    continue
                }
                let prefix = String(decoding: prefixData, as: UTF8.self)
                guard MarkdownNote.idFromFrontmatter(prefix) == noteID,
                      let content = CoordinatedFileManager.readString(from: normalizedURL) else {
                    continue
                }

                let modifiedDate = (try? normalizedURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? Date()
                let note = MarkdownNote(
                    id: noteID,
                    fileURL: normalizedURL,
                    title: Self.displayTitle(for: normalizedURL, content: content),
                    modifiedDate: modifiedDate
                )
                let noteStore = MarkdownNoteStore(
                    directoryURL: normalizedURL.deletingLastPathComponent(),
                    vaultRootURL: vaultRootURL,
                    autoload: false,
                    directoryLoader: directoryLoader
                )
                return (noteStore, note)
            }
        }

        return nil
    }

    func pageMentionDocuments(
        matching query: String,
        excluding excludedURL: URL? = nil,
        limit: Int = 5,
        allowEmptyQuery: Bool = false
    ) -> [PageMentionDocument] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let excludedPath = excludedURL?.standardizedFileURL.path
        let documents = allPageMentionDocuments(excludingPath: excludedPath)
        guard !normalizedQuery.isEmpty else {
            return allowEmptyQuery ? Array(documents.prefix(limit)) : []
        }

        return Array(documents
            .filter { document in
                document.title.lowercased().contains(normalizedQuery) ||
                    document.relativePath.lowercased().contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                let lhsTitle = lhs.title.lowercased()
                let rhsTitle = rhs.title.lowercased()
                let lhsPath = lhs.relativePath.lowercased()
                let rhsPath = rhs.relativePath.lowercased()

                let lhsTitlePrefix = lhsTitle.hasPrefix(normalizedQuery)
                let rhsTitlePrefix = rhsTitle.hasPrefix(normalizedQuery)
                if lhsTitlePrefix != rhsTitlePrefix { return lhsTitlePrefix }

                let lhsPathPrefix = lhsPath.hasPrefix(normalizedQuery)
                let rhsPathPrefix = rhsPath.hasPrefix(normalizedQuery)
                if lhsPathPrefix != rhsPathPrefix { return lhsPathPrefix }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(limit))
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

        let directoryURL = note.fileURL.deletingLastPathComponent()
        let newURL = Self.resolveConflict(for: "\(sanitized).md", in: directoryURL)

        guard CoordinatedFileManager.move(from: note.fileURL, to: newURL) else {
            logger.error("Failed to rename note to \(newURL.lastPathComponent)")
            return note
        }

        logger.info("Renamed note to \(newURL.lastPathComponent)")

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
            modifiedDate: folder.modifiedDate,
            folderCount: folder.folderCount,
            itemCount: folder.itemCount
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
            id = VaultDirectoryLoader.stableID(for: fileURL)
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
        let folderURL = directoryURL.appendingPathComponent(name)
        CoordinatedFileManager.createDirectory(at: folderURL)

        let folder = NotoFolder(
            id: VaultDirectoryLoader.stableID(for: folderURL),
            folderURL: folderURL,
            name: name,
            modifiedDate: Date(),
            folderCount: 0,
            itemCount: 0
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
