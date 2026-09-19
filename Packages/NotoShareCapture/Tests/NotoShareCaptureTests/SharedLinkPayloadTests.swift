import Foundation
import Testing
@testable import NotoShareCapture

/// Test case index
/// 1. explicitURLWins — a `public.url` attachment is used even when the text holds another URL (SC2)
/// 2. urlIsExtractedFromTextWhenNoAttachment — first http(s) token in the text becomes the link; trailing prose punctuation is trimmed (SC2)
/// 3. payloadWithoutURLResolvesToNil — plain text, mailto:, or file URLs stage nothing (SC2)
/// 4. pageTitleFromPreprocessingIsPreferredOverItemTitle — Safari's document.title beats the item's own title; blank titles are skipped (SC2)
/// 5. resolvedBodyUsesLinkFormat — the resolved payload renders through SharedLinkCapture (SC1, SC2)
struct SharedLinkPayloadTests {
    @Test func explicitURLWins() {
        let payload = SharedLinkPayload(
            urls: [URL(string: "https://a.example/one")!],
            texts: ["read https://b.example/two"]
        )
        let resolved = payload.resolve()
        #expect(resolved?.url.absoluteString == "https://a.example/one")
        #expect(resolved?.text == "read https://b.example/two")
    }

    @Test func urlIsExtractedFromTextWhenNoAttachment() {
        let payload = SharedLinkPayload(texts: ["Check this out (https://b.example/two?q=1)."])
        #expect(payload.resolve()?.url.absoluteString == "https://b.example/two?q=1")

        let bare = SharedLinkPayload(texts: ["https://c.example"])
        #expect(bare.resolve()?.url.absoluteString == "https://c.example")
    }

    @Test func payloadWithoutURLResolvesToNil() {
        #expect(SharedLinkPayload(texts: ["just a thought"]).resolve() == nil)
        #expect(SharedLinkPayload(urls: [URL(string: "mailto:me@example.com")!]).resolve() == nil)
        #expect(SharedLinkPayload(urls: [URL(fileURLWithPath: "/tmp/x.pdf")]).resolve() == nil)
        #expect(SharedLinkPayload().resolve() == nil)
    }

    @Test func pageTitleFromPreprocessingIsPreferredOverItemTitle() {
        let url = URL(string: "https://a.example/one")!
        #expect(SharedLinkPayload(urls: [url], pageTitle: "Doc Title", itemTitle: "Item").resolve()?.title == "Doc Title")
        #expect(SharedLinkPayload(urls: [url], pageTitle: "  ", itemTitle: "Item").resolve()?.title == "Item")
        #expect(SharedLinkPayload(urls: [url]).resolve()?.title == nil)
    }

    @Test func resolvedBodyUsesLinkFormat() {
        let payload = SharedLinkPayload(urls: [URL(string: "https://a.example/one")!], pageTitle: "One")
        #expect(payload.resolve()?.body == "[One](https://a.example/one)")
    }
}
