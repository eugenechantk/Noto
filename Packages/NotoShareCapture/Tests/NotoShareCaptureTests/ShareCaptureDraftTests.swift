import Foundation
import Testing
@testable import NotoShareCapture

struct ShareCaptureDraftTests {
    private let url = URL(string: "https://example.com/calm")!

    private func resolved(text: String? = nil) -> SharedLinkPayload.Resolved {
        SharedLinkPayload(urls: [url], texts: text.map { [$0] } ?? [], pageTitle: "Calm software").resolve()!
    }

    @Test func composeStartsWithTheSharedThoughtAboveTheLink() {
        let draft = ShareCaptureDraft(resolved: resolved(text: "  A useful quote.\r\nKeep this.  "))
        #expect(draft.thought == "A useful quote.\nKeep this.")
        #expect(draft.body == "A useful quote.\nKeep this.\n\n[Calm software](https://example.com/calm)")
    }

    @Test(arguments: ["", "  ", "https://example.com/calm", "Calm software"])
    func composeDoesNotRepeatTheSharedLinkOrTitle(_ text: String) {
        let draft = ShareCaptureDraft(resolved: resolved(text: text))
        #expect(draft.thought.isEmpty)
        #expect(draft.body == "[Calm software](https://example.com/calm)")
    }

    @Test func editedThoughtKeepsMarkdownAndAppearsBeforeTheLink() {
        var draft = ShareCaptureDraft(resolved: resolved())
        draft.thought = "  # Idea\n- Keep **one** accent.\n- [[Design]]  "
        #expect(draft.body == "# Idea\n- Keep **one** accent.\n- [[Design]]\n\n[Calm software](https://example.com/calm)")
    }

    @Test func clearingSharedTextStillSavesTheLink() {
        var draft = ShareCaptureDraft(resolved: resolved(text: "Old selection"))
        draft.thought = " \n "
        #expect(draft.body == "[Calm software](https://example.com/calm)")
    }

    @Test func onlyAnExplicitSaveCreatesAPendingCapture() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PendingCaptureStore(containerURL: root)
        var draft = ShareCaptureDraft(resolved: resolved())
        draft.thought = "Remember the quiet layout."
        #expect(store.isEmpty)
        let saved = try store.enqueue(body: draft.body)
        #expect(store.pending() == [saved])
        #expect(saved.body.hasPrefix("Remember the quiet layout.\n\n"))
    }

    @Test func mediaJobTargetsTheComposedCapturePath() {
        let source = URL(string: "https://x.com/example/status/123456")!
        let resolved = SharedLinkPayload(urls: [source]).resolve()!
        var draft = ShareCaptureDraft(resolved: resolved)
        draft.thought = "A thought worth keeping"
        let capture = PendingCapture(body: draft.body)
        let job = ShareMediaJob.make(for: capture, url: source, title: nil)
        #expect(job?.notePath == CaptureNotePath.relativePath(forRawBody: draft.body, date: capture.createdAt))
        #expect(job?.notePath != CaptureNotePath.relativePath(forRawBody: resolved.body, date: capture.createdAt))
    }
}
