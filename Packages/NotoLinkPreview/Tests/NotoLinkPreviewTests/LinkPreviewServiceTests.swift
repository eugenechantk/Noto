import Foundation
import Testing
@testable import NotoLinkPreview

/// The fetch coordinator the editor talks to (SC4).
///
/// | Test | Covers |
/// | --- | --- |
/// | `firstRequestStartsOneFetchAndReportsLoading` | uncached URL → `.loading` + one fetch |
/// | `concurrentRequestsShareOneFetch` | single-flight: N requests, 1 fetch |
/// | `successIsCachedAndAnnounced` | result lands in cache, notification carries the URL |
/// | `cachedMetadataSkipsTheFetcher` | second service on same disk cache never fetches |
/// | `failureIsCachedAndReportedAsFailed` | thrown error → `.failed`, no refetch inside window |
/// | `cachedMetadataDoesNotTriggerFetch` | `cachedMetadata(for:)` is a pure read |
@Suite("LinkPreviewService")
@MainActor
struct LinkPreviewServiceTests {
    private let url = URL(string: "https://example.com/article")!

    private func makeCache() throws -> LinkPreviewCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoLinkPreviewServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LinkPreviewCache(directoryURL: directory)
    }

    @Test("first request starts one fetch and reports loading")
    func firstRequestStartsOneFetchAndReportsLoading() async throws {
        let cache = try makeCache()
        defer { cache.removeAll() }
        let fetcher = FakeFetcher(result: .success(sample()))
        let service = LinkPreviewService(cache: cache, fetcher: fetcher, notificationCenter: NotificationCenter())

        #expect(service.state(for: url) == .loading)
        #expect(service.isFetching)
        await service.waitForPendingFetches()

        #expect(service.fetchCount == 1)
        #expect(fetcher.calls == [url])
        #expect(service.state(for: url) == .loaded(sample()))
    }

    @Test("concurrent requests share one fetch")
    func concurrentRequestsShareOneFetch() async throws {
        let cache = try makeCache()
        defer { cache.removeAll() }
        let fetcher = FakeFetcher(result: .success(sample()))
        fetcher.holdUntilReleased = true
        let service = LinkPreviewService(cache: cache, fetcher: fetcher, notificationCenter: NotificationCenter())

        _ = service.state(for: url)
        _ = service.state(for: url)
        _ = service.state(for: url)
        fetcher.release()
        await service.waitForPendingFetches()

        #expect(service.fetchCount == 1)
        #expect(fetcher.calls.count == 1)
    }

    @Test("success is cached and announced")
    func successIsCachedAndAnnounced() async throws {
        let cache = try makeCache()
        defer { cache.removeAll() }
        let center = NotificationCenter()
        let fetcher = FakeFetcher(result: .success(sample()))
        let service = LinkPreviewService(cache: cache, fetcher: fetcher, notificationCenter: center)

        let received = NotificationSink(center: center, name: LinkPreviewService.didChangeNotification)
        _ = service.state(for: url)
        await service.waitForPendingFetches()

        #expect(cache.entry(for: url) == .metadata(sample()))
        #expect(received.urls == [url])
        #expect(!service.isFetching)
    }

    @Test("cached metadata skips the fetcher")
    func cachedMetadataSkipsTheFetcher() async throws {
        let cache = try makeCache()
        defer { cache.removeAll() }
        cache.store(.metadata(sample()), for: url)
        let fetcher = FakeFetcher(result: .success(sample()))
        let service = LinkPreviewService(cache: cache, fetcher: fetcher, notificationCenter: NotificationCenter())

        #expect(service.state(for: url) == .loaded(sample()))
        #expect(service.fetchCount == 0)
        #expect(fetcher.calls.isEmpty)
    }

    @Test("failure is cached and reported as failed")
    func failureIsCachedAndReportedAsFailed() async throws {
        let cache = try makeCache()
        defer { cache.removeAll() }
        let fetcher = FakeFetcher(result: .failure(LinkPreviewFetchError.noMetadata))
        let service = LinkPreviewService(cache: cache, fetcher: fetcher, notificationCenter: NotificationCenter())

        #expect(service.state(for: url) == .loading)
        await service.waitForPendingFetches()

        #expect(service.state(for: url) == .failed)
        #expect(service.state(for: url) == .failed)
        #expect(service.fetchCount == 1)
        guard case .failure? = cache.entry(for: url) else {
            Issue.record("Expected a failure entry in the cache")
            return
        }
    }

    @Test("cachedMetadata does not trigger a fetch")
    func cachedMetadataDoesNotTriggerFetch() throws {
        let cache = try makeCache()
        defer { cache.removeAll() }
        let fetcher = FakeFetcher(result: .success(sample()))
        let service = LinkPreviewService(cache: cache, fetcher: fetcher, notificationCenter: NotificationCenter())

        #expect(service.cachedMetadata(for: url) == nil)
        #expect(service.fetchCount == 0)
        #expect(!service.isFetching)
    }

    private func sample() -> LinkPreviewMetadata {
        LinkPreviewMetadata(
            url: url,
            title: "Sample",
            summary: "Summary",
            host: "example.com",
            fetchedAt: recentWholeSecondDate()
        )
    }
}

// MARK: - Test doubles

final class FakeFetcher: LinkPreviewFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<LinkPreviewMetadata, Error>
    private(set) var calls: [URL] = []
    var holdUntilReleased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    init(result: Result<LinkPreviewMetadata, Error>) {
        self.result = result
    }

    func fetch(_ url: URL) async throws -> LinkPreviewMetadata {
        lock.lock()
        calls.append(url)
        let shouldWait = holdUntilReleased && !released
        lock.unlock()

        if shouldWait {
            await withCheckedContinuation { continuation in
                lock.lock()
                if released {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                    lock.unlock()
                }
            }
        }
        return try result.get()
    }

    func release() {
        lock.lock()
        released = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

final class NotificationSink: @unchecked Sendable {
    private(set) var urls: [URL] = []
    private var token: NSObjectProtocol?

    init(center: NotificationCenter, name: Notification.Name) {
        token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
            if let url = notification.userInfo?[LinkPreviewService.urlUserInfoKey] as? URL {
                self?.urls.append(url)
            }
        }
    }
}
