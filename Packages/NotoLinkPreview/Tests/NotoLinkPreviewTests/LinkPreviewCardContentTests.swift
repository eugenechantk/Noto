import Foundation
import Testing
@testable import NotoLinkPreview

/// What the card says in each state (SC5).
///
/// | Test | Covers |
/// | --- | --- |
/// | `loadingShowsHostAndLoadingLine` | before metadata arrives |
/// | `failedShowsReadableURLAndUnavailableLine` | fetch failed |
/// | `loadedUsesTitleSummaryHostAndImage` | the happy path |
/// | `loadedWithoutTitleFallsBackToURL` | pages with no `<title>` / og:title |
/// | `blankSummaryIsDropped` | whitespace-only descriptions render nothing |
/// | `displayHostStripsWWW` | `www.` never shows |
/// | `displayURLStripsSchemeAndTrailingSlash` | URL fallback reads cleanly |
@Suite("LinkPreviewCardContent")
struct LinkPreviewCardContentTests {
    private let url = URL(string: "https://www.example.com/article/")!

    @Test("loading shows host and loading line")
    func loadingShowsHostAndLoadingLine() {
        let content = LinkPreviewCardContent.make(url: url, state: .loading)
        #expect(content.title == "example.com")
        #expect(content.subtitle == LinkPreviewCardContent.loadingSubtitle)
        #expect(content.host == "example.com")
        #expect(!content.hasImage)
    }

    @Test("failed shows readable URL and unavailable line")
    func failedShowsReadableURLAndUnavailableLine() {
        let content = LinkPreviewCardContent.make(url: url, state: .failed)
        #expect(content.title == "example.com/article")
        #expect(content.subtitle == LinkPreviewCardContent.unavailableSubtitle)
        #expect(content.host == "example.com")
    }

    @Test("loaded uses title, summary, host and image")
    func loadedUsesTitleSummaryHostAndImage() {
        let metadata = LinkPreviewMetadata(
            url: url,
            title: "  An Article  ",
            summary: "About things.",
            host: "example.com",
            imageData: Data([1, 2]),
            iconData: Data([3])
        )
        let content = LinkPreviewCardContent.make(url: url, state: .loaded(metadata))
        #expect(content.title == "An Article")
        #expect(content.subtitle == "About things.")
        #expect(content.host == "example.com")
        #expect(content.hasImage)
        #expect(content.hasIcon)
    }

    @Test("loaded without title falls back to URL")
    func loadedWithoutTitleFallsBackToURL() {
        let metadata = LinkPreviewMetadata(url: url, title: nil, host: "example.com")
        let content = LinkPreviewCardContent.make(url: url, state: .loaded(metadata))
        #expect(content.title == "example.com/article")
        #expect(content.subtitle == nil)
    }

    @Test("blank summary is dropped")
    func blankSummaryIsDropped() {
        let metadata = LinkPreviewMetadata(url: url, title: "T", summary: "   \n ", host: "example.com")
        let content = LinkPreviewCardContent.make(url: url, state: .loaded(metadata))
        #expect(content.subtitle == nil)
    }

    @Test("display host strips www")
    func displayHostStripsWWW() {
        #expect(LinkPreviewMetadata.displayHost(for: url) == "example.com")
        #expect(LinkPreviewMetadata.displayHost(for: URL(string: "https://blog.example.com")!) == "blog.example.com")
        #expect(LinkPreviewMetadata.displayHost(for: URL(string: "https://WWW.Example.COM")!) == "example.com")
    }

    @Test("display URL strips scheme and trailing slash")
    func displayURLStripsSchemeAndTrailingSlash() {
        #expect(LinkPreviewCardContent.displayURL(url) == "example.com/article")
        #expect(LinkPreviewCardContent.displayURL(URL(string: "http://example.com/a?b=1")!) == "example.com/a?b=1")
        #expect(LinkPreviewCardContent.displayURL(URL(string: "https://example.com")!) == "example.com")
    }
}
