import Foundation
import Testing
@testable import Noto2

struct SearchSummaryRoutingTests {
    @Test func defaultRouteIsAttemptedOnce() {
        #expect(SearchModel.summaryBaseURLs(configured: OpenRouterBaseURLStore.defaultBaseURL)
            == [OpenRouterBaseURLStore.defaultBaseURL])
    }

    @Test func customRouteFallsBackToDirectOpenRouter() {
        let proxy = URL(string: "https://noto-relay.example.com/openai/v1")!
        #expect(SearchModel.summaryBaseURLs(configured: proxy)
            == [proxy, OpenRouterBaseURLStore.defaultBaseURL])
    }
}
