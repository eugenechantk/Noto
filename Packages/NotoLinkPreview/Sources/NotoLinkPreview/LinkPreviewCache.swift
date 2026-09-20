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

        guard let entry, isLive(entry) else { return nil }
        return entry
    }

    public func store(_ entry: Entry, for url: URL) {
        let key = Self.key(for: url)
        lock.lock()
        memory[key] = entry
        lock.unlock()
        writeToDisk(entry, key: key)
    }

    public func remove(for url: URL) {
        let key = Self.key(for: url)
        lock.lock()
        memory.removeValue(forKey: key)
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    public func removeAll() {
        lock.lock()
        memory.removeAll()
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
