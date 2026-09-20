import Foundation
import Testing
@testable import NotoLinkPreview

/// Disk + memory persistence of preview metadata (SC4).
///
/// | Test | Covers |
/// | --- | --- |
/// | `metadataRoundTripsThroughDisk` | a fresh cache instance reads what another wrote |
/// | `failureIsRememberedUntilRetryWindowPasses` | dead links are not refetched every open |
/// | `staleMetadataReadsAsMissing` | expired successes fall through to a refetch |
/// | `corruptFileReadsAsMissing` | a bad JSON file never crashes or poisons the cache |
/// | `removeForgetsOneURL` | `remove(for:)` clears memory and disk |
/// | `keyIsStablePerURL` | file name is deterministic and safe for the filesystem |
@Suite("LinkPreviewCache")
struct LinkPreviewCacheTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoLinkPreviewCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private let url = URL(string: "https://example.com/article")!

    @Test("metadata round-trips through disk")
    func metadataRoundTripsThroughDisk() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let metadata = LinkPreviewMetadata(
            url: url,
            title: "An Article",
            summary: "About things.",
            host: "example.com",
            imageData: Data([0x01, 0x02, 0x03]),
            iconData: Data([0x09]),
            fetchedAt: recentWholeSecondDate()
        )

        LinkPreviewCache(directoryURL: directory).store(.metadata(metadata), for: url)

        let reloaded = LinkPreviewCache(directoryURL: directory).entry(for: url)
        #expect(reloaded == .metadata(metadata))
    }

    @Test("failure is remembered until the retry window passes")
    func failureIsRememberedUntilRetryWindowPasses() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = MutableClock(now: start)
        let cache = LinkPreviewCache(
            directoryURL: directory,
            failureRetryInterval: 60,
            now: { clock.now }
        )

        cache.store(.failure(start), for: url)
        #expect(cache.entry(for: url) == .failure(start))

        clock.now = start.addingTimeInterval(61)
        #expect(cache.entry(for: url) == nil)
    }

    @Test("stale metadata reads as missing")
    func staleMetadataReadsAsMissing() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = MutableClock(now: fetchedAt)
        let cache = LinkPreviewCache(directoryURL: directory, successTTL: 100, now: { clock.now })
        cache.store(.metadata(LinkPreviewMetadata(url: url, host: "example.com", fetchedAt: fetchedAt)), for: url)

        clock.now = fetchedAt.addingTimeInterval(99)
        #expect(cache.entry(for: url) != nil)

        clock.now = fetchedAt.addingTimeInterval(101)
        #expect(cache.entry(for: url) == nil)
    }

    @Test("corrupt file reads as missing")
    func corruptFileReadsAsMissing() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = LinkPreviewCache(directoryURL: directory)
        try Data("not json".utf8).write(to: cache.fileURL(for: LinkPreviewCache.key(for: url)))

        #expect(cache.entry(for: url) == nil)
    }

    @Test("remove forgets one URL")
    func removeForgetsOneURL() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let other = URL(string: "https://example.com/other")!
        let cache = LinkPreviewCache(directoryURL: directory)
        cache.store(.failure(Date()), for: url)
        cache.store(.failure(Date()), for: other)

        cache.remove(for: url)

        #expect(cache.entry(for: url) == nil)
        #expect(cache.entry(for: other) != nil)
        #expect(LinkPreviewCache(directoryURL: directory).entry(for: url) == nil)
    }

    @Test("key is stable per URL")
    func keyIsStablePerURL() {
        let key = LinkPreviewCache.key(for: url)
        #expect(key == LinkPreviewCache.key(for: url))
        #expect(key != LinkPreviewCache.key(for: URL(string: "https://example.com/article?x")!))
        #expect(key.count == 64)
        #expect(key.allSatisfy { $0.isHexDigit })
    }
}

final class MutableClock: @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}

/// A "now" that survives ISO 8601 round-tripping (no fractional seconds) and sits
/// well inside the cache's success TTL.
func recentWholeSecondDate() -> Date {
    Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
}
