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
    func dateFilterParserExtractsThisYear() {
        // Use a fixed "now" so assertions are deterministic
        let now = ISO8601DateFormatter().date(from: "2026-03-07T12:00:00Z")!
        let parsed = DateFilterParser.parse("what I wrote this year", now: now)

        #expect(parsed.text == "what I wrote")
        #expect(parsed.dateRange != nil)

        let cal = Calendar.current
        let start = parsed.dateRange!.start
        #expect(cal.component(.year, from: start) == 2026)
        #expect(cal.component(.month, from: start) == 1)
        #expect(cal.component(.day, from: start) == 1)
        #expect(parsed.dateRange!.end == now)
    }

    @Test
    func dateFilterParserExtractsLastYear() {
        let now = ISO8601DateFormatter().date(from: "2026-03-07T12:00:00Z")!
        let parsed = DateFilterParser.parse("notes from last year", now: now)

        #expect(parsed.text == "notes from")
        #expect(parsed.dateRange != nil)

        let cal = Calendar.current
        let start = parsed.dateRange!.start
        let end = parsed.dateRange!.end
        #expect(cal.component(.year, from: start) == 2025)
        #expect(cal.component(.month, from: start) == 1)
        #expect(cal.component(.day, from: start) == 1)
        #expect(cal.component(.year, from: end) == 2026)
        #expect(cal.component(.month, from: end) == 1)
        #expect(cal.component(.day, from: end) == 1)
    }

    @Test
    func dateFilterParserExtractsLastYearPossessive() {
        let now = ISO8601DateFormatter().date(from: "2026-03-07T12:00:00Z")!
        let parsed = DateFilterParser.parse("last year's goals", now: now)

        #expect(parsed.text == "goals")
        #expect(parsed.dateRange != nil)

        let cal = Calendar.current
        #expect(cal.component(.year, from: parsed.dateRange!.start) == 2025)
    }

    @Test
    func dateFilterParserThisYearEmbeddedInQuery() {
        let now = ISO8601DateFormatter().date(from: "2026-06-15T10:00:00Z")!
        let parsed = DateFilterParser.parse("projects this year about swift", now: now)

        #expect(parsed.text == "projects about swift")
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
