import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import NotoLinkPreview

/// Open Graph fallback: richer cards when `LinkPresentation` returns little (SC-cards).
///
/// | Test | Covers |
/// | --- | --- |
/// | `parsesOpenGraphInAnyAttributeOrder` | `content` before/after `property`, single quotes, entities, relative image |
/// | `fallsBackToTwitterAndHTMLTags` | `twitter:*`, `<meta name=description>`, `<title>` |
/// | `ignoresNonWebImagesAndEmptyPages` | `data:` images dropped; a page with no tags is empty |
/// | `fetcherSendsCrawlerUserAgentAndDownloadsImage` | crawler UA on the page and image requests; image downsampled |
/// | `fetcherFailsWithoutTags` | no tags → error, so the card falls back to the URL |
/// | `strongPrimaryIsUsedAsIs` | image + description from LinkPresentation → no page fetch |
/// | `weakPrimaryTakesOpenGraphTitleAndFillsGaps` | Instagram-style "Instagram" title replaced; image and description filled |
/// | `failedPrimaryUsesOpenGraphAndBothFailingThrows` | LinkPresentation failure falls through; both failing throws |
@Suite("LinkPreviewOpenGraph")
struct LinkPreviewOpenGraphTests {
    private let page = URL(string: "https://www.instagram.com/p/Daw8hiys2w1/")!

    @Test("parses Open Graph tags in any attribute order")
    func parsesOpenGraphInAnyAttributeOrder() {
        let html = """
        <html><head>
        <meta content="Ophelia on Instagram: &quot;I want to get married!&quot;" property="og:title" />
        <meta property='og:description' content='51.8K likes, 315 comments &#8211; ophelia.muuur on September 25, 2026' />
        <meta property="og:image" content="/images/cover.jpg?x=1&amp;y=2">
        </head></html>
        """
        let tags = OpenGraphParser.parse(html: html, baseURL: page)
        #expect(tags.title == "Ophelia on Instagram: \"I want to get married!\"")
        #expect(tags.summary == "51.8K likes, 315 comments – ophelia.muuur on September 25, 2026")
        #expect(tags.imageURL?.absoluteString == "https://www.instagram.com/images/cover.jpg?x=1&y=2")
    }

    @Test("falls back to Twitter and plain HTML tags")
    func fallsBackToTwitterAndHTMLTags() {
        let html = """
        <head><title>  Page   Title </title>
        <meta name="description" content="Plain description">
        <meta name="twitter:image" content="https://cdn.example/card.png">
        </head>
        """
        let tags = OpenGraphParser.parse(html: html, baseURL: page)
        #expect(tags.title == "Page Title")
        #expect(tags.summary == "Plain description")
        #expect(tags.imageURL?.absoluteString == "https://cdn.example/card.png")
    }

    @Test("ignores non-web images and empty pages")
    func ignoresNonWebImagesAndEmptyPages() {
        let tags = OpenGraphParser.parse(html: #"<meta property="og:image" content="data:image/png;base64,AAAA">"#, baseURL: page)
        #expect(tags.imageURL == nil)
        #expect(OpenGraphParser.parse(html: "<html><body>hi</body></html>", baseURL: page).isEmpty)
    }

    @Test("fetcher sends a crawler user agent and downloads the image")
    func fetcherSendsCrawlerUserAgentAndDownloadsImage() async throws {
        let recorder = RequestRecorder()
        let png = try #require(Self.pngData(width: 1200, height: 630))
        let fetcher = OpenGraphFetcher(maxImagePixelSize: 320) { request in
            recorder.append(request)
            let url = request.url!
            if url.path.hasSuffix(".png") {
                return (png, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let html = #"<meta property="og:title" content="Title"><meta property="og:image" content="https://cdn.example/a.png">"#
            return (Data(html.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let metadata = try await fetcher.fetch(page)
        #expect(metadata.title == "Title")
        #expect(metadata.host == "instagram.com")
        let size = try #require(metadata.imageData.flatMap(LinkPreviewImageDownsampler.pixelSize(of:)))
        #expect(max(size.width, size.height) <= 320)
        #expect(recorder.requests.count == 2)
        #expect(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") == OpenGraphFetcher.crawlerUserAgent })
    }

    @Test("fetcher fails without tags")
    func fetcherFailsWithoutTags() async {
        let fetcher = OpenGraphFetcher { request in
            (Data("<html></html>".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: LinkPreviewFetchError.noMetadata) { try await fetcher.fetch(page) }
    }

    @Test("a strong primary result is used as is")
    func strongPrimaryIsUsedAsIs() async throws {
        let primary = StubFetcher(result: .success(LinkPreviewMetadata(url: page, title: "LP", summary: "LP summary", host: "x.com", imageData: Data([1]))))
        let secondary = StubFetcher(result: .success(LinkPreviewMetadata(url: page, title: "OG", host: "x.com")))
        let metadata = try await CompositeLinkPreviewFetcher(primary: primary, secondary: secondary).fetch(page)
        #expect(metadata.title == "LP")
        #expect(secondary.calls == 0)
    }

    @Test("a weak primary takes the Open Graph title and fills the gaps")
    func weakPrimaryTakesOpenGraphTitleAndFillsGaps() async throws {
        let primary = StubFetcher(result: .success(LinkPreviewMetadata(url: page, title: "Instagram", host: "instagram.com", iconData: Data([9]))))
        let secondary = StubFetcher(result: .success(LinkPreviewMetadata(url: page, title: "Ophelia on Instagram", summary: "51.8K likes", host: "instagram.com", imageData: Data([2]))))
        let metadata = try await CompositeLinkPreviewFetcher(primary: primary, secondary: secondary).fetch(page)
        #expect(metadata.title == "Ophelia on Instagram")
        #expect(metadata.summary == "51.8K likes")
        #expect(metadata.imageData == Data([2]))
        #expect(metadata.iconData == Data([9]))
    }

    @Test("a failed primary uses Open Graph; both failing throws")
    func failedPrimaryUsesOpenGraphAndBothFailingThrows() async throws {
        let failing = StubFetcher(result: .failure(LinkPreviewFetchError.noMetadata))
        let og = StubFetcher(result: .success(LinkPreviewMetadata(url: page, title: "OG", host: "instagram.com")))
        #expect(try await CompositeLinkPreviewFetcher(primary: failing, secondary: og).fetch(page).title == "OG")
        await #expect(throws: LinkPreviewFetchError.noMetadata) {
            try await CompositeLinkPreviewFetcher(primary: failing, secondary: failing).fetch(page)
        }
    }

    private static func pngData(width: Int, height: Int) -> Data? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = { context.setFillColor(CGColor(red: 1, green: 0.4, blue: 0.2, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height)); return context.makeImage() }()
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    func append(_ request: URLRequest) { lock.withLock { recorded.append(request) } }
    var requests: [URLRequest] { lock.withLock { recorded } }
}

private final class StubFetcher: LinkPreviewFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<LinkPreviewMetadata, Error>
    private var count = 0
    init(result: Result<LinkPreviewMetadata, Error>) { self.result = result }
    var calls: Int { lock.withLock { count } }
    func fetch(_ url: URL) async throws -> LinkPreviewMetadata {
        lock.withLock { count += 1 }
        return try result.get()
    }
}
