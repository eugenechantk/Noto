import Foundation
import Testing
@testable import Noto2

/// Test case index
/// 1. bodyThatIsOnlyALinkSplitsToURLAndNoRemainder — a share-sheet capture `[title](url)` yields the URL and no remainder (SC3)
/// 2. bareURLBodyAlsoSplits — a typed bare URL line is treated the same way (SC3)
/// 3. linkFollowedByTextKeepsTheText — text after the link line survives, trimmed (SC3)
/// 4. bodyWithoutLeadingLinkDoesNotSplit — prose, or a link that is not on the first line, renders as before (SC3)
struct DigestLinkCardSplitTests {
    @Test func bodyThatIsOnlyALinkSplitsToURLAndNoRemainder() {
        let split = DigestLinkCardSplit.split(body: "[Swift - Wikipedia](https://en.wikipedia.org/wiki/Swift_%28programming_language%29)")
        #expect(split?.url.absoluteString == "https://en.wikipedia.org/wiki/Swift_%28programming_language%29")
        #expect(split?.remainder == nil)
    }

    @Test func bareURLBodyAlsoSplits() {
        let split = DigestLinkCardSplit.split(body: "https://example.com/post\n")
        #expect(split?.url.absoluteString == "https://example.com/post")
        #expect(split?.remainder == nil)
    }

    @Test func linkFollowedByTextKeepsTheText() {
        let split = DigestLinkCardSplit.split(body: "[Post](https://example.com/post)\r\n\r\nA quote I liked.\nSecond line.\n")
        #expect(split?.url.absoluteString == "https://example.com/post")
        #expect(split?.remainder == "A quote I liked.\nSecond line.")
    }

    @Test func bodyWithoutLeadingLinkDoesNotSplit() {
        #expect(DigestLinkCardSplit.split(body: "Just a thought") == nil)
        #expect(DigestLinkCardSplit.split(body: "See [Post](https://example.com/post) later") == nil)
        #expect(DigestLinkCardSplit.split(body: "Intro\n[Post](https://example.com/post)") == nil)
        #expect(DigestLinkCardSplit.split(body: "") == nil)
    }
}
