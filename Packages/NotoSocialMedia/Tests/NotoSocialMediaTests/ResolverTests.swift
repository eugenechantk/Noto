import Foundation
import Testing
@testable import NotoSocialMedia

/// Test case index
/// 1. xTokenMatchesJavaScript — the Swift port of `toString(36)` gives the same token as JS for real ids (SC4)
/// 2. xStatusIDIsReadFromEveryURLShape — /<user>/status/<id>, /i/web/status/<id>, trailing /video/1 (SC4)
/// 3. xVideoPostKeepsDisplayTextAndBestMP4 — real response: t.co media link trimmed, highest-bitrate MP4 chosen (SC4)
/// 4. xQuotePostCarriesQuotedVideo — real response: quoted post parsed with its own video (SC4)
/// 5. xPhotoPostUsesLargeImagesAndExpandsLinks — photos at name=large, t.co expanded, entities decoded (SC4)
/// 6. xMissingPostIsUnreadable — a tombstone/empty response throws (SC4)
/// 7. instagramShortcodeIsReadFromEveryURLShape — /p/, /reel/, /<user>/p/ (SC4)
/// 8. instagramVideoEmbedParses — real embed page: author, caption, one video (SC4)
/// 9. instagramCarouselKeepsEveryChildInOrder — GraphSidecar with image, video, image (SC4)
/// 10. instagramLoginWallIsUnreadable — a page without contextJSON throws (SC4)
/// 11. resolverRoutesByPlatform — X hits the syndication endpoint, Instagram the embed page (SC4)
struct ResolverTests {
    @Test func xTokenMatchesJavaScript() {
        #expect(XPostResolver.token(for: "2102386784814735508") == "53gucdbo9sf")
        #expect(XPostResolver.token(for: "2100400751357083664") == "53alq85xcke")
        #expect(XPostResolver.token(for: "20") == "6dq1a2xwd93")
    }

    @Test func xStatusIDIsReadFromEveryURLShape() {
        #expect(XPostResolver.statusID(in: URL(string: "https://x.com/a/status/42?s=46")!) == "42")
        #expect(XPostResolver.statusID(in: URL(string: "https://x.com/i/web/status/7")!) == "7")
        #expect(XPostResolver.statusID(in: URL(string: "https://x.com/a/status/9/video/1")!) == "9")
        #expect(XPostResolver.statusID(in: URL(string: "https://x.com/a")!) == nil)
    }

    @Test func xVideoPostKeepsDisplayTextAndBestMP4() throws {
        let post = try XPostResolver.parse(try Fixture.data("x-video.json"))
        #expect(post.postID == "2102386784814735508")
        #expect(post.author == "jacobrodri_")
        #expect(post.text == "I can see a potential $100k/month app here")
        #expect(post.media.count == 1)
        #expect(post.media.first?.kind == .video)
        #expect(post.media.first?.url.absoluteString.contains("/720x1280/") == true)
        #expect(post.quoted.isEmpty)
    }

    @Test func xQuotePostCarriesQuotedVideo() throws {
        let post = try XPostResolver.parse(try Fixture.data("x-quote-with-video.json"))
        #expect(post.text == "congrats quiver team! this is awesome")
        #expect(post.media.isEmpty)
        let quoted = try #require(post.quoted.first)
        #expect(quoted.author == "QuiverAI")
        #expect(quoted.text?.hasPrefix("Introducing Arrow 2") == true)
        #expect(quoted.media.map(\.kind) == [.video])
        #expect(post.allMedia.count == 1)
    }

    @Test func xPhotoPostUsesLargeImagesAndExpandsLinks() throws {
        let json: [String: Any] = [
            "id_str": "5", "text": "Tom &amp; Jerry https://t.co/abc https://t.co/pic",
            "display_text_range": [0, 28],
            "user": ["screen_name": "someone"],
            "entities": ["urls": [["url": "https://t.co/abc", "expanded_url": "https://example.com/read"]]],
            "mediaDetails": [
                ["type": "photo", "media_url_https": "https://pbs.twimg.com/media/A.jpg"],
                ["type": "photo", "media_url_https": "https://pbs.twimg.com/media/B.png"],
            ],
        ]
        let post = try XPostResolver.parse(try JSONSerialization.data(withJSONObject: json))
        #expect(post.text == "Tom & Jerry https://example.com/read")
        #expect(post.media.map(\.url.absoluteString) == ["https://pbs.twimg.com/media/A.jpg?name=large", "https://pbs.twimg.com/media/B.png?name=large"])
        #expect(post.media.allSatisfy { $0.kind == .image })
    }

    @Test func xMissingPostIsUnreadable() {
        #expect(throws: SocialPostError.self) { try XPostResolver.parse(Data("{}".utf8)) }
        #expect(throws: (any Error).self) { try XPostResolver.parse(Data("not json".utf8)) }
    }

    @Test func instagramShortcodeIsReadFromEveryURLShape() {
        #expect(InstagramPostResolver.shortcode(in: URL(string: "https://www.instagram.com/p/Daw8hiys2w1/?stkn=x")!) == "Daw8hiys2w1")
        #expect(InstagramPostResolver.shortcode(in: URL(string: "https://www.instagram.com/reel/ABC/")!) == "ABC")
        #expect(InstagramPostResolver.shortcode(in: URL(string: "https://www.instagram.com/someone/p/XYZ/")!) == "XYZ")
        #expect(InstagramPostResolver.shortcode(in: URL(string: "https://www.instagram.com/someone/")!) == nil)
    }

    @Test func instagramVideoEmbedParses() throws {
        let post = try InstagramPostResolver.parse(html: try Fixture.text("instagram-video-embed.html"), shortcode: "Daw8hiys2w1")
        #expect(post.platform == .instagram)
        #expect(post.postID == "Daw8hiys2w1")
        #expect(post.author == "instaagent.ai")
        #expect(post.text?.hasPrefix("拍廣告片唔一定要貴") == true)
        #expect(post.media.map(\.kind) == [.video])
        #expect(post.media.first?.url.host?.hasSuffix("cdninstagram.com") == true)
    }

    @Test func instagramCarouselKeepsEveryChildInOrder() throws {
        let html = try Fixture.instagramEmbed(shortcodeMedia: [
            "__typename": "GraphSidecar", "shortcode": "CAR", "owner": ["username": "maker"],
            "edge_media_to_caption": ["edges": [["node": ["text": "Three things"]]]],
            "edge_sidecar_to_children": ["edges": [
                ["node": ["__typename": "GraphImage", "is_video": false, "display_url": "https://scontent.cdninstagram.com/1.jpg"]],
                ["node": ["__typename": "GraphVideo", "is_video": true, "display_url": "https://scontent.cdninstagram.com/2.jpg", "video_url": "https://scontent.cdninstagram.com/2.mp4"]],
                ["node": ["__typename": "GraphImage", "is_video": false, "display_url": "https://scontent.cdninstagram.com/3.webp"]],
            ]],
        ])
        let post = try InstagramPostResolver.parse(html: html, shortcode: "CAR")
        #expect(post.text == "Three things")
        #expect(post.media.map(\.kind) == [.image, .video, .image])
        #expect(post.media.map(\.url.lastPathComponent) == ["1.jpg", "2.mp4", "3.webp"])
    }

    @Test func instagramLoginWallIsUnreadable() {
        #expect(throws: SocialPostError.self) {
            try InstagramPostResolver.parse(html: "<html><title>Login • Instagram</title></html>", shortcode: "X")
        }
    }

    @Test func resolverRoutesByPlatform() async throws {
        let http = FakeHTTP()
        http.serve("https://cdn.syndication.twimg.com/tweet-result?id=2102386784814735508", data: try Fixture.data("x-video.json"))
        http.serve("https://www.instagram.com/p/Daw8hiys2w1/embed/captioned/", text: try Fixture.text("instagram-video-embed.html"))
        let resolver = SocialPostResolver(http: http)
        let x = try await resolver.resolve(URL(string: "https://x.com/jacobrodri_/status/2102386784814735508?s=46")!)
        let ig = try await resolver.resolve(URL(string: "https://www.instagram.com/p/Daw8hiys2w1/?stkn=MXNu")!)
        #expect(x.platform == .x)
        #expect(ig.platform == .instagram)
        #expect(http.requestedURLs.first?.contains("token=53gucdbo9sf") == true)
        await #expect(throws: SocialPostError.unsupportedURL) {
            try await resolver.resolve(URL(string: "https://example.com/post")!)
        }
    }
}
