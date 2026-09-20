import Foundation
import Testing
@testable import NotoLinkPreview

/// Which lines become preview cards (SC1). The rule is "the whole line is one web URL".
///
/// | Test | Covers |
/// | --- | --- |
/// | `bareHTTPSLineIsDetected` | plain `https://…` line |
/// | `bareHTTPLineIsDetected` | `http://` is accepted too |
/// | `surroundingWhitespaceIsIgnored` | indent / trailing spaces do not matter |
/// | `angleBracketAutolinkIsUnwrapped` | `<https://…>` yields the inner URL |
/// | `queryAndFragmentSurvive` | nothing is stripped from the URL |
/// | `localhostIsAllowed` | dev-server links still card |
/// | `textAroundURLIsNotDetected` | prose containing a link stays prose |
/// | `markdownLinkLineIsDetected` | a line that is exactly `[t](u)` cards (share-sheet captures) |
/// | `markdownLinkWithParenthesesInURLIsDetected` | `%28`/`%29`-encoded destinations survive |
/// | `markdownLinkWithSurroundingTextIsNotDetected` | prose around `[t](u)` stays prose |
/// | `markdownLinkToNonWebURLIsNotDetected` | `[t](mailto:…)` / `[t](Note.md)` never card |
/// | `imageLinkIsNotDetected` | `![](u)` is the image renderer's job |
/// | `nonWebSchemesAreNotDetected` | mailto / ftp / noto-document never card |
/// | `unfinishedHostIsNotDetected` | `https://exa` does not flip mid-keystroke |
/// | `emptyAndBlankLinesAreNotDetected` | no false positives on empty input |
@Suite("LinkPreviewDetector")
struct LinkPreviewDetectorTests {
    @Test("bare https line is detected")
    func bareHTTPSLineIsDetected() {
        let url = LinkPreviewDetector.url(inLine: "https://example.com/article")
        #expect(url?.absoluteString == "https://example.com/article")
    }

    @Test("bare http line is detected")
    func bareHTTPLineIsDetected() {
        #expect(LinkPreviewDetector.url(inLine: "http://example.com")?.host == "example.com")
    }

    @Test("surrounding whitespace is ignored")
    func surroundingWhitespaceIsIgnored() {
        let url = LinkPreviewDetector.url(inLine: "    https://example.com/a   ")
        #expect(url?.absoluteString == "https://example.com/a")
    }

    @Test("angle-bracket autolink is unwrapped")
    func angleBracketAutolinkIsUnwrapped() {
        let url = LinkPreviewDetector.url(inLine: "<https://example.com/a>")
        #expect(url?.absoluteString == "https://example.com/a")
    }

    @Test("query and fragment survive")
    func queryAndFragmentSurvive() {
        let url = LinkPreviewDetector.url(inLine: "https://example.com/a?x=1&y=2#top")
        #expect(url?.query == "x=1&y=2")
        #expect(url?.fragment == "top")
    }

    @Test("localhost is allowed")
    func localhostIsAllowed() {
        #expect(LinkPreviewDetector.url(inLine: "http://localhost:3000/")?.port == 3000)
    }

    @Test("text around the URL is not detected")
    func textAroundURLIsNotDetected() {
        #expect(LinkPreviewDetector.url(inLine: "See https://example.com for details") == nil)
        #expect(LinkPreviewDetector.url(inLine: "https://example.com is great") == nil)
        #expect(LinkPreviewDetector.url(inLine: "- https://example.com") == nil)
    }

    @Test("a line that is exactly a markdown link is detected")
    func markdownLinkLineIsDetected() {
        let url = LinkPreviewDetector.url(inLine: "[Swift - Wikipedia](https://en.wikipedia.org/wiki/Swift)")
        #expect(url?.absoluteString == "https://en.wikipedia.org/wiki/Swift")
        #expect(LinkPreviewDetector.url(inLine: "  [t](http://example.com/a?b=1)  ")?.absoluteString == "http://example.com/a?b=1")
    }

    @Test("markdown link with percent-encoded parentheses in the URL is detected")
    func markdownLinkWithParenthesesInURLIsDetected() {
        let url = LinkPreviewDetector.url(inLine: "[Swift](https://en.wikipedia.org/wiki/Swift_%28programming_language%29)")
        #expect(url?.absoluteString == "https://en.wikipedia.org/wiki/Swift_%28programming_language%29")
    }

    @Test("markdown link with surrounding text is not detected")
    func markdownLinkWithSurroundingTextIsNotDetected() {
        #expect(LinkPreviewDetector.url(inLine: "see [t](https://example.com)") == nil)
        #expect(LinkPreviewDetector.url(inLine: "[t](https://example.com) and more") == nil)
        #expect(LinkPreviewDetector.url(inLine: "[a](https://a.example) [b](https://b.example)") == nil)
    }

    @Test("markdown link to a non-web URL is not detected")
    func markdownLinkToNonWebURLIsNotDetected() {
        #expect(LinkPreviewDetector.url(inLine: "[mail](mailto:me@example.com)") == nil)
        #expect(LinkPreviewDetector.url(inLine: "[note](Projects/Noto.md)") == nil)
        #expect(LinkPreviewDetector.url(inLine: "[broken](https://exa)") == nil)
    }

    @Test("image link is not detected")
    func imageLinkIsNotDetected() {
        #expect(LinkPreviewDetector.url(inLine: "![](https://example.com/a.png)") == nil)
    }

    @Test("non-web schemes are not detected")
    func nonWebSchemesAreNotDetected() {
        #expect(LinkPreviewDetector.url(inLine: "mailto:someone@example.com") == nil)
        #expect(LinkPreviewDetector.url(inLine: "ftp://example.com/file") == nil)
        #expect(LinkPreviewDetector.url(inLine: "noto-document://open?path=a.md") == nil)
        #expect(LinkPreviewDetector.url(inLine: "example.com") == nil)
    }

    @Test("unfinished host is not detected")
    func unfinishedHostIsNotDetected() {
        #expect(LinkPreviewDetector.url(inLine: "https://") == nil)
        #expect(LinkPreviewDetector.url(inLine: "https://exa") == nil)
        #expect(LinkPreviewDetector.url(inLine: "https://.com") == nil)
    }

    @Test("empty and blank lines are not detected")
    func emptyAndBlankLinesAreNotDetected() {
        #expect(LinkPreviewDetector.url(inLine: "") == nil)
        #expect(LinkPreviewDetector.url(inLine: "   ") == nil)
        #expect(LinkPreviewDetector.url(inLine: "<>") == nil)
    }
}
