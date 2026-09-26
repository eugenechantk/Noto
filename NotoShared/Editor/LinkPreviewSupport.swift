import Foundation
import NotoLinkPreview

/// The one `LinkPreviewService` both apps share: `LinkPresentation`, with the page's
/// Open Graph tags filling what it misses. Metadata is cached under the app's
/// Caches directory so a purge costs nothing but a refetch.
enum LinkPreviewSupport {
    @MainActor
    static let service: LinkPreviewService = {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let cache = LinkPreviewCache(directoryURL: cachesDirectory.appendingPathComponent("LinkPreviews", isDirectory: true))
        let fetcher = CompositeLinkPreviewFetcher(primary: LinkPresentationFetcher(), secondary: OpenGraphFetcher())
        return LinkPreviewService(cache: cache, fetcher: fetcher)
    }()
}
