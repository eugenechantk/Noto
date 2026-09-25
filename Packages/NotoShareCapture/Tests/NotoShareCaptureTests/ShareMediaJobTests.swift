import Foundation
import Testing
@testable import NotoShareCapture

/// Test case index
/// 1. xStatusURLsAreRouted — x.com / twitter.com / mobile / i/web status URLs are X media sources (SC1)
/// 2. instagramPostAndReelURLsAreRouted — /p/, /reel/, /reels/, /tv/ and /<user>/p/ are Instagram sources (SC1)
/// 3. otherURLsAreNotRouted — profiles, home pages, other hosts, non-http schemes produce no job (SC1)
/// 4. notePathMatchesInboxShape — CaptureNotePath yields inbox/<date>-<sha8>.md from the normalized body, in the given calendar (SC1)
/// 5. jobCarriesCaptureIdentityAndNotePath — make(for:) copies id/share time and computes the note path; unsupported URLs give nil (SC1)
/// 6. jobJSONRoundTripsWithISODates — the wire format is stable ISO-8601 JSON (SC1)
/// 7. inboxPathValidatorRejectsTraversal — only inbox/<date>-<8 hex>.md passes (SC1)
struct ShareMediaJobTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func xStatusURLsAreRouted() {
        for raw in ["https://x.com/jacobrodri_/status/2102386784814735508?s=46",
                    "https://twitter.com/a/status/1",
                    "https://mobile.twitter.com/a/status/12/photo/1",
                    "https://x.com/i/web/status/2100400751357083664"] {
            #expect(ShareMediaSource.platform(for: URL(string: raw)!) == .x, "\(raw)")
        }
    }

    @Test func instagramPostAndReelURLsAreRouted() {
        for raw in ["https://www.instagram.com/p/Daw8hiys2w1/?stkn=abc",
                    "https://instagram.com/reel/ABC123/",
                    "https://www.instagram.com/reels/ABC123",
                    "https://www.instagram.com/tv/ABC123/",
                    "https://www.instagram.com/someone/p/ABC123/"] {
            #expect(ShareMediaSource.platform(for: URL(string: raw)!) == .instagram, "\(raw)")
        }
    }

    @Test func otherURLsAreNotRouted() {
        for raw in ["https://x.com/jacobrodri_", "https://x.com/home", "https://x.com/a/status/abc",
                    "https://www.instagram.com/instaagent.ai/", "https://www.instagram.com/",
                    "https://example.com/p/ABC", "ftp://x.com/a/status/1", "https://threads.net/@a/post/1"] {
            #expect(ShareMediaSource.platform(for: URL(string: raw)!) == nil, "\(raw)")
        }
    }

    @Test func notePathMatchesInboxShape() throws {
        let date = Date(timeIntervalSince1970: 1_787_000_000) // 2026-08-17T20:53:20Z
        let path = try #require(CaptureNotePath.relativePath(forRawBody: "  [T](https://x.com/a/status/1)\r\n", date: date, calendar: utc))
        #expect(path == "inbox/2026-08-17-\(CaptureNotePath.hash8(of: "[T](https://x.com/a/status/1)")).md")
        #expect(CaptureNotePath.relativePath(forRawBody: " \n ", date: date, calendar: utc) == nil)
        var hongKong = Calendar(identifier: .gregorian)
        hongKong.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        #expect(CaptureNotePath.relativePath(forRawBody: "x", date: date, calendar: hongKong)?.hasPrefix("inbox/2026-08-18-") == true)
    }

    @Test func jobCarriesCaptureIdentityAndNotePath() throws {
        let capture = PendingCapture(body: "[Post](https://x.com/a/status/42)", createdAt: Date(timeIntervalSince1970: 1_787_000_000))
        let job = try #require(ShareMediaJob.make(for: capture, url: URL(string: "https://x.com/a/status/42")!, title: "Post", calendar: utc))
        #expect(job.captureId == capture.id)
        #expect(job.platform == .x)
        #expect(job.sharedAt == capture.createdAt)
        #expect(job.notePath == CaptureNotePath.relativePath(forRawBody: capture.body, date: capture.createdAt, calendar: utc))
        #expect(job.version == ShareMediaJob.currentVersion)
        #expect(ShareMediaJob.make(for: capture, url: URL(string: "https://example.com/a")!, title: nil) == nil)
    }

    @Test func jobJSONRoundTripsWithISODates() throws {
        let job = ShareMediaJob(captureId: UUID(uuidString: "2843E15B-EFE8-4673-9B25-1251AA9D9F17")!,
                                url: URL(string: "https://www.instagram.com/p/Daw8hiys2w1/")!, platform: .instagram,
                                notePath: "inbox/2026-09-23-1a2b3c4d.md", sharedAt: Date(timeIntervalSince1970: 1_790_000_000), title: nil)
        let data = try ShareMediaJob.encoder.encode(job)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"sharedAt\":\"2026-09-21T14:13:20Z\""))
        #expect(json.contains("\"url\":\"https://www.instagram.com/p/Daw8hiys2w1/\""))
        #expect(json.contains("\"platform\":\"instagram\""))
        #expect(try ShareMediaJob.decoder.decode(ShareMediaJob.self, from: data) == job)
    }

    @Test func inboxPathValidatorRejectsTraversal() {
        #expect(CaptureNotePath.isInboxCapturePath("inbox/2026-09-23-1a2b3c4d.md"))
        for bad in ["inbox/../secret.md", "/inbox/2026-09-23-1a2b3c4d.md", "inbox/2026-09-23-1A2B3C4D.md",
                    "Projects/2026-09-23-1a2b3c4d.md", "inbox/2026-09-23-1a2b3c4d.md.bak", "inbox/x.md"] {
            #expect(!CaptureNotePath.isInboxCapturePath(bad), "\(bad)")
        }
    }
}
