import CryptoKit
import Foundation

/// Memory + disk cache of preview metadata, one JSON file per URL.
///
/// Successful entries expire after `successTTL`; failures are remembered for
/// `failureRetryInterval` so a dead link is not re-fetched every time a note opens.
/// Expired entries read back as `nil`, which is the service's cue to fetch again.
public final class LinkPreviewCache: @unchecked Sendable {
    public enum Entry: Codable, Equatable, Sendable {
        case metadata(LinkPreviewMetadata)
        case failure(Date)
    }

    public let directoryURL: URL
    public let successTTL: TimeInterval
    public let failureRetryInterval: TimeInterval

    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var memory: [String: Entry] = [:]
    private var searchMemory: [String: String] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        directoryURL: URL,
        successTTL: TimeInterval = 30 * 24 * 60 * 60,
        failureRetryInterval: TimeInterval = 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directoryURL = directoryURL
        self.successTTL = successTTL
        self.failureRetryInterval = failureRetryInterval
        self.now = now
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Live entry for `url`, or `nil` when there is none or it has expired.
    public func entry(for url: URL) -> Entry? {
        guard let entry = storedEntry(for: url), isLive(entry) else { return nil }
        return entry
    }

    /// Read-only search projection of saved metadata. Display expiry requests
    /// a refresh, but must not make previously saved words disappear offline.
    /// Missing/failed entries contribute no metadata and never initiate a fetch.
    public func searchText(for url: URL) -> String? {
        let key = Self.key(for: url)
        lock.lock()
        let cachedText = searchMemory[key]
        lock.unlock()
        if let cachedText { return cachedText }
        // The lightweight last-success projection survives a failed preview
        // refresh, without retaining image bytes in the search index.
        if let savedText = try? String(contentsOf: searchFileURL(for: key), encoding: .utf8) {
            lock.lock()
            let currentText = searchMemory[key] ?? savedText
            searchMemory[key] = currentText
            lock.unlock()
            return currentText
        }
        guard case .metadata(let metadata)? = storedEntry(for: url) else { return nil }
        return Self.searchText(for: metadata)
    }

    private static func searchText(for metadata: LinkPreviewMetadata) -> String {
        return [metadata.title, metadata.summary, metadata.host, metadata.url.absoluteString]
            .compactMap { $0 }.joined(separator: "\n")
    }

    private func storedEntry(for url: URL) -> Entry? {
        let key = Self.key(for: url)

        lock.lock()
        let cached = memory[key]
        lock.unlock()

        let entry: Entry?
        if let cached {
            entry = cached
        } else if let loaded = loadFromDisk(key: key) {
            lock.lock()
            memory[key] = loaded
            lock.unlock()
            entry = loaded
        } else {
            entry = nil
        }

        return entry
    }

    public func store(_ entry: Entry, for url: URL) {
        let key = Self.key(for: url)
        let text: String?
        if case .metadata(let metadata) = entry {
            text = Self.searchText(for: metadata)
        } else if case .metadata(let previous)? = storedEntry(for: url) {
            // Migrate an older cache entry before a failed refetch replaces it.
            text = Self.searchText(for: previous)
        } else { text = nil }
        lock.lock()
        memory[key] = entry
        if let text { searchMemory[key] = text }
        lock.unlock()
        writeToDisk(entry, key: key)
        if let text {
            try? text.write(to: searchFileURL(for: key), atomically: true, encoding: .utf8)
        }
    }

    public func remove(for url: URL) {
        let key = Self.key(for: url)
        lock.lock()
        memory.removeValue(forKey: key)
        searchMemory.removeValue(forKey: key)
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL(for: key))
        try? FileManager.default.removeItem(at: searchFileURL(for: key))
    }

    public func removeAll() {
        lock.lock()
        memory.removeAll()
        searchMemory.removeAll()
        lock.unlock()
        try? FileManager.default.removeItem(at: directoryURL)
    }

    // MARK: - Internals

    private func isLive(_ entry: Entry) -> Bool {
        let current = now()
        switch entry {
        case .metadata(let metadata):
            return current.timeIntervalSince(metadata.fetchedAt) < successTTL
        case .failure(let failedAt):
            return current.timeIntervalSince(failedAt) < failureRetryInterval
        }
    }

    static func key(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func fileURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(key).appendingPathExtension("json")
    }

    private func searchFileURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(key).appendingPathExtension("search.txt")
    }

    private func loadFromDisk(key: String) -> Entry? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? decoder.decode(Entry.self, from: data)
    }

    private func writeToDisk(_ entry: Entry, key: String) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(entry)
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            // Disk is a best-effort tier; memory still holds the entry for this run.
        }
    }
}
