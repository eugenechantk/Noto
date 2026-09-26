import Foundation
import Testing
@testable import NotoSocialMedia

/// Test case index
/// 1. reelPicksTheProgressiveMP4 — real yt-dlp output (URLs replaced): author, caption, the 720p single-file MP4, not a DASH stream
/// 2. carouselKeepsEntriesInOrder — a playlist of video + image entries becomes video, image
/// 3. dashOnlyVideoFallsBackToItsThumbnail — no single-file MP4 → the poster image is saved instead
/// 4. unusableOutputThrows — no formats and no thumbnail → unreadable
/// 5. commandReadsCookiesLiveFromTheBrowser — yt-dlp arguments: --cookies-from-browser <browser> -J, no cookie file
/// 6. resolverFallsBackWhenTheEmbedIsUnreadable — embed without a media graph → the login fallback's post
/// 7. resolverWithoutFallbackStillReportsUnreadable — no fallback configured → the embed error, as before
/// 8. loginFetchFailuresAreRetriedNotSkipped — a failed login fetch is transient; unreadable embeds stay permanent
struct InstagramLoginFallbackTests {
    @Test func reelPicksTheProgressiveMP4() throws {
        let post = try YtDlpInstagramParser.parse(try Fixture.data("instagram-reel-ytdlp.json"), shortcode: "DdlzZLuTe2A")
        #expect(post.platform == .instagram)
        #expect(post.postID == "DdlzZLuTe2A")
        #expect(post.author == "ophelia.muuur")
        #expect(post.text == "I want to get married!😡")
        #expect(post.media.count == 1)
        #expect(post.media.first?.kind == .video)
        let url = try #require(post.media.first?.url.absoluteString)
        #expect(url.contains("28521861324119061v-"))
        #expect(!url.contains("dash-"))
    }

    @Test func carouselKeepsEntriesInOrder() throws {
        let json = """
        {"_type": "playlist", "id": "CAROUSEL1", "channel": "someone", "description": "two things",
         "entries": [
           {"_type": "video", "id": "a", "formats": [
             {"format_id": "dash-1v", "ext": "mp4", "width": 1080, "height": 1920, "vcodec": "vp09", "acodec": "none", "url": "https://cdn.example/dash.mp4"},
             {"format_id": "111v-0", "ext": "mp4", "width": 720, "height": 1280, "url": "https://cdn.example/first.mp4"}]},
           {"_type": "video", "id": "b", "formats": [], "thumbnail": "https://cdn.example/second.jpg"}
         ]}
        """
        let post = try YtDlpInstagramParser.parse(Data(json.utf8), shortcode: "CAROUSEL1")
        #expect(post.author == "someone")
        #expect(post.media == [
            SocialMedia(kind: .video, url: URL(string: "https://cdn.example/first.mp4")!),
            SocialMedia(kind: .image, url: URL(string: "https://cdn.example/second.jpg")!),
        ])
    }

    @Test func dashOnlyVideoFallsBackToItsThumbnail() throws {
        let json = """
        {"_type": "video", "id": "X", "uploader_id": "123", "thumbnail": "https://cdn.example/poster.jpg", "formats": [
          {"format_id": "dash-2v", "ext": "mp4", "vcodec": "vp09", "acodec": "none", "url": "https://cdn.example/v.mp4"},
          {"format_id": "dash-2a", "ext": "m4a", "vcodec": "none", "acodec": "mp4a", "url": "https://cdn.example/a.m4a"}]}
        """
        let post = try YtDlpInstagramParser.parse(Data(json.utf8), shortcode: "X")
        #expect(post.media == [SocialMedia(kind: .image, url: URL(string: "https://cdn.example/poster.jpg")!)])
        #expect(post.author == "123")
    }

    @Test func unusableOutputThrows() {
        #expect(throws: SocialPostError.self) {
            try YtDlpInstagramParser.parse(Data(#"{"_type": "video", "id": "X"}"#.utf8), shortcode: "X")
        }
        #expect(throws: SocialPostError.self) {
            try YtDlpInstagramParser.parse(Data("null".utf8), shortcode: "X")
        }
    }

    @Test func commandReadsCookiesLiveFromTheBrowser() {
        let runner = YtDlpRunner(executable: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"), cookiesBrowser: "chrome")
        let url = URL(string: "https://www.instagram.com/reel/DdlzZLuTe2A/")!
        #expect(runner.arguments(for: url) == ["--cookies-from-browser", "chrome", "-J", "--no-warnings", url.absoluteString])
        #expect(!runner.arguments(for: url).contains("--cookies"))
    }

    @Test func resolverFallsBackWhenTheEmbedIsUnreadable() async throws {
        let http = FakeHTTP()
        http.serve("https://www.instagram.com/p/DdlzZLuTe2A/embed/", text: "<html>The link to this photo or video may be broken</html>")
        let fallback = FakeFallback(post: SocialPost(platform: .instagram, postID: "DdlzZLuTe2A", author: "ophelia.muuur", text: nil,
                                                     media: [SocialMedia(kind: .video, url: URL(string: "https://cdn.example/v.mp4")!)]))
        let resolver = SocialPostResolver(http: http, instagramFallback: fallback)
        let post = try await resolver.resolve(URL(string: "https://www.instagram.com/reel/DdlzZLuTe2A/?stkn=abc")!)
        #expect(post.author == "ophelia.muuur")
        #expect(fallback.calls == ["DdlzZLuTe2A"])
    }

    @Test func resolverWithoutFallbackStillReportsUnreadable() async {
        let http = FakeHTTP()
        http.serve("https://www.instagram.com/p/DdlzZLuTe2A/embed/", text: "<html>nothing</html>")
        let resolver = SocialPostResolver(http: http)
        await #expect(throws: SocialPostError.self) {
            try await resolver.resolve(URL(string: "https://www.instagram.com/reel/DdlzZLuTe2A/")!)
        }
    }

    @Test func loginFetchFailuresAreRetriedNotSkipped() {
        #expect(!SocialPostError.isPermanent(SocialPostError.loginFetchFailed("empty media response")))
        #expect(SocialPostError.isPermanent(SocialPostError.unreadable("no media graph")))
        #expect(SocialPostError.isPermanent(SocialPostError.unsupportedURL))
        #expect(SocialPostError.isPermanent(SocialPostError.badResponse(status: 404)))
        #expect(!SocialPostError.isPermanent(SocialPostError.badResponse(status: 503)))
        #expect(!SocialPostError.isPermanent(URLError(.timedOut)))
    }
}

private final class FakeFallback: InstagramLoginFallback, @unchecked Sendable {
    private let lock = NSLock()
    private let post: SocialPost
    private var recorded: [String] = []

    init(post: SocialPost) { self.post = post }

    var calls: [String] { lock.withLock { recorded } }

    func resolve(_ url: URL, shortcode: String) async throws -> SocialPost {
        lock.withLock { recorded.append(shortcode) }
        return post
    }
}
