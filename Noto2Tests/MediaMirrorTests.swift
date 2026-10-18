import Foundation
import Testing
@testable import Noto2

/// Test case index
/// 1. signatureMatchesTheWorkersVector — Swift and the Worker sign "<key>\n<exp>" identically (SC3)
/// 2. keyComesFromTheAttachmentsFolder — `.attachments/<file>` from any vault path; nothing else is a key (SC5)
/// 3. signedURLsAreEncodedAndStableForADay — same link all day (URL cache hits), valid ≥ 24 h, spaces encoded (SC5)
/// 4. webImageBackupKeyMatchesHermes — `remote/` + first 32 hex of SHA-256(URL), the key Hermes uploads under
/// 5. mirrorURLCoversVaultFilesPostersAndWebImages — what to try first for each kind of media; nil when nothing to try
/// 6. videoPlaysFromTheMirrorFirstThenTheDevice — mirror primary, local fallback when downloaded; without a mirror, local or nothing
/// 7. configComesFromInfoPlist — missing, empty or unexpanded values disable the mirror (SC5)
struct MediaMirrorTests {
    private let mirror = MediaMirror(baseURL: URL(string: "https://cloudflare.eugenechantk.me/noto/media")!, signingKey: "test-signing-key")
    private let video = URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/iCloud~Noto/Documents/Noto/.attachments/x-1-1.mp4")

    @Test func signatureMatchesTheWorkersVector() {
        #expect(MediaMirror.signature(key: ".attachments/x-1-1.mp4", expires: 1_790_000_000, secret: "test-signing-key")
                == "usGssbnHCagkEOJoi4rDqJw6YOH4pc-fQ-9IR5u2zH8")
    }

    @Test func keyComesFromTheAttachmentsFolder() {
        #expect(MediaMirror.key(for: video) == ".attachments/x-1-1.mp4")
        #expect(MediaMirror.key(for: URL(fileURLWithPath: "/vault/.attachments/My Photo.png")) == ".attachments/My Photo.png")
        #expect(MediaMirror.key(for: URL(fileURLWithPath: "/vault/inbox/note.md")) == nil)
        #expect(MediaMirror.key(for: URL(fileURLWithPath: "/vault/.attachments")) == nil)
        #expect(MediaMirror.key(for: URL(string: "https://cdn.example/.attachments/a.png")!) == nil)
    }

    @Test func signedURLsAreEncodedAndStableForADay() throws {
        let morning = Date(timeIntervalSince1970: 1_790_000_000)
        let evening = morning.addingTimeInterval(3 * 3600)
        let first = mirror.signedURL(forKey: ".attachments/My Photo.png", now: morning)
        #expect(first == mirror.signedURL(forKey: ".attachments/My Photo.png", now: evening))
        #expect(first.absoluteString.hasPrefix("https://cloudflare.eugenechantk.me/noto/media/.attachments/My%20Photo.png?exp="))
        let components = try #require(URLComponents(url: first, resolvingAgainstBaseURL: false))
        let exp = try #require(components.queryItems?.first { $0.name == "exp" }?.value.flatMap(Int.init))
        #expect(exp >= Int(evening.timeIntervalSince1970) + 86_400)
        let sig = components.queryItems?.first { $0.name == "sig" }?.value
        #expect(sig == MediaMirror.signature(key: ".attachments/My Photo.png", expires: exp, secret: "test-signing-key"))
    }

    @Test func webImageBackupKeyMatchesHermes() {
        #expect(MediaMirror.remoteKey(for: URL(string: "https://pbs.twimg.com/media/abc.jpg")!) == "remote/c616ca93fac60b0af66709cea6decf01")
    }

    @Test func mirrorURLCoversVaultFilesPostersAndWebImages() {
        #expect(MediaSource.mirrorURL(for: video, mirror: mirror)?.path == "/noto/media/.attachments/x-1-1.mp4")
        #expect(MediaSource.mirrorURL(for: video, poster: true, mirror: mirror)?.path == "/noto/media/.attachments/x-1-1.mp4.poster.jpg")
        let web = URL(string: "https://pbs.twimg.com/media/abc.jpg")!
        #expect(MediaSource.mirrorURL(for: web, mirror: mirror)?.path == "/noto/media/remote/c616ca93fac60b0af66709cea6decf01")
        #expect(MediaSource.mirrorURL(for: URL(fileURLWithPath: "/vault/images/a.png"), mirror: mirror) == nil)
        #expect(MediaSource.mirrorURL(for: video, mirror: nil) == nil)
    }

    @Test func videoPlaysFromTheMirrorFirstThenTheDevice() {
        var downloads: [URL] = []
        let downloaded = MediaSource.videoSource(for: video, mirror: mirror, isAvailable: { _ in true }, startDownload: { downloads.append($0) })
        #expect(downloaded?.primary.path == "/noto/media/.attachments/x-1-1.mp4")
        #expect(downloaded?.fallback == video)
        #expect(downloads.isEmpty)

        let evicted = MediaSource.videoSource(for: video, mirror: mirror, isAvailable: { _ in false }, startDownload: { downloads.append($0) })
        #expect(evicted?.primary.host == "cloudflare.eugenechantk.me")
        #expect(evicted?.fallback == nil)
        #expect(downloads == [video])

        #expect(MediaSource.videoSource(for: video, mirror: nil, isAvailable: { _ in true }, startDownload: { _ in })
                == MediaSource.VideoSource(primary: video, fallback: nil))
        #expect(MediaSource.videoSource(for: video, mirror: nil, isAvailable: { _ in false }, startDownload: { downloads.append($0) }) == nil)
        #expect(downloads.count == 2)
    }

    @Test func configComesFromInfoPlist() {
        #expect(MediaMirror(infoDictionary: nil) == nil)
        #expect(MediaMirror(infoDictionary: ["NotoMediaMirrorURL": "https://cloudflare.eugenechantk.me/noto/media", "NotoMediaMirrorKey": ""]) == nil)
        #expect(MediaMirror(infoDictionary: ["NotoMediaMirrorURL": "https://cloudflare.eugenechantk.me/noto/media", "NotoMediaMirrorKey": "$(NOTO_MEDIA_SIGNING_KEY)"]) == nil)
        #expect(MediaMirror(infoDictionary: ["NotoMediaMirrorURL": "https://cloudflare.eugenechantk.me/noto/media", "NotoMediaMirrorKey": "k"])?.baseURL.host == "cloudflare.eugenechantk.me")
    }
}
