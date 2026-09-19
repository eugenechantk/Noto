import Foundation
import Testing
@testable import Noto2

/// Test case index
/// 1. canonicalQuickCaptureURLSelectsCapture — noto2://capture opens Capture
/// 2. unrelatedAndMalformedURLsAreRejected — other schemes/hosts/paths/queries are not routes
/// 3. routerPublishesEveryQuickCaptureRequest — revision bumps per request
/// 4. sharedCaptureURLRoundTrips — noto2://capture?shared=<UUID> builds and parses back to the id (share-extension "Add notes")
/// 5. sharedCaptureURLsWithBadIDsOrExtraItemsAreRejected — only exactly one well-formed `shared` item is accepted
/// 6. routerCarriesTheSharedCaptureIDUntilCleared — the router exposes the id for the app to drain + open, and plain requests clear it
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
}
