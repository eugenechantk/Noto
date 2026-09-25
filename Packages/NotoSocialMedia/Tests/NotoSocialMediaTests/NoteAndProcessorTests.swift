import Foundation
import NotoShareCapture
import Testing
@testable import NotoSocialMedia

/// Test case index
/// 1. downloadNamesFilesStablyAndSkipsExistingFiles — `.attachments/<platform>-<id>-<n>.<ext>`, quoted media included, second run fetches nothing (SC5)
/// 2. blockQuotesTextListsMediaAndNestsQuotedPost — exact markdown: author + text, media lines, then "Quoting @author" (SC5)
/// 3. appendAddsBlockOnceAfterABlankLine — second append is a no-op keyed by the first attachment (SC5)
/// 4. locateUsesInboxPathThenSearchesByURL — direct path, then the note that links the shared URL after Digest moved it (SC6)
/// 5. acceptParksUntilNoteAppearsThenAppends — waiting → appended → nothing left (SC6)
/// 6. parkedBlockIsDroppedAfterSevenDays — give-up window (SC6)
/// 7. overwrittenBlockIsRestoredWithinVerifyWindowOnly — an autosave that drops the block is undone for 10 minutes, then left alone (SC5)
struct NoteAndProcessorTests {
    private let xURL = URL(string: "https://x.com/jacobrodri_/status/2102386784814735508?s=46")!

    private func job(url: URL, notePath: String = "inbox/2026-09-23-1a2b3c4d.md") -> ShareMediaJob {
        ShareMediaJob(captureId: UUID(), url: url, platform: .x, notePath: notePath,
                      sharedAt: Date(timeIntervalSince1970: 1_790_000_000), title: "Post")
    }

    private func http() throws -> FakeHTTP {
        let http = FakeHTTP()
        http.serve("https://cdn.syndication.twimg.com/tweet-result?id=2102386784814735508", data: try Fixture.data("x-video.json"))
        http.serve("https://cdn.syndication.twimg.com/tweet-result?id=2100400751357083664", data: try Fixture.data("x-quote-with-video.json"))
        http.serve("https://video.twimg.com/", data: Data(repeating: 7, count: 64))
        return http
    }

    private func writeNote(_ vault: URL, _ path: String, _ body: String) throws {
        let url = vault.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\nid: 1\n---\n\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func downloadNamesFilesStablyAndSkipsExistingFiles() async throws {
        let vault = try Fixture.tempDirectory("vault")
        let http = try http()
        let post = try XPostResolver.parse(try Fixture.data("x-quote-with-video.json"))
        let downloader = MediaDownloader(vaultURL: vault, http: http)
        let paths = try await downloader.download(post)
        let quotedVideo = try #require(post.quoted.first?.media.first)
        #expect(paths[quotedVideo.url] == ".attachments/x-\(post.quoted[0].postID)-1.mp4")
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent(paths[quotedVideo.url]!).path))
        let fetched = http.requests.count
        _ = try await downloader.download(post)
        #expect(http.requests.count == fetched)
    }

    @Test func blockQuotesTextListsMediaAndNestsQuotedPost() {
        let quoted = SocialPost(platform: .x, postID: "2", author: "QuiverAI", text: "Introducing Arrow 2\n\nFaster.",
                                media: [SocialMedia(kind: .video, url: URL(string: "https://v/2.mp4")!)])
        let post = SocialPost(platform: .x, postID: "1", author: "a", text: "congrats!",
                              media: [SocialMedia(kind: .image, url: URL(string: "https://p/1.jpg")!)], quoted: [quoted])
        let block = ShareMediaMarkdown.block(for: post, paths: [
            URL(string: "https://p/1.jpg")!: ".attachments/x-1-1.jpg",
            URL(string: "https://v/2.mp4")!: ".attachments/x-2-1.mp4",
        ])
        #expect(block == """
        **@a**
        congrats!

        ![](.attachments/x-1-1.jpg)

        Quoting **@QuiverAI**
        Introducing Arrow 2

        Faster.

        ![](.attachments/x-2-1.mp4)
        """)
        #expect(ShareMediaMarkdown.firstAttachment(in: block) == ".attachments/x-1-1.jpg")
    }

    @Test func appendAddsBlockOnceAfterABlankLine() throws {
        let vault = try Fixture.tempDirectory("vault")
        try writeNote(vault, "inbox/n.md", "[Post](https://x.com/a/status/1)")
        let note = vault.appendingPathComponent("inbox/n.md")
        let appender = CaptureNoteAppender(vaultURL: vault)
        let block = "> hi\n\n![](.attachments/x-1-1.jpg)"
        #expect(try appender.append(block, to: note) == .appended)
        #expect(try appender.append(block, to: note) == .alreadyPresent)
        let text = try String(contentsOf: note, encoding: .utf8)
        #expect(text.hasSuffix("[Post](https://x.com/a/status/1)\n\n> hi\n\n![](.attachments/x-1-1.jpg)\n"))
        #expect(text.components(separatedBy: "x-1-1.jpg").count == 2)
    }

    @Test func locateUsesInboxPathThenSearchesByURL() throws {
        let vault = try Fixture.tempDirectory("vault")
        let appender = CaptureNoteAppender(vaultURL: vault)
        let job = job(url: URL(string: "https://en.wikipedia.org/wiki/Swift_(programming_language)")!)
        #expect(appender.locate(job, searchVault: true) == nil)
        // Digest filed the capture into a project note; the body keeps the encoded link.
        try writeNote(vault, "Projects/Languages.md", "[Swift](https://en.wikipedia.org/wiki/Swift_%28programming_language%29)")
        #expect(appender.locate(job, searchVault: false) == nil)
        #expect(appender.locate(job, searchVault: true)?.lastPathComponent == "Languages.md")
        try writeNote(vault, job.notePath, "[Swift](…)")
        #expect(appender.locate(job, searchVault: false)?.path.hasSuffix(job.notePath) == true)
    }

    @Test func acceptParksUntilNoteAppearsThenAppends() async throws {
        let vault = try Fixture.tempDirectory("vault")
        let state = try Fixture.tempDirectory("state")
        let processor = ShareMediaProcessor(vaultURL: vault, stateDirectory: state, http: try http())
        let job = job(url: xURL)
        let post = try await processor.accept(job)
        #expect(post.media.count == 1)
        #expect(processor.appendPending() == [.waiting(job: job.captureId)])

        try writeNote(vault, job.notePath, "[Post](\(xURL.absoluteString))")
        #expect(processor.appendPending() == [.appended(job: job.captureId, note: job.notePath)])
        #expect(processor.appendPending().isEmpty)
        let text = try String(contentsOf: vault.appendingPathComponent(job.notePath), encoding: .utf8)
        #expect(text.contains("**@jacobrodri_**\nI can see a potential $100k/month app here"))
        #expect(text.contains("![](.attachments/x-2102386784814735508-1.mp4)"))
    }

    @Test func parkedBlockIsDroppedAfterSevenDays() async throws {
        let vault = try Fixture.tempDirectory("vault")
        let state = try Fixture.tempDirectory("state")
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let early = ShareMediaProcessor(vaultURL: vault, stateDirectory: state, http: try http(), now: { start })
        let job = job(url: xURL)
        _ = try await early.accept(job)
        let late = ShareMediaProcessor(vaultURL: vault, stateDirectory: state, http: try http(),
                                       now: { start.addingTimeInterval(8 * 24 * 3600) })
        #expect(late.appendPending() == [.gaveUp(job: job.captureId)])
        #expect(late.appendPending().isEmpty)
    }

    @Test func overwrittenBlockIsRestoredWithinVerifyWindowOnly() async throws {
        let vault = try Fixture.tempDirectory("vault")
        let state = try Fixture.tempDirectory("state")
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        func processor(after seconds: TimeInterval) throws -> ShareMediaProcessor {
            ShareMediaProcessor(vaultURL: vault, stateDirectory: state, http: try http(), now: { start.addingTimeInterval(seconds) })
        }
        let job = job(url: xURL)
        try writeNote(vault, job.notePath, "[Post](\(xURL.absoluteString))")
        _ = try await processor(after: 0).accept(job)
        #expect(try processor(after: 0).appendPending() == [.appended(job: job.captureId, note: job.notePath)])
        #expect(try processor(after: 60).appendPending().isEmpty) // still present: silent

        // The editor autosaves text typed before the append landed.
        try writeNote(vault, job.notePath, "[Post](\(xURL.absoluteString))\n\nmy thoughts")
        #expect(try processor(after: 120).appendPending() == [.restored(job: job.captureId, note: job.notePath)])
        let restored = try String(contentsOf: vault.appendingPathComponent(job.notePath), encoding: .utf8)
        #expect(restored.contains("my thoughts"))
        #expect(restored.contains("x-2102386784814735508-1.mp4"))

        // After the window the user's edits win, even if they remove the media.
        try writeNote(vault, job.notePath, "[Post](\(xURL.absoluteString))\n\nmy thoughts")
        #expect(try processor(after: 11 * 60).appendPending().isEmpty)
        #expect(try processor(after: 12 * 60).appendPending().isEmpty)
        let final = try String(contentsOf: vault.appendingPathComponent(job.notePath), encoding: .utf8)
        #expect(!final.contains("x-2102386784814735508-1.mp4"))
    }
}
