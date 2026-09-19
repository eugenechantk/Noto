import Foundation
import Testing
@testable import NotoShareCapture

/// Test case index
/// 1. bodyIsMarkdownLinkWithTitle — `[title](url)` from a URL and a page title (SC1)
/// 2. bodyFallsBackToURLAsTitle — nil/blank title → the URL is the link text, like the editor's toggle (SC1)
/// 3. titleBracketsAndNewlinesAreNeutralised — `[`/`]` become parens, whitespace runs collapse, so the link cannot close early (SC1)
/// 4. parenthesesInURLArePercentEncoded — `(`/`)`/space in the URL are encoded so the `(url)` part survives the link regex (SC1)
/// 5. sharedTextFollowsLinkAsSecondParagraph — selected text is appended after a blank line (SC2)
/// 6. textEqualToURLOrTitleIsNotRepeated — text that merely repeats the URL or the title is dropped (SC2)
struct SharedLinkCaptureTests {
    private let url = URL(string: "https://example.com/post?id=7")!

    @Test func bodyIsMarkdownLinkWithTitle() {
        let body = SharedLinkCapture.body(url: url, title: "A Great Post")
        #expect(body == "[A Great Post](https://example.com/post?id=7)")
    }

    @Test func bodyFallsBackToURLAsTitle() {
        #expect(SharedLinkCapture.body(url: url, title: nil)
            == "[https://example.com/post?id=7](https://example.com/post?id=7)")
        #expect(SharedLinkCapture.body(url: url, title: "  \n ")
            == "[https://example.com/post?id=7](https://example.com/post?id=7)")
    }

    @Test func titleBracketsAndNewlinesAreNeutralised() {
        let body = SharedLinkCapture.body(url: url, title: "  [Draft]  Title\nwith\r\nlines ")
        #expect(body == "[(Draft) Title with lines](https://example.com/post?id=7)")
        // Exactly one markdown link, and it spans the whole line.
        let regex = try! NSRegularExpression(pattern: #"(?<!!)\[([^\]\n]+)\]\(([^)\n]+)\)"#)
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: (body as NSString).length))
        #expect(matches.count == 1)
        #expect(matches.first?.range == NSRange(location: 0, length: (body as NSString).length))
    }

    @Test func parenthesesInURLArePercentEncoded() {
        let wiki = URL(string: "https://en.wikipedia.org/wiki/Swift_(programming_language)")!
        let body = SharedLinkCapture.body(url: wiki, title: "Swift")
        #expect(body == "[Swift](https://en.wikipedia.org/wiki/Swift_%28programming_language%29)")
        let regex = try! NSRegularExpression(pattern: #"(?<!!)\[([^\]\n]+)\]\(([^)\n]+)\)"#)
        let match = regex.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length))
        let captured = (body as NSString).substring(with: match!.range(at: 2))
        #expect(captured == "https://en.wikipedia.org/wiki/Swift_%28programming_language%29")
        #expect(URL(string: captured)?.path == "/wiki/Swift_(programming_language)")
    }

    @Test func sharedTextFollowsLinkAsSecondParagraph() {
        let body = SharedLinkCapture.body(url: url, title: "Post", text: "  A quote I liked.\r\nSecond line.  ")
        #expect(body == "[Post](https://example.com/post?id=7)\n\nA quote I liked.\nSecond line.")
    }

    @Test func textEqualToURLOrTitleIsNotRepeated() {
        #expect(SharedLinkCapture.body(url: url, title: "Post", text: url.absoluteString)
            == "[Post](https://example.com/post?id=7)")
        #expect(SharedLinkCapture.body(url: url, title: "Post", text: "Post")
            == "[Post](https://example.com/post?id=7)")
        #expect(SharedLinkCapture.body(url: url, title: nil, text: " ")
            == "[https://example.com/post?id=7](https://example.com/post?id=7)")
    }
}
