import Testing
@testable import NotoVault

@Suite("WordCounter")
struct WordCounterTests {
    @Test
    func emptyMarkdownHasZeroWordsAndCharacters() {
        let count = WordCounter().count(in: "")

        #expect(count.words == 0)
        #expect(count.characters == 0)
    }

    @Test
    func countsWordsAndUserVisibleCharacters() {
        let markdown = "# Shopping List\n\nFresh fruit and milk."

        let count = WordCounter().count(in: markdown)

        #expect(count.words == 6)
        #expect(count.characters == markdown.count)
    }

    @Test
    func stripsFrontmatterBeforeCounting() {
        let markdown = """
        ---
        id: 11111111-1111-1111-1111-111111111111
        created: 2026-04-20T00:00:00Z
        modified: 2026-04-20T00:00:00Z
        ---
        # Title

        Body words here.
        """

        let count = WordCounter().count(in: markdown)

        #expect(count.words == 4)
        #expect(count.characters == "# Title\n\nBody words here.".count)
    }

    @Test
    func countsGraphemeClustersForCharacters() {
        let markdown = "Cafe\u{301} notes 👍🏽"

        let count = WordCounter().count(in: markdown)

        #expect(count.words == 2)
        #expect(count.characters == 12)
    }
}
