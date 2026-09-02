import Foundation
import Testing
@testable import Noto2

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
}
