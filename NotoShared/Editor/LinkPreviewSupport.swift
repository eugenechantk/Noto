import Foundation
import NotoLinkPreview

/// The one `LinkPreviewService` both apps share. Metadata is cached under the app's
/// Caches directory so a purge costs nothing but a refetch.
enum LinkPreviewSupport {
    @MainActor
    static let service: LinkPreviewService = {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let cache = LinkPreviewCache(directoryURL: cachesDirectory.appendingPathComponent("LinkPreviews", isDirectory: true))
        return LinkPreviewService(cache: cache, fetcher: LinkPresentationFetcher())
    }()
}
