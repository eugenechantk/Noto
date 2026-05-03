import Foundation
import os.log

private let pendingIndexLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.noto.NotoSearch",
    category: "PendingIndexQueue"
)

/// One unit of work the search index promises to perform for a specific file.
public struct PendingIndexEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Action: String, Codable, Sendable {
        case refresh
        case delete
    }

    public let id: UUID
    public let url: URL
    public let action: Action
    public let queuedAt: Date

    public init(id: UUID = UUID(), url: URL, action: Action, queuedAt: Date = Date()) {
        self.id = id
        self.url = url.standardizedFileURL
        self.action = action
        self.queuedAt = queuedAt
    }
}

/// Crash-safe FIFO queue of pending search-index work for a single vault.
///
/// Entries persist in `<indexDir>/pending-index.json` via atomic writes. Every
/// write site enqueues *before* invoking the indexer, and consumes the entry
/// only after the SQLite transaction commits. If the app dies in between, the
/// next launch's `drain` re-runs the action.
public actor PendingIndexQueue {
    private let queueURL: URL
    private let fileManager: FileManager
    private var entries: [PendingIndexEntry]

    public init(indexDirectory: URL, fileManager: FileManager = .default) throws {
        self.queueURL = indexDirectory.appendingPathComponent("pending-index.json")
        self.fileManager = fileManager
        try fileManager.createDirectory(
            at: indexDirectory,
            withIntermediateDirectories: true
        )
        self.entries = Self.load(from: queueURL, fileManager: fileManager)
    }

    public func pending() -> [PendingIndexEntry] {
        entries
    }

    /// Append a new entry and persist immediately. Returns the persisted entry
    /// so the caller can match it back when consuming.
    @discardableResult
    public func enqueue(_ url: URL, action: PendingIndexEntry.Action) throws -> PendingIndexEntry {
        let entry = PendingIndexEntry(url: url, action: action)
        entries.append(entry)
        try persist()
        return entry
    }

    /// Remove the entry with the given id and persist. Idempotent — a missing
    /// id (e.g. already-consumed) is a no-op.
    public func consume(_ entryID: UUID) throws {
        guard entries.contains(where: { $0.id == entryID }) else { return }
        entries.removeAll { $0.id == entryID }
        try persist()
    }

    /// Discard every queued entry and remove the on-disk file. Used when the
    /// caller is about to nuke the index entirely (any pending work would be
    /// stale anyway).
    public func clear() throws {
        guard !entries.isEmpty || fileManager.fileExists(atPath: queueURL.path) else { return }
        entries.removeAll()
        try persist()
    }

    /// Drain everything currently queued by passing each entry to `handler`.
    /// On a successful `handler` call (no thrown error) the entry is consumed.
    /// On failure, the entry is left in the queue for the next drain attempt
    /// and the loop continues with the next entry.
    public func drain(handler: (PendingIndexEntry) async throws -> Void) async {
        let snapshot = entries
        for entry in snapshot {
            do {
                try await handler(entry)
                try? consume(entry.id)
            } catch {
                pendingIndexLogger.error(
                    "Drain handler failed for \(entry.url.lastPathComponent, privacy: .public) action=\(entry.action.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    // MARK: - Persistence

    private func persist() throws {
        if entries.isEmpty {
            if fileManager.fileExists(atPath: queueURL.path) {
                try fileManager.removeItem(at: queueURL)
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try data.write(to: queueURL, options: [.atomic])
    }

    private static func load(from url: URL, fileManager: FileManager) -> [PendingIndexEntry] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([PendingIndexEntry].self, from: data)
        } catch {
            pendingIndexLogger.error(
                "Failed to load pending index queue at \(url.path, privacy: .public) — discarding: \(String(describing: error), privacy: .public)"
            )
            return []
        }
    }
}
