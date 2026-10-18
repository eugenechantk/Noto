import CryptoKit
import Foundation

/// Thumbnails kept on disk across launches, one small file per key.
///
/// A local file's key is its path + modified date + size — metadata iCloud
/// syncs even while the file itself is evicted — so a thumbnail seen once shows
/// again without downloading the media, and an edited file gets a new one.
public final class MediaThumbnailStore: @unchecked Sendable {
    public let directoryURL: URL
    private let maxEntries: Int
    private let lock = NSLock()

    public init(directoryURL: URL, maxEntries: Int = 2_000) {
        self.directoryURL = directoryURL
        self.maxEntries = max(1, maxEntries)
    }

    public static func key(forFile url: URL, modified: Date, size: Int) -> String {
        key(forFilePath: url.standardizedFileURL.path, modified: modified, size: size)
    }

    /// `path` can be any stable spelling of the file's location (e.g. relative
    /// to the app's home, which moves on reinstall).
    public static func key(forFilePath path: String, modified: Date, size: Int) -> String {
        "file|\(path)|\(Int(modified.timeIntervalSince1970 * 1000))|\(size)"
    }

    public static func key(forRemote url: URL) -> String {
        "url|\(url.absoluteString)"
    }

    public func data(for key: String) -> Data? {
        let file = fileURL(for: key)
        guard let data = try? Data(contentsOf: file) else { return nil }
        // Touch so pruning drops the least recently used first.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return data
    }

    public func store(_ data: Data, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: key), options: .atomic)
        pruneIfNeeded()
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent(digest).appendingPathExtension("thumb")
    }

    /// Keeps the newest `maxEntries`; runs on store, which is rare.
    private func pruneIfNeeded() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: keys),
              files.count > maxEntries else { return }
        let byAge = files.sorted {
            let a = (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return a < b
        }
        for file in byAge.prefix(files.count - maxEntries) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
