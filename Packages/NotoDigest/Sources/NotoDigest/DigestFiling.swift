import Foundation
import NotoVault

/// The four things you can do to a capture during a digest pass.
///
/// Ordering rule for every destructive path: **the inbox file is deleted only
/// after the destination write has returned success.** A failed append or create
/// leaves the capture exactly where it was, so a bad write can cost you a retry
/// but never the thought.
public struct DigestFiling: Sendable {
    /// The frontmatter key a snooze writes. `status:` is deliberately left as
    /// `inbox` so gbrain's cycle keeps typing the file as a note — only the
    /// digest honours this key.
    public static let snoozeKey = "snoozed_until"
    /// One week, per the digest's "don't show me this again until later" action.
    public static let defaultSnoozeInterval: TimeInterval = 7 * 24 * 60 * 60

    public enum FilingError: Error, Equatable {
        /// The capture could not be read — usually a dataless iCloud stub.
        case unreadable(String)
        /// The destination note does not exist (deleted between picking and filing).
        case targetMissing(String)
        /// A title that is blank, or sanitizes down to nothing.
        case invalidTitle
        case writeFailed(String)
        case deleteFailed(String)
        case changedSinceFiling(String)

        public var message: String {
            switch self {
            case .unreadable(let path): return "Couldn't read \(path) — it may still be downloading from iCloud."
            case .targetMissing(let path): return "\(path) no longer exists."
            case .invalidTitle: return "Give the note a title."
            case .writeFailed(let path): return "Couldn't write \(path)."
            case .deleteFailed(let path): return "Filed, but couldn't remove \(path) from the inbox."
            case .changedSinceFiling(let path): return "\(path) has changed since filing. Your newer changes were kept."
            }
        }
    }

    public let vaultURL: URL
    private let fileSystem: any VaultFileSystem
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        vaultURL: URL,
        fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.vaultURL = vaultURL.standardizedFileURL
        self.fileSystem = fileSystem
        self.now = now
        self.makeID = makeID
    }

    // MARK: - Snooze

    /// Hides the capture from the digest until `date` (a week out by default) by
    /// writing `snoozed_until:` into its frontmatter. Nothing else in the file
    /// changes — not the body, not the other keys, not `updated:` (a snooze is a
    /// triage decision, not an edit of the thought).
    ///
    /// Returns the date the capture will resurface.
    @discardableResult
    public func snooze(_ entry: DigestEntry, until date: Date? = nil) throws -> Date {
        guard let content = fileSystem.readString(from: entry.fileURL) else {
            throw FilingError.unreadable(entry.relativePath)
        }
        let wakeDate = date ?? now().addingTimeInterval(Self.defaultSnoozeInterval)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let updated = NoteFrontmatter.setting(Self.snoozeKey, to: formatter.string(from: wakeDate), in: content)
        // No frontmatter to write into: `setting` is a no-op, so the snooze would
        // silently do nothing. Fail loudly instead of lying to the caller.
        guard updated != content else { throw FilingError.writeFailed(entry.relativePath) }
        guard fileSystem.writeString(updated, to: entry.fileURL) else {
            throw FilingError.writeFailed(entry.relativePath)
        }
        return wakeDate
    }

    // MARK: - Add to an existing note

    /// Appends the capture to the end of the note at `targetURL`, stamps that
    /// note's `updated:`, then removes the capture from the inbox.
    @discardableResult
    public func append(_ entry: DigestEntry, toNoteAt targetURL: URL) throws -> URL {
        guard entry.isAvailable else { throw FilingError.unreadable(entry.relativePath) }
        let target = targetURL.standardizedFileURL
        guard fileSystem.fileExists(at: target) else {
            throw FilingError.targetMissing(relativePath(of: target))
        }
        guard let existing = fileSystem.readString(from: target) else {
            throw FilingError.unreadable(relativePath(of: target))
        }
        guard let body = try captureBody(of: entry) else { throw FilingError.unreadable(entry.relativePath) }

        // Not `VaultMarkdown.updateTimestamp` — that only knows `updated:`, and
        // notes written by the main Noto app use `modified:`, so appending to one
        // left it claiming a months-old write time.
        let merged = NoteFrontmatter.stampingExistingTimestamps(
            DigestMarkdown.appending(body, to: existing),
            to: now()
        )
        guard fileSystem.writeString(merged, to: target) else {
            throw FilingError.writeFailed(relativePath(of: target))
        }
        try removeFromInbox(entry)
        return target
    }

    // MARK: - Create a new note

    /// Writes the capture as a new note titled `title` inside `folderURL`,
    /// resolving filename collisions (`Title(2).md`), then removes the capture
    /// from the inbox. Pass the vault root to file at the top level.
    @discardableResult
    public func createNote(from entry: DigestEntry, title: String, inFolderAt folderURL: URL) throws -> URL {
        guard entry.isAvailable else { throw FilingError.unreadable(entry.relativePath) }
        guard let filename = DigestMarkdown.filename(forTitle: title) else { throw FilingError.invalidTitle }
        let folder = folderURL.standardizedFileURL

        if !fileSystem.fileExists(at: folder) {
            guard fileSystem.createDirectory(at: folder) else {
                throw FilingError.writeFailed(relativePath(of: folder))
            }
        }
        guard let body = try captureBody(of: entry) else { throw FilingError.unreadable(entry.relativePath) }

        let destination = VaultMarkdown.resolveFileConflict(for: filename, in: folder, fileSystem: fileSystem)
        let document = DigestMarkdown.newNoteDocument(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body,
            id: makeID(),
            date: now()
        )
        guard fileSystem.writeString(document, to: destination) else {
            throw FilingError.writeFailed(relativePath(of: destination))
        }
        try removeFromInbox(entry)
        return destination
    }

    /// Writes the capture as a new note **as written** inside `folderURL`: named
    /// from its first line (`DigestMarkdown.noteTitle(fromFirstLineOf:)`), with
    /// the Markdown unchanged and no heading added. Same ordering guarantee as
    /// `createNote`: the note is written first and the capture removed only
    /// after that succeeds.
    @discardableResult
    public func createNoteAsWritten(from entry: DigestEntry, inFolderAt folderURL: URL, body editedBody: String? = nil) throws -> URL {
        guard entry.isAvailable else { throw FilingError.unreadable(entry.relativePath) }
        guard let body = try editedBody ?? captureBody(of: entry) else { throw FilingError.unreadable(entry.relativePath) }
        guard let title = DigestMarkdown.noteTitle(fromFirstLineOf: body),
              let filename = DigestMarkdown.filename(forTitle: title) else { throw FilingError.invalidTitle }
        let folder = folderURL.standardizedFileURL

        if !fileSystem.fileExists(at: folder) {
            guard fileSystem.createDirectory(at: folder) else {
                throw FilingError.writeFailed(relativePath(of: folder))
            }
        }
        let destination = VaultMarkdown.resolveFileConflict(for: filename, in: folder, fileSystem: fileSystem)
        let document = DigestMarkdown.newNoteDocument(body: body, id: makeID(), date: now())
        guard fileSystem.writeString(document, to: destination) else {
            throw FilingError.writeFailed(relativePath(of: destination))
        }
        try removeFromInbox(entry)
        return destination
    }

    // MARK: - Discard

    /// A capture that was deleted, carrying enough to put it back.
    public struct DiscardedCapture: Equatable, Sendable {
        public let entry: DigestEntry
        /// The file's full original contents — frontmatter included, so a restore
        /// returns the exact bytes rather than a reconstruction.
        public let document: String
    }

    /// Deletes the capture and returns what it took, so the caller can offer an
    /// undo. Nothing else is written.
    ///
    /// The read happens before the delete; if the file cannot be read the delete
    /// still proceeds (an unreadable stub is not worth blocking on) but the
    /// returned document is empty and `canRestore` is false.
    @discardableResult
    public func discard(_ entry: DigestEntry) throws -> DiscardedCapture {
        let document = fileSystem.readString(from: entry.fileURL) ?? ""
        try removeFromInbox(entry)
        return DiscardedCapture(entry: entry, document: document)
    }

    /// Writes a discarded capture back where it came from.
    ///
    /// Refuses an empty document — restoring a capture whose body was never read
    /// would replace a real thought with a blank file, which is worse than the
    /// delete it is undoing.
    public func restore(_ discarded: DiscardedCapture) throws {
        guard !discarded.document.isEmpty else {
            throw FilingError.unreadable(discarded.entry.relativePath)
        }
        if fileSystem.fileExists(at: discarded.entry.fileURL),
           fileSystem.readString(from: discarded.entry.fileURL) != discarded.document {
            throw FilingError.changedSinceFiling(discarded.entry.relativePath)
        }
        let folderURL = discarded.entry.fileURL.deletingLastPathComponent()
        if !fileSystem.fileExists(at: folderURL) {
            guard fileSystem.createDirectory(at: folderURL) else {
                throw FilingError.writeFailed(relativePath(of: folderURL))
            }
        }
        guard fileSystem.writeString(discarded.document, to: discarded.entry.fileURL) else {
            throw FilingError.writeFailed(discarded.entry.relativePath)
        }
    }

    /// A safe undo receipt. The destination is reverted only while its exact
    /// post-filing contents remain unchanged; later edits are never overwritten.
    public struct UndoReceipt: Equatable, Sendable {
        public let capture: DiscardedCapture
        public let destinationURL: URL?
        public let destinationBefore: String?
        public let destinationAfter: String?
    }

    public struct SnoozedCapture: Equatable, Sendable {
        public let entry: DigestEntry
        public let previousValue: String?
        public let writtenValue: String
        public let wakeDate: Date
    }

    public func snoozeWithUndo(_ entry: DigestEntry, until date: Date? = nil) throws -> SnoozedCapture {
        guard let original = fileSystem.readString(from: entry.fileURL) else { throw FilingError.unreadable(entry.relativePath) }
        let wake = try snooze(entry, until: date)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return SnoozedCapture(entry: entry, previousValue: NoteFrontmatter.value(for: Self.snoozeKey, in: original),
                              writtenValue: formatter.string(from: wake), wakeDate: wake)
    }

    public func undoSnooze(_ receipt: SnoozedCapture) throws {
        guard let document = fileSystem.readString(from: receipt.entry.fileURL) else { throw FilingError.unreadable(receipt.entry.relativePath) }
        guard NoteFrontmatter.value(for: Self.snoozeKey, in: document) == receipt.writtenValue else {
            throw FilingError.changedSinceFiling(receipt.entry.relativePath)
        }
        let restored: String
        if let previous = receipt.previousValue {
            restored = NoteFrontmatter.setting(Self.snoozeKey, to: previous, in: document)
        } else {
            restored = NoteFrontmatter.removing(Self.snoozeKey, in: document)
        }
        guard fileSystem.writeString(restored, to: receipt.entry.fileURL) else { throw FilingError.writeFailed(receipt.entry.relativePath) }
    }

    public func appendWithUndo(_ entry: DigestEntry, toNoteAt target: URL) throws -> UndoReceipt {
        let capture = try snapshot(entry)
        guard let before = fileSystem.readString(from: target) else { throw FilingError.unreadable(relativePath(of: target)) }
        let destination = try append(entry, toNoteAt: target)
        guard let after = fileSystem.readString(from: destination) else { throw FilingError.unreadable(relativePath(of: destination)) }
        return UndoReceipt(capture: capture, destinationURL: destination, destinationBefore: before, destinationAfter: after)
    }

    public func createWithUndo(_ entry: DigestEntry, inFolderAt folder: URL, body: String? = nil) throws -> UndoReceipt {
        let capture = try snapshot(entry)
        let destination = try createNoteAsWritten(from: entry, inFolderAt: folder, body: body)
        guard let after = fileSystem.readString(from: destination) else { throw FilingError.unreadable(relativePath(of: destination)) }
        return UndoReceipt(capture: capture, destinationURL: destination, destinationBefore: nil, destinationAfter: after)
    }

    public func undo(_ receipt: UndoReceipt) throws {
        if let target = receipt.destinationURL {
            guard fileSystem.readString(from: target) == receipt.destinationAfter else {
                throw FilingError.changedSinceFiling(relativePath(of: target))
            }
        }
        // Refuse to overwrite a capture that reappeared through iCloud. An
        // identical restored copy is safe when retrying a previous failed undo.
        if fileSystem.fileExists(at: receipt.capture.entry.fileURL),
           fileSystem.readString(from: receipt.capture.entry.fileURL) != receipt.capture.document {
            throw FilingError.changedSinceFiling(receipt.capture.entry.relativePath)
        }
        try restore(receipt.capture)
        if let target = receipt.destinationURL {
            if let original = receipt.destinationBefore {
                guard fileSystem.writeString(original, to: target) else { throw FilingError.writeFailed(relativePath(of: target)) }
            } else {
                guard fileSystem.delete(at: target) else { throw FilingError.deleteFailed(relativePath(of: target)) }
            }
        }
    }

    private func snapshot(_ entry: DigestEntry) throws -> DiscardedCapture {
        guard let document = fileSystem.readString(from: entry.fileURL), !document.isEmpty else {
            throw FilingError.unreadable(entry.relativePath)
        }
        return DiscardedCapture(entry: entry, document: document)
    }

    /// Saves an edited capture while retaining its frontmatter and identity.
    public func updateBody(_ body: String, of entry: DigestEntry) throws {
        guard let original = fileSystem.readString(from: entry.fileURL) else { throw FilingError.unreadable(entry.relativePath) }
        let oldBody = VaultMarkdown.stripFrontmatter(original)
        let prefix = String(original.prefix(original.count - oldBody.count))
        let document = NoteFrontmatter.stampingExistingTimestamps(prefix + body, to: now())
        guard fileSystem.writeString(document, to: entry.fileURL) else { throw FilingError.writeFailed(entry.relativePath) }
    }

    // MARK: - Helpers

    /// Re-reads the capture at filing time rather than trusting the in-memory
    /// entry: the digest can sit on screen for minutes while iCloud syncs an edit
    /// from another device, and filing stale text would silently lose it.
    private func captureBody(of entry: DigestEntry) throws -> String? {
        guard let content = fileSystem.readString(from: entry.fileURL) else { return nil }
        let body = VaultMarkdown.stripFrontmatter(content).trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? entry.body : body
    }

    private func removeFromInbox(_ entry: DigestEntry) throws {
        guard fileSystem.fileExists(at: entry.fileURL) else { return }
        guard fileSystem.delete(at: entry.fileURL) else {
            throw FilingError.deleteFailed(entry.relativePath)
        }
    }

    private func relativePath(of url: URL) -> String {
        let root = vaultURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root) else { return url.lastPathComponent }
        return String(path.dropFirst(root.count).drop { $0 == "/" })
    }
}
