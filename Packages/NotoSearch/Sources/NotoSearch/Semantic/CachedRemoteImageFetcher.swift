import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import os.log

private let fetcherLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.noto.NotoSearch",
    category: "CachedRemoteImageFetcher"
)

/// Default `RemoteImageFetching` implementation: a disk-cached, synchronous
/// HTTP fetcher.
///
/// The image-indexing pipeline is a synchronous walk on a background queue, so
/// `fetch(url:)` blocks the calling thread with a semaphore around a
/// `URLSession` data task (the completion fires on the session's own queue, so
/// no deadlock). Cache entries are keyed by the SHA-256 of the absolute URL
/// string and written atomically; failures are never cached, so transient
/// outages retry naturally on the next indexing pass.
public final class CachedRemoteImageFetcher: RemoteImageFetching, @unchecked Sendable {
    /// Hard cap on accepted payloads — anything larger is not a note image.
    private static let maxImageBytes = 20 * 1024 * 1024

    public let cacheDirectory: URL
    private let session: URLSession
    private let timeout: TimeInterval

    public init(cacheDirectory: URL? = nil, session: URLSession = .shared, timeout: TimeInterval = 4) {
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory()
        self.session = session
        self.timeout = timeout
    }

    // MARK: - RemoteImageFetching

    private let failedLock = NSLock()
    nonisolated(unsafe) private var failedURLs = Set<String>()

    private func markFailed(_ url: URL) {
        failedLock.lock()
        failedURLs.insert(url.absoluteString)
        failedLock.unlock()
    }

    private func hasFailed(_ url: URL) -> Bool {
        failedLock.lock()
        defer { failedLock.unlock() }
        return failedURLs.contains(url.absoluteString)
    }

    public func fetch(url: URL) -> Data? {
        if let cached = cachedData(for: url) {
            return cached
        }
        // A URL that already failed this session fails fast: dead links in a
        // large vault otherwise cost a full network timeout at every
        // re-encounter during the initial sweep.
        guard !hasFailed(url) else { return nil }
        guard let (data, response) = downloadSynchronously(url) else {
            markFailed(url)
            return nil
        }
        guard response.statusCode == 200 else {
            fetcherLogger.debug("skip \(url.absoluteString, privacy: .public): HTTP \(response.statusCode)")
            markFailed(url)
            return nil
        }
        guard !data.isEmpty, data.count <= Self.maxImageBytes else {
            fetcherLogger.debug("skip \(url.absoluteString, privacy: .public): \(data.count) bytes out of bounds")
            markFailed(url)
            return nil
        }
        let isImageContentType = response.mimeType?.lowercased().hasPrefix("image/") ?? false
        guard isImageContentType || Self.isDecodableImage(data) else {
            fetcherLogger.debug("skip \(url.absoluteString, privacy: .public): not an image payload")
            markFailed(url)
            return nil
        }
        writeCache(data, for: url)
        return data
    }

    // MARK: - Cache

    public func cachedData(for url: URL) -> Data? {
        let file = cacheFileURL(for: url)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try? Data(contentsOf: file)
    }

    private func cacheFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(name, isDirectory: false)
    }

    private func writeCache(_ data: Data, for url: URL) {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: cacheFileURL(for: url), options: .atomic)
        } catch {
            // Caching is best-effort; the fetched data is still returned.
            fetcherLogger.error("cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Noto", isDirectory: true)
            .appendingPathComponent("RemoteImageCache", isDirectory: true)
    }

    // MARK: - Download

    /// Blocks until the data task completes (or `timeout` + grace elapses).
    private func downloadSynchronously(_ url: URL) -> (Data, HTTPURLResponse)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        final class ResultBox: @unchecked Sendable {
            var data: Data?
            var response: URLResponse?
            var error: Error?
        }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            semaphore.signal()
        }
        task.resume()

        // The request's own timeout normally fires first; the extra grace here
        // only guards against a pathological session that never calls back.
        if semaphore.wait(timeout: .now() + timeout + 5) == .timedOut {
            task.cancel()
            fetcherLogger.error("download timed out: \(url.absoluteString, privacy: .public)")
            return nil
        }
        if let error = box.error {
            fetcherLogger.debug("download failed \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let data = box.data, let http = box.response as? HTTPURLResponse else { return nil }
        return (data, http)
    }

    /// Fallback acceptance for servers that lie about Content-Type: the bytes
    /// count as an image if ImageIO can identify and open them.
    private static func isDecodableImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
    }
}
