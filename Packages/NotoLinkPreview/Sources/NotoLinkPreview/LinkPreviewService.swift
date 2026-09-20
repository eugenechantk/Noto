import Foundation

/// Editor-facing entry point. `state(for:)` answers synchronously from the cache and,
/// when nothing usable is cached, starts one fetch per URL in the background. Every
/// change (success or failure) is announced through `didChangeNotification` so any
/// editor showing that URL can refresh its card.
@MainActor
public final class LinkPreviewService {
    public enum State: Equatable, Sendable {
        case loading
        case loaded(LinkPreviewMetadata)
        case failed
    }

    public static let didChangeNotification = Notification.Name("NotoLinkPreview.didChange")
    public static let urlUserInfoKey = "url"

    public let cache: LinkPreviewCache
    private let fetcher: any LinkPreviewFetching
    private let notificationCenter: NotificationCenter
    private var inFlight: [URL: Task<Void, Never>] = [:]
    /// Number of fetches started over the service's lifetime (tests read this).
    public private(set) var fetchCount = 0

    public init(
        cache: LinkPreviewCache,
        fetcher: any LinkPreviewFetching,
        notificationCenter: NotificationCenter = .default
    ) {
        self.cache = cache
        self.fetcher = fetcher
        self.notificationCenter = notificationCenter
    }

    /// Current state for `url`, starting a fetch if needed.
    public func state(for url: URL) -> State {
        if let entry = cache.entry(for: url) {
            switch entry {
            case .metadata(let metadata):
                return .loaded(metadata)
            case .failure:
                return .failed
            }
        }

        startFetchIfNeeded(url)
        return .loading
    }

    /// Cached metadata without triggering a fetch.
    public func cachedMetadata(for url: URL) -> LinkPreviewMetadata? {
        if case .metadata(let metadata)? = cache.entry(for: url) {
            return metadata
        }
        return nil
    }

    public var isFetching: Bool {
        !inFlight.isEmpty
    }

    /// Awaits every fetch that is currently running. Tests use it; the editor never needs to.
    public func waitForPendingFetches() async {
        for task in Array(inFlight.values) {
            await task.value
        }
    }

    private func startFetchIfNeeded(_ url: URL) {
        guard inFlight[url] == nil else { return }
        fetchCount += 1

        let fetcher = self.fetcher
        let task = Task { [weak self] in
            let result: Result<LinkPreviewMetadata, Error>
            do {
                result = .success(try await fetcher.fetch(url))
            } catch {
                result = .failure(error)
            }
            self?.finishFetch(url, result: result)
        }
        inFlight[url] = task
    }

    private func finishFetch(_ url: URL, result: Result<LinkPreviewMetadata, Error>) {
        switch result {
        case .success(let metadata):
            cache.store(.metadata(metadata), for: url)
        case .failure:
            cache.store(.failure(Date()), for: url)
        }
        inFlight.removeValue(forKey: url)
        notificationCenter.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: [Self.urlUserInfoKey: url]
        )
    }
}
