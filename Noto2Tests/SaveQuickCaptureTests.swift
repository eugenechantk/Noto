import Foundation
import NotoShareCapture
import Testing
@testable import Noto2

/// Test case index
/// 1. filesIntoTheVaultAndLinksToTheNote — vault reachable: inbox note written, notification links noto2://note?path=
/// 2. anIdenticalCaptureSaysAlreadyInNoto — same text same day: no second file, "Already in Noto 2"
/// 3. withoutAVaultTheCaptureIsStaged — vault unreachable: staged in the App Group, link opens the staged capture
/// 4. blankTextAndNoWhereToSaveThrow — errors instead of silent success
/// 5. previewIsTheFirstLineCapped — notification body stays short
/// 6. noteLinkRoundTripsAndRejectsEscapes — noto2://note?path= builds, parses, and refuses paths outside the vault
/// 7. routerCarriesTheNotePathUntilCleared — the router requests Browse with the path; other requests clear it
@MainActor
struct SaveQuickCaptureTests {
    private func makeDir(_ prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func filesIntoTheVaultAndLinksToTheNote() throws {
        let vault = try makeDir("vault")
        defer { try? FileManager.default.removeItem(at: vault) }

        let outcome = try QuickCaptureAction.run(text: "Buy oat milk\nand eggs", vaultURL: vault, store: nil)

        let path = try #require(outcome.relativePath)
        #expect(path.hasPrefix("inbox/") && path.hasSuffix(".md"))
        let content = try String(contentsOf: vault.appendingPathComponent(path), encoding: .utf8)
        #expect(content.contains("Buy oat milk\nand eggs"))
        #expect(outcome.title == "Action completed")
        #expect(outcome.body == "Saved to Noto 2: “Buy oat milk”")
        #expect(Noto2LaunchRoute.route(for: outcome.link) == .openNote(path: path))
        #expect(outcome.stagedID == nil)
    }

    @Test func anIdenticalCaptureSaysAlreadyInNoto() throws {
        let vault = try makeDir("vault")
        defer { try? FileManager.default.removeItem(at: vault) }
        let first = try QuickCaptureAction.run(text: "Call the dentist", vaultURL: vault, store: nil)
        let second = try QuickCaptureAction.run(text: "Call the dentist", vaultURL: vault, store: nil)
        #expect(second.relativePath == first.relativePath)
        #expect(second.body.hasPrefix("Already in Noto 2:"))
        let inbox = try FileManager.default.contentsOfDirectory(atPath: vault.appendingPathComponent("inbox").path)
        #expect(inbox.filter { $0.hasSuffix(".md") }.count == 1)
    }

    @Test func withoutAVaultTheCaptureIsStaged() throws {
        let group = try makeDir("group")
        defer { try? FileManager.default.removeItem(at: group) }
        let store = PendingCaptureStore(containerURL: group)

        let outcome = try QuickCaptureAction.run(text: "Idea for later", vaultURL: nil, store: store)

        let id = try #require(outcome.stagedID)
        #expect(store.pending().map(\.body) == ["Idea for later"])
        #expect(Noto2LaunchRoute.route(for: outcome.link) == .openSharedCapture(id: id))
        #expect(outcome.body.contains("filed when Noto 2 next opens"))
    }

    @Test func blankTextAndNoWhereToSaveThrow() throws {
        #expect(throws: QuickCaptureAction.ActionError.self) {
            _ = try QuickCaptureAction.run(text: "  \n ", vaultURL: nil, store: nil)
        }
        #expect(throws: QuickCaptureAction.ActionError.self) {
            _ = try QuickCaptureAction.run(text: "hello", vaultURL: nil, store: nil)
        }
    }

    @Test func previewIsTheFirstLineCapped() {
        #expect(QuickCaptureAction.preview("  one\ntwo ") == "“one”")
        let long = String(repeating: "a", count: 120)
        let p = QuickCaptureAction.preview(long)
        #expect(p.count == 82)             // quotes + 79 chars + ellipsis
        #expect(p.hasSuffix("…”"))
    }

    @Test func noteLinkRoundTripsAndRejectsEscapes() throws {
        let path = "inbox/2026-09-30-a1b2c3d4.md"
        let url = try #require(Noto2LaunchRoute.openNoteURL(relativePath: path))
        #expect(url.absoluteString == "noto2://note?path=inbox/2026-09-30-a1b2c3d4.md")
        #expect(Noto2LaunchRoute.route(for: url) == .openNote(path: path))
        #expect(Noto2LaunchRoute.tab(for: url) == .browse)
        #expect(Noto2LaunchRoute.route(for: try #require(URL(string: "noto2://note?path=Projects/My%20Note.md"))) == .openNote(path: "Projects/My Note.md"))

        for bad in ["noto2://note?path=../secrets.md", "noto2://note?path=/etc/passwd.md", "noto2://note?path=inbox/../../x.md",
                    "noto2://note?path=inbox/x.txt", "noto2://note?path=", "noto2://note", "noto2://note?path=a.md&x=1",
                    "noto2://note/extra?path=a.md", "noto2://note?path=a//b.md"] {
            #expect(Noto2LaunchRoute.route(for: try #require(URL(string: bad))) == nil, "accepted \(bad)")
        }
        #expect(Noto2LaunchRoute.openNoteURL(relativePath: "../x.md") == nil)
    }

    @Test func routerCarriesTheNotePathUntilCleared() throws {
        let router = Noto2LaunchRouter()
        #expect(router.handle(try #require(Noto2LaunchRoute.openNoteURL(relativePath: "inbox/n.md"))))
        #expect(router.requestedNotePath == "inbox/n.md")
        #expect(router.requestedTab == .browse)
        #expect(router.requestRevision == 1)
        router.clearNoteRequest()
        #expect(router.requestedNotePath == nil)

        #expect(router.handle(try #require(Noto2LaunchRoute.openNoteURL(relativePath: "inbox/n.md"))))
        router.request(.capture)                        // a plain request never carries a stale path
        #expect(router.requestedNotePath == nil)
        #expect(router.handle(try #require(Noto2LaunchRoute.openNoteURL(relativePath: "inbox/n.md"))))
        router.requestSharedCapture(id: UUID())
        #expect(router.requestedNotePath == nil)
    }
}

@MainActor
struct SavedCaptureEntityTests {
    @Test func carriesTheAlertTextAndTheLinkForTheShortcut() throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let outcome = try QuickCaptureAction.run(text: "Pick up the dry cleaning", vaultURL: vault, store: nil)
        let saved = SavedCapture(outcome)
        #expect(saved.title == "Action completed")
        #expect(saved.message == "Saved to Noto 2: “Pick up the dry cleaning”")
        #expect(saved.path == outcome.relativePath)
        #expect(saved.link == outcome.link)
        #expect(Noto2LaunchRoute.route(for: try #require(saved.link)) == .openNote(path: try #require(outcome.relativePath)))
    }
}
