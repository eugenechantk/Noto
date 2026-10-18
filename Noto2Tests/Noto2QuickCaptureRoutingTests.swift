import Foundation
import NotoShareCapture
import Testing
@testable import Noto2

/// Test case index
/// 1. canonicalQuickCaptureURLSelectsCapture — noto2://capture opens Capture
/// 2. unrelatedAndMalformedURLsAreRejected — other schemes/hosts/paths/queries are not routes
/// 3. routerPublishesEveryQuickCaptureRequest — revision bumps per request
/// 4. sharedCaptureURLRoundTrips — noto2://capture?shared=<UUID> builds and parses back to the id (share-extension "Add notes")
/// 5. sharedCaptureURLsWithBadIDsOrExtraItemsAreRejected — only exactly one well-formed `shared` item is accepted
/// 6. routerCarriesTheSharedCaptureIDUntilCleared — the router exposes the id for the app to drain + open, and plain requests clear it
/// 7. captureTextURLRoundTripsExactText — noto2://capture?text=… carries the exact text, reserved characters included (SC1)
/// 8. shortcutsStyleCaptureTextURLsParse — %20 / %0A encoded text from a Shortcut, and a literal `+`, parse as written (SC1)
/// 9. captureTextURLsThatAreEmptyOrMixedAreRejected — blank, valueless, repeated or mixed `text` items are not routes (SC2)
/// 10. routerStagesCaptureTextAndRequestsItsNote — the text is staged and its note requested like a share-sheet capture (SC3)
/// 11. routerFallsBackToCaptureTabWhenStagingFails — no stager (widget/extension default) or a failed write opens Capture (SC4)
/// 12. captureTextStagerWritesAPendingCapture — the app's stager puts exactly one capture with the text in the store (SC3)
/// 13. captureTextStagerReportsAMissingStore — no App Group container means nothing staged (SC4)
@MainActor
struct Noto2QuickCaptureRoutingTests {
    @Test func canonicalQuickCaptureURLSelectsCapture() throws {
        let url = Noto2LaunchRoute.quickCaptureURL

        #expect(url.absoluteString == "noto2://capture")
        #expect(Noto2LaunchRoute.tab(for: url) == .capture)
    }

    @Test func unrelatedAndMalformedURLsAreRejected() throws {
        let invalidURLs = [
            "noto://capture",
            "https://capture",
            "noto2://search",
            "noto2://capture/extra",
            "noto2://capture?source=test",
            "noto2://capture#fragment",
            "noto2:capture"
        ]

        for rawURL in invalidURLs {
            let url = try #require(URL(string: rawURL))
            #expect(Noto2LaunchRoute.tab(for: url) == nil, "Unexpectedly accepted \(rawURL)")
        }
    }

    @Test func routerPublishesEveryQuickCaptureRequest() throws {
        let router = Noto2LaunchRouter()
        let url = try #require(URL(string: "noto2://capture"))

        #expect(router.requestRevision == 0)
        #expect(router.requestedTab == nil)

        #expect(router.handle(url))
        #expect(router.requestedTab == .capture)
        #expect(router.requestRevision == 1)

        router.request(.capture)
        #expect(router.requestRevision == 2)
    }

    @Test func sharedCaptureURLRoundTrips() throws {
        let id = try #require(UUID(uuidString: "2843E15B-EFE8-4673-9B25-1251AA9D9F17"))
        let url = Noto2LaunchRoute.openSharedCaptureURL(id: id)

        #expect(url.absoluteString == "noto2://capture?shared=2843E15B-EFE8-4673-9B25-1251AA9D9F17")
        #expect(Noto2LaunchRoute.route(for: url) == .openSharedCapture(id: id))
        #expect(Noto2LaunchRoute.tab(for: url) == .capture)
        #expect(Noto2LaunchRoute.route(for: Noto2LaunchRoute.quickCaptureURL) == .capture)
    }

    @Test func sharedCaptureURLsWithBadIDsOrExtraItemsAreRejected() throws {
        let invalidURLs = [
            "noto2://capture?shared=abc",
            "noto2://capture?shared=",
            "noto2://capture?shared",
            "noto2://capture?shared=2843E15B-EFE8-4673-9B25-1251AA9D9F17&x=1",
            "noto2://capture?other=2843E15B-EFE8-4673-9B25-1251AA9D9F17",
            "noto2://capture/x?shared=2843E15B-EFE8-4673-9B25-1251AA9D9F17",
            "noto2://capture?shared=2843E15B-EFE8-4673-9B25-1251AA9D9F17#f"
        ]
        for rawURL in invalidURLs {
            let url = try #require(URL(string: rawURL))
            #expect(Noto2LaunchRoute.route(for: url) == nil, "Unexpectedly accepted \(rawURL)")
        }
    }

    @Test func routerCarriesTheSharedCaptureIDUntilCleared() throws {
        let router = Noto2LaunchRouter()
        let id = UUID()

        #expect(router.handle(Noto2LaunchRoute.openSharedCaptureURL(id: id)))
        #expect(router.requestedSharedCaptureID == id)
        #expect(router.requestedTab == .capture)
        #expect(router.requestRevision == 1)

        router.clearSharedCaptureRequest()
        #expect(router.requestedSharedCaptureID == nil)

        // A plain capture request never carries a stale shared id.
        #expect(router.handle(Noto2LaunchRoute.openSharedCaptureURL(id: id)))
        router.request(.capture)
        #expect(router.requestedSharedCaptureID == nil)
        #expect(router.requestRevision == 3)
    }

    // MARK: Capture-text deep link

    @Test func captureTextURLRoundTripsExactText() throws {
        let texts = [
            "Buy milk",
            "Line one\nLine two\n\n- bullet",
            "Ideas & plans: a=b, 1+1=2, #tag, what? /path",
            "Café — 日本語 🎙️",
            "  padded  "
        ]
        for text in texts {
            let url = try #require(Noto2LaunchRoute.captureTextURL(text))
            #expect(Noto2LaunchRoute.route(for: url) == .captureText(text), "Round trip failed for \(url.absoluteString)")
            #expect(Noto2LaunchRoute.tab(for: url) == .capture)
        }
        #expect(Noto2LaunchRoute.captureTextURL("Buy milk")?.absoluteString == "noto2://capture?text=Buy%20milk")
    }

    @Test func shortcutsStyleCaptureTextURLsParse() throws {
        let cases: [(String, String)] = [
            ("noto2://capture?text=Buy%20milk%0Aand%20eggs", "Buy milk\nand eggs"),
            ("noto2://capture?text=1+1", "1+1"),
            ("noto2://capture?text=a%26b%3Dc", "a&b=c")
        ]
        for (raw, expected) in cases {
            let url = try #require(URL(string: raw))
            #expect(Noto2LaunchRoute.route(for: url) == .captureText(expected), "Unexpected route for \(raw)")
        }
    }

    @Test func captureTextURLsThatAreEmptyOrMixedAreRejected() throws {
        let invalidURLs = [
            "noto2://capture?text=",
            "noto2://capture?text",
            "noto2://capture?text=%20%0A%20",
            "noto2://capture?text=a&text=b",
            "noto2://capture?text=a&shared=2843E15B-EFE8-4673-9B25-1251AA9D9F17",
            "noto2://capture?text=a&source=shortcut",
            "noto2://capture/x?text=a",
            "noto2://capture?text=a#f",
            "noto2://search?text=a"
        ]
        for rawURL in invalidURLs {
            let url = try #require(URL(string: rawURL))
            #expect(Noto2LaunchRoute.route(for: url) == nil, "Unexpectedly accepted \(rawURL)")
        }
        #expect(Noto2LaunchRoute.captureTextURL("") == nil)
        #expect(Noto2LaunchRoute.captureTextURL(" \n ") == nil)
    }

    @Test func routerStagesCaptureTextAndRequestsItsNote() throws {
        let router = Noto2LaunchRouter()
        let stagedID = UUID()
        var staged: [String] = []
        let url = try #require(Noto2LaunchRoute.captureTextURL("Call the plumber\nbefore Friday"))

        #expect(router.handle(url, stageText: { text in
            staged.append(text)
            return stagedID
        }))

        #expect(staged == ["Call the plumber\nbefore Friday"])
        #expect(router.requestedSharedCaptureID == stagedID)
        #expect(router.requestedTab == .capture)
        #expect(router.requestRevision == 1)
    }

    @Test func routerFallsBackToCaptureTabWhenStagingFails() throws {
        let url = try #require(Noto2LaunchRoute.captureTextURL("Lost thought"))

        let defaultRouter = Noto2LaunchRouter()
        #expect(defaultRouter.handle(url))
        #expect(defaultRouter.requestedTab == .capture)
        #expect(defaultRouter.requestedSharedCaptureID == nil)
        #expect(defaultRouter.requestRevision == 1)

        let failingRouter = Noto2LaunchRouter()
        #expect(failingRouter.handle(url, stageText: { _ in nil }))
        #expect(failingRouter.requestedTab == .capture)
        #expect(failingRouter.requestedSharedCaptureID == nil)
    }

    @Test func captureTextStagerWritesAPendingCapture() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-text-stager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let store = PendingCaptureStore(containerURL: container)

        let id = try #require(CaptureTextStager.stage("Voice note from the Action button", in: store))

        let pending = store.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.id == id)
        #expect(pending.first?.body == "Voice note from the Action button")
    }

    @Test func captureTextStagerReportsAMissingStore() {
        #expect(CaptureTextStager.stage("Nowhere to go", in: nil) == nil)
    }
}
