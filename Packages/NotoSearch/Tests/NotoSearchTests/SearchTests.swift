import Foundation
import Testing
import NotoSearch

struct SearchPackageTests {
    @Test
    func dateFilterParserExtractsToday() {
        let parsed = DateFilterParser.parse("notes from today")
        #expect(parsed.text == "notes from")
        #expect(parsed.dateRange != nil)
    }

    @Test
    func hybridRankerMergesKeywordAndSemantic() {
        let idA = UUID()
        let idB = UUID()

        let keyword = [
            KeywordSearchResult(blockId: idA, bm25Score: -5.0),
            KeywordSearchResult(blockId: idB, bm25Score: -2.0),
        ]
        let semantic = [SemanticSearchResult(blockId: idA, similarity: 0.8)]

        let ranked = HybridRanker().rank(keyword: keyword, semantic: semantic)
        #expect(ranked.count == 2)
        #expect(ranked.first?.blockId == idA)
    }
}
