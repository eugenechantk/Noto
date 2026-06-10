import Foundation
import Testing
@testable import NotoSearch

/// Test case index
/// 1. testExtractsVaultAttachmentWithPercentEncoding — editor-written `![alt](.attachments/My%20Receipt.png)` decodes (SC14)
/// 2. testExtractsRemoteURL — http/https targets marked remote, URL preserved (SC14)
/// 3. testLineNumbersAreFullFileOneBased — frontmatter lines count toward line numbers (SC14)
/// 4. testIgnoresDataURIsAndAbsolutePaths — unsupported targets skipped (SC14)
/// 5. testHandlesTitleSyntaxAndMultiplePerLine — `![a](p "title")` and two refs on one line (SC14)
/// 6. testEmptyAltTextAllowed — `![]()` style with empty alt still extracts (SC14)
struct MarkdownImageExtractorTests {
    @Test func testExtractsVaultAttachmentWithPercentEncoding() {
        let refs = MarkdownImageExtractor.references(
            in: "# Note\n\n![receipt scan](.attachments/My%20Receipt.png)"
        )
        #expect(refs.count == 1)
        #expect(refs[0].altText == "receipt scan")
        #expect(refs[0].target == ".attachments/My Receipt.png")
        #expect(refs[0].isRemote == false)
        #expect(refs[0].line == 3)
    }

    @Test func testExtractsRemoteURL() {
        let refs = MarkdownImageExtractor.references(
            in: "![chart](https://example.com/charts/q3.png)"
        )
        #expect(refs.count == 1)
        #expect(refs[0].target == "https://example.com/charts/q3.png")
        #expect(refs[0].isRemote == true)
    }

    @Test func testLineNumbersAreFullFileOneBased() {
        let markdown = """
        ---
        id: 44444444-4444-4444-8444-444444444444
        ---
        # Title

        ![first](.attachments/a.png)
        text
        ![second](.attachments/b.png)
        """
        let refs = MarkdownImageExtractor.references(in: markdown)
        #expect(refs.map(\.line) == [6, 8])
    }

    @Test func testIgnoresDataURIsAndAbsolutePaths() {
        let markdown = """
        ![inline](data:image/png;base64,AAAA)
        ![abs](/etc/passwd.png)
        ![ok](.attachments/ok.png)
        """
        let refs = MarkdownImageExtractor.references(in: markdown)
        #expect(refs.count == 1)
        #expect(refs[0].target == ".attachments/ok.png")
    }

    @Test func testHandlesTitleSyntaxAndMultiplePerLine() {
        let markdown = #"![a](.attachments/a.png "A title") and ![b](https://x.com/b.jpg)"#
        let refs = MarkdownImageExtractor.references(in: markdown)
        #expect(refs.count == 2)
        #expect(refs[0].target == ".attachments/a.png")
        #expect(refs[1].isRemote == true)
    }

    @Test func testEmptyAltTextAllowed() {
        let refs = MarkdownImageExtractor.references(in: "![](.attachments/photo.jpg)")
        #expect(refs.count == 1)
        #expect(refs[0].altText.isEmpty)
    }
}
