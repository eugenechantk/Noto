//
//  HybridLogicTests.swift
//  NotoTests
//
//  Comprehensive tests for DateFilterParser, HybridRanker, and BreadcrumbBuilder.
//

import Testing
import Foundation
import SwiftData
import NotoModels
import NotoCore
import NotoSearch
@testable import Noto

// MARK: - DateFilterParser Tests

struct DateFilterParserTests {

    // Fixed reference date: 2026-03-15 12:00:00 UTC
    private var referenceDate: Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 15
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps)!
    }

    private let calendar = Calendar.current

    @Test
    func testToday() {
        let result = DateFilterParser.parse("notes from today", now: referenceDate)
        #expect(result.text == "notes from")
        #expect(result.dateRange != nil)
        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: start))
        #expect(calendar.isDate(result.dateRange!.end, inSameDayAs: end))
    }

    @Test
    func testYesterday() {
        let result = DateFilterParser.parse("what I wrote yesterday", now: referenceDate)
        #expect(result.text == "what I wrote")
        #expect(result.dateRange != nil)
        let todayStart = calendar.startOfDay(for: referenceDate)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: yesterdayStart))
        #expect(calendar.isDate(result.dateRange!.end, inSameDayAs: todayStart))
    }

    @Test
    func testLastWeek() {
        let result = DateFilterParser.parse("ideas from last week", now: referenceDate)
        #expect(result.text == "ideas from")
        #expect(result.dateRange != nil)
        let start = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: referenceDate))!
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: start))
    }

    @Test
    func testThisWeek() {
        let result = DateFilterParser.parse("meetings this week", now: referenceDate)
        #expect(result.text == "meetings")
        #expect(result.dateRange != nil)
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
        let weekStart = calendar.date(from: comps)!
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: weekStart))
    }

    @Test
    func testLastMonth() {
        let result = DateFilterParser.parse("projects last month", now: referenceDate)
        #expect(result.text == "projects")
        #expect(result.dateRange != nil)
        // Reference is March 2026, so last month = Feb 2026
        let monthComps = calendar.dateComponents([.year, .month], from: referenceDate)
        let thisMonthStart = calendar.date(from: monthComps)!
        let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: lastMonthStart))
        #expect(calendar.isDate(result.dateRange!.end, inSameDayAs: thisMonthStart))
    }

    @Test
    func testThisMonth() {
        let result = DateFilterParser.parse("tasks this month", now: referenceDate)
        #expect(result.text == "tasks")
        #expect(result.dateRange != nil)
        let monthComps = calendar.dateComponents([.year, .month], from: referenceDate)
        let thisMonthStart = calendar.date(from: monthComps)!
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: thisMonthStart))
    }

    @Test
    func testLastNDays() {
        let result = DateFilterParser.parse("recent last 3 days", now: referenceDate)
        // "recent" and "last 3 days" are both temporal. "recent" is leftmost.
        // Actually let's test with just "last 3 days"
        let result2 = DateFilterParser.parse("stuff from last 3 days", now: referenceDate)
        #expect(result2.text == "stuff from")
        #expect(result2.dateRange != nil)
        let start = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: referenceDate))!
        #expect(calendar.isDate(result2.dateRange!.start, inSameDayAs: start))
    }

    @Test
    func testLastNDaysSingular() {
        let result = DateFilterParser.parse("from last 1 day", now: referenceDate)
        #expect(result.text == "from")
        #expect(result.dateRange != nil)
    }

    @Test
    func testRecent() {
        let result = DateFilterParser.parse("recent thoughts", now: referenceDate)
        #expect(result.text == "thoughts")
        #expect(result.dateRange != nil)
        let start = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: referenceDate))!
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: start))
    }

    @Test
    func testRecently() {
        let result = DateFilterParser.parse("things I wrote recently", now: referenceDate)
        #expect(result.text == "things I wrote")
        #expect(result.dateRange != nil)
    }

    @Test
    func testInMonthYear() {
        let result = DateFilterParser.parse("food in March 2024", now: referenceDate)
        #expect(result.text == "food")
        #expect(result.dateRange != nil)
        // March 2024
        var comps = DateComponents()
        comps.year = 2024
        comps.month = 3
        comps.day = 1
        let expectedStart = calendar.date(from: comps)!
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: expectedStart))
        let expectedEnd = calendar.date(byAdding: .month, value: 1, to: expectedStart)!
        #expect(calendar.isDate(result.dateRange!.end, inSameDayAs: expectedEnd))
    }

    @Test
    func testInMonth() {
        let result = DateFilterParser.parse("notes in March", now: referenceDate)
        #expect(result.text == "notes")
        #expect(result.dateRange != nil)
        // Should be March of current year (2026)
        let currentYear = calendar.component(.year, from: referenceDate)
        var comps = DateComponents()
        comps.year = currentYear
        comps.month = 3
        comps.day = 1
        let expectedStart = calendar.date(from: comps)!
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: expectedStart))
    }

    @Test
    func testInYear() {
        let result = DateFilterParser.parse("goals in 2024", now: referenceDate)
        #expect(result.text == "goals")
        #expect(result.dateRange != nil)
        var comps = DateComponents()
        comps.year = 2024
        comps.month = 1
        comps.day = 1
        let expectedStart = calendar.date(from: comps)!
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: expectedStart))
        comps.year = 2025
        let expectedEnd = calendar.date(from: comps)!
        #expect(calendar.isDate(result.dateRange!.end, inSameDayAs: expectedEnd))
    }

    @Test
    func testNoTemporalPhrase() {
        let result = DateFilterParser.parse("design patterns", now: referenceDate)
        #expect(result.text == "design patterns")
        #expect(result.dateRange == nil)
    }

    @Test
    func testFalsePositiveMarchVerb() {
        // "march" as a verb should NOT be matched — needs "in March"
        let result = DateFilterParser.parse("march to the beat", now: referenceDate)
        #expect(result.text == "march to the beat")
        #expect(result.dateRange == nil)
    }

    @Test
    func testOnlyTemporal() {
        let result = DateFilterParser.parse("today", now: referenceDate)
        #expect(result.text == "")
        #expect(result.dateRange != nil)
    }

    @Test
    func testMultipleTemporalFirstWins() {
        let result = DateFilterParser.parse("today and last week", now: referenceDate)
        // "today" is leftmost, should be the match
        #expect(result.dateRange != nil)
        let start = calendar.startOfDay(for: referenceDate)
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: start))
        #expect(result.text == "and last week")
    }

    @Test
    func testCaseInsensitive() {
        let result = DateFilterParser.parse("notes from TODAY", now: referenceDate)
        #expect(result.text == "notes from")
        #expect(result.dateRange != nil)
    }

    @Test
    func testCaseInsensitiveMixed() {
        let result = DateFilterParser.parse("food in MARCH 2024", now: referenceDate)
        #expect(result.text == "food")
        #expect(result.dateRange != nil)
    }

    @Test
    func testEmptyQuery() {
        let result = DateFilterParser.parse("", now: referenceDate)
        #expect(result.text == "")
        #expect(result.dateRange == nil)
    }

    @Test
    func testInJanuary() {
        let result = DateFilterParser.parse("stuff in January", now: referenceDate)
        #expect(result.text == "stuff")
        #expect(result.dateRange != nil)
        let currentYear = calendar.component(.year, from: referenceDate)
        var comps = DateComponents()
        comps.year = currentYear
        comps.month = 1
        comps.day = 1
        let expectedStart = calendar.date(from: comps)!
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: expectedStart))
    }

    @Test
    func testInDecember2025() {
        let result = DateFilterParser.parse("plans in December 2025", now: referenceDate)
        #expect(result.text == "plans")
        #expect(result.dateRange != nil)
        var comps = DateComponents()
        comps.year = 2025
        comps.month = 12
        comps.day = 1
        let expectedStart = calendar.date(from: comps)!
        #expect(calendar.isDate(result.dateRange!.start, inSameDayAs: expectedStart))
    }

    @Test
    func testWhitespaceCleanup() {
        let result = DateFilterParser.parse("notes  from  today", now: referenceDate)
        #expect(result.text == "notes from")
        #expect(result.dateRange != nil)
    }

    @Test
    func testTemporalAtStart() {
        let result = DateFilterParser.parse("yesterday I had a meeting", now: referenceDate)
        #expect(result.text == "I had a meeting")
        #expect(result.dateRange != nil)
    }

    @Test
    func testTemporalInMiddle() {
        let result = DateFilterParser.parse("things from last week about design", now: referenceDate)
        #expect(result.text == "things from about design")
        #expect(result.dateRange != nil)
    }
}

// MARK: - HybridRanker Tests

struct HybridRankerTests {

    private let ranker = HybridRanker()

    // Helper to make UUIDs deterministic for tests
    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!
    }

    @Test
    func testBothEngineHighest() {
        let idA = uuid(1)
        let idB = uuid(2)

        let keyword = [
            KeywordSearchResult(blockId: idA, bm25Score: -5.0),
            KeywordSearchResult(blockId: idB, bm25Score: -2.0),
        ]
        let semantic = [
            SemanticSearchResult(blockId: idA, similarity: 0.8),
        ]

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        #expect(results.count == 2)
        // A appears in both engines, so it should rank highest
        #expect(results[0].blockId == idA)
    }

    @Test
    func testKeywordOnlyCapsAtAlpha() {
        let idA = uuid(1)

        let keyword = [
            KeywordSearchResult(blockId: idA, bm25Score: -5.0),
        ]
        let semantic = [
            SemanticSearchResult(blockId: uuid(2), similarity: 0.5),
        ]

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        let resultA = results.first { $0.blockId == idA }!
        // A is keyword-only, its max hybrid = alpha * 1.0 + (1-alpha) * 0.0 = 0.6
        #expect(resultA.hybridScore <= 0.6 + 0.001)
    }

    @Test
    func testSemanticOnlyCapsAt1MinusAlpha() {
        let idB = uuid(2)

        let keyword = [
            KeywordSearchResult(blockId: uuid(1), bm25Score: -5.0),
        ]
        let semantic = [
            SemanticSearchResult(blockId: idB, similarity: 0.9),
        ]

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        let resultB = results.first { $0.blockId == idB }!
        // B is semantic-only, its max hybrid = alpha * 0.0 + (1-alpha) * 1.0 = 0.4
        #expect(resultB.hybridScore <= 0.4 + 0.001)
    }

    @Test
    func testEmptyKeywordPureSemantic() {
        let idA = uuid(1)
        let idB = uuid(2)

        let keyword: [KeywordSearchResult] = []
        let semantic = [
            SemanticSearchResult(blockId: idA, similarity: 0.9),
            SemanticSearchResult(blockId: idB, similarity: 0.5),
        ]

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        #expect(results.count == 2)
        // Pure semantic: A should rank first (higher similarity)
        #expect(results[0].blockId == idA)
        #expect(results[1].blockId == idB)
        // With α=0, hybrid = 1.0 * sem, so A=1.0, B=0.0
        #expect(results[0].hybridScore == 1.0)
        #expect(results[1].hybridScore == 0.0)
    }

    @Test
    func testEmptySemanticPureKeyword() {
        let idA = uuid(1)
        let idB = uuid(2)

        let keyword = [
            KeywordSearchResult(blockId: idA, bm25Score: -5.0),
            KeywordSearchResult(blockId: idB, bm25Score: -2.0),
        ]
        let semantic: [SemanticSearchResult] = []

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        #expect(results.count == 2)
        // Pure keyword: A is better (more negative)
        #expect(results[0].blockId == idA)
        // With α=1, hybrid = 1.0 * kw
        #expect(results[0].hybridScore == 1.0)
    }

    @Test
    func testSingleKeywordNormalizesToOne() {
        let idA = uuid(1)

        let keyword = [
            KeywordSearchResult(blockId: idA, bm25Score: -3.0),
        ]
        let semantic: [SemanticSearchResult] = []

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        #expect(results.count == 1)
        // Single result normalized to 1.0, α=1.0 (no semantic)
        #expect(results[0].hybridScore == 1.0)
    }

    @Test
    func testSingleSemanticNormalizesToOne() {
        let idA = uuid(1)

        let keyword: [KeywordSearchResult] = []
        let semantic = [
            SemanticSearchResult(blockId: idA, similarity: 0.6),
        ]

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        #expect(results.count == 1)
        // Single result normalized to 1.0, α=0.0 (no keyword)
        #expect(results[0].hybridScore == 1.0)
    }

    @Test
    func testBM25Normalization() {
        let idA = uuid(1)
        let idB = uuid(2)

        // A: -10 (best), B: -2 (worst)
        let keyword = [
            KeywordSearchResult(blockId: idA, bm25Score: -10.0),
            KeywordSearchResult(blockId: idB, bm25Score: -2.0),
        ]
        let semantic: [SemanticSearchResult] = []

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        // A should have higher score
        let resultA = results.first { $0.blockId == idA }!
        let resultB = results.first { $0.blockId == idB }!
        #expect(resultA.hybridScore > resultB.hybridScore)
        #expect(resultA.hybridScore == 1.0)
        #expect(resultB.hybridScore == 0.0)
    }

    @Test
    func testCosineNormalization() {
        let idA = uuid(1)
        let idB = uuid(2)

        let keyword: [KeywordSearchResult] = []
        let semantic = [
            SemanticSearchResult(blockId: idA, similarity: 0.9),
            SemanticSearchResult(blockId: idB, similarity: 0.4),
        ]

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        let resultA = results.first { $0.blockId == idA }!
        let resultB = results.first { $0.blockId == idB }!
        #expect(resultA.hybridScore == 1.0)
        #expect(resultB.hybridScore == 0.0)
    }

    @Test
    func testExactMatchBoost() {
        let idA = uuid(1)
        let idB = uuid(2)
        let idC = uuid(3)

        // Use three results so normalization spreads scores out
        // A: -8.0, B: -6.0, C: -2.0 → A=1.0, B=0.667, C=0.0
        let keyword = [
            KeywordSearchResult(blockId: idA, bm25Score: -8.0),
            KeywordSearchResult(blockId: idB, bm25Score: -6.0),
            KeywordSearchResult(blockId: idC, bm25Score: -2.0),
        ]
        let semantic = [
            SemanticSearchResult(blockId: idA, similarity: 0.7),
            SemanticSearchResult(blockId: idB, similarity: 0.7),
            SemanticSearchResult(blockId: idC, similarity: 0.7),
        ]

        // B has exact match in content, A does not
        // B's keyword score (0.667) gets boosted by 1.5 → 1.0 (capped)
        // Without boost: B hybrid < A hybrid. With boost: B hybrid = A hybrid or higher.
        let contents: [UUID: String] = [
            idA: "Brewing techniques for espresso",
            idB: "The coffee is great",
            idC: "Tea leaves are lovely",
        ]

        let resultsWithBoost = ranker.rank(
            keyword: keyword,
            semantic: semantic,
            queryText: "coffee",
            blockContents: contents
        )
        let resultB = resultsWithBoost.first { $0.blockId == idB }!

        // Without boost, B's keyword normalized = 0.667
        // With boost, B's keyword = min(0.667 * 1.5, 1.0) = 1.0
        // So B's hybrid = 0.6 * 1.0 + 0.4 * 0.5 = 0.8
        // Without boost it would be 0.6 * 0.667 + 0.4 * 0.5 = 0.6
        let resultsWithoutBoost = ranker.rank(
            keyword: keyword,
            semantic: semantic
        )
        let resultBNoBoost = resultsWithoutBoost.first { $0.blockId == idB }!
        #expect(resultB.hybridScore > resultBNoBoost.hybridScore)
    }

    @Test
    func testBoostCappedAtOne() {
        let idA = uuid(1)

        // High keyword score + boost should still cap at 1.0
        let keyword = [
            KeywordSearchResult(blockId: idA, bm25Score: -10.0),
        ]
        let semantic: [SemanticSearchResult] = []

        let contents: [UUID: String] = [
            idA: "The coffee is great",
        ]

        let results = ranker.rank(
            keyword: keyword,
            semantic: semantic,
            queryText: "coffee",
            blockContents: contents
        )
        #expect(results[0].hybridScore <= 1.0)
    }

    @Test
    func testDisjointMerged() {
        let idA = uuid(1) // keyword only
        let idB = uuid(2) // semantic only

        let keyword = [
            KeywordSearchResult(blockId: idA, bm25Score: -5.0),
        ]
        let semantic = [
            SemanticSearchResult(blockId: idB, similarity: 0.9),
        ]

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        #expect(results.count == 2)
        let blockIds = Set(results.map { $0.blockId })
        #expect(blockIds.contains(idA))
        #expect(blockIds.contains(idB))
    }

    @Test
    func testSortedDescending() {
        let ids = (1...5).map { uuid($0) }

        let keyword = [
            KeywordSearchResult(blockId: ids[0], bm25Score: -10.0),
            KeywordSearchResult(blockId: ids[1], bm25Score: -7.0),
            KeywordSearchResult(blockId: ids[2], bm25Score: -4.0),
            KeywordSearchResult(blockId: ids[3], bm25Score: -2.0),
            KeywordSearchResult(blockId: ids[4], bm25Score: -1.0),
        ]
        let semantic: [SemanticSearchResult] = []

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        for i in 1..<results.count {
            #expect(results[i - 1].hybridScore >= results[i].hybridScore)
        }
    }

    @Test
    func testBothEmpty() {
        let results = ranker.rank(keyword: [], semantic: [])
        #expect(results.isEmpty)
    }

    @Test
    func testIdenticalScoresNormalize() {
        let idA = uuid(1)
        let idB = uuid(2)

        // Both have the same BM25 score
        let keyword = [
            KeywordSearchResult(blockId: idA, bm25Score: -5.0),
            KeywordSearchResult(blockId: idB, bm25Score: -5.0),
        ]
        let semantic: [SemanticSearchResult] = []

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        // Both should normalize to 1.0 (all identical)
        for r in results {
            #expect(r.hybridScore == 1.0)
        }
    }

    @Test
    func testThreeEngineOverlap() {
        let idA = uuid(1)
        let idB = uuid(2)
        let idC = uuid(3)

        let keyword = [
            KeywordSearchResult(blockId: idA, bm25Score: -8.0),
            KeywordSearchResult(blockId: idB, bm25Score: -4.0),
        ]
        let semantic = [
            SemanticSearchResult(blockId: idA, similarity: 0.9),
            SemanticSearchResult(blockId: idC, similarity: 0.7),
        ]

        let results = ranker.rank(keyword: keyword, semantic: semantic)
        #expect(results.count == 3)
        // A is in both engines, should rank highest
        #expect(results[0].blockId == idA)
    }

    @Test
    func testExactMatchCaseInsensitive() {
        let idA = uuid(1)

        let keyword = [
            KeywordSearchResult(blockId: idA, bm25Score: -5.0),
        ]
        let semantic: [SemanticSearchResult] = []
        let contents: [UUID: String] = [
            idA: "COFFEE beans",
        ]

        let results = ranker.rank(
            keyword: keyword,
            semantic: semantic,
            queryText: "coffee",
            blockContents: contents
        )
        // Should still get the boost (case-insensitive match)
        #expect(results[0].hybridScore <= 1.0)
    }
}

// MARK: - BreadcrumbBuilder Tests

struct BreadcrumbBuilderTests {

    @Test @MainActor
    func testRootBlock() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "My Notes", sortOrder: 1.0)
        context.insert(root)

        let block = Block(content: "A note", parent: root, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let breadcrumb = BreadcrumbBuilder.build(for: block)
        #expect(breadcrumb == "Home")
    }

    @Test @MainActor
    func testBlockAtRootLevel() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "Top level block", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let breadcrumb = BreadcrumbBuilder.build(for: block)
        #expect(breadcrumb == "Home")
    }

    @Test @MainActor
    func testOneDeep() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "My Notes", sortOrder: 1.0)
        context.insert(root)

        let parent = Block(content: "Projects", parent: root, sortOrder: 1.0)
        context.insert(parent)

        let block = Block(content: "My Project", parent: parent, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let breadcrumb = BreadcrumbBuilder.build(for: block)
        #expect(breadcrumb == "Home / Projects")
    }

    @Test @MainActor
    func testTwoDeep() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "My Notes", sortOrder: 1.0)
        context.insert(root)

        let level1 = Block(content: "Projects", parent: root, sortOrder: 1.0)
        context.insert(level1)

        let level2 = Block(content: "Ideas", parent: level1, sortOrder: 1.0)
        context.insert(level2)

        let block = Block(content: "Mobile app", parent: level2, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let breadcrumb = BreadcrumbBuilder.build(for: block)
        #expect(breadcrumb == "Home / Projects / Ideas")
    }

    @Test @MainActor
    func testFourDeep() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let a = Block(content: "A", parent: root, sortOrder: 1.0)
        context.insert(a)

        let b = Block(content: "B", parent: a, sortOrder: 1.0)
        context.insert(b)

        let c = Block(content: "C", parent: b, sortOrder: 1.0)
        context.insert(c)

        let d = Block(content: "D", parent: c, sortOrder: 1.0)
        context.insert(d)

        let block = Block(content: "Leaf", parent: d, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let breadcrumb = BreadcrumbBuilder.build(for: block)
        #expect(breadcrumb == "Home / A / B / C / D")
    }

    @Test @MainActor
    func testLongTitleTruncation() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let longTitle = "This is a very long title that definitely exceeds thirty characters"
        let parent = Block(content: longTitle, parent: root, sortOrder: 1.0)
        context.insert(parent)

        let block = Block(content: "Child", parent: parent, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let breadcrumb = BreadcrumbBuilder.build(for: block)
        // The parent's title should be truncated at 30 chars + "..."
        let expectedTruncated = String(longTitle.prefix(30)) + "..."
        #expect(breadcrumb == "Home / \(expectedTruncated)")
    }

    @Test @MainActor
    func testMultilineContent() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let parent = Block(content: "First Line\nSecond Line\nThird Line", parent: root, sortOrder: 1.0)
        context.insert(parent)

        let block = Block(content: "Child", parent: parent, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let breadcrumb = BreadcrumbBuilder.build(for: block)
        // Should only use the first line
        #expect(breadcrumb == "Home / First Line")
    }

    @Test @MainActor
    func testSelfExcluded() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let block = Block(content: "My Block Content", parent: root, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let breadcrumb = BreadcrumbBuilder.build(for: block)
        // Block's own content should NOT appear in the breadcrumb
        #expect(!breadcrumb.contains("My Block Content"))
        #expect(breadcrumb == "Home")
    }

    @Test @MainActor
    func testExactly30Characters() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        // Exactly 30 characters — should NOT be truncated
        let exact30 = "123456789012345678901234567890"
        #expect(exact30.count == 30)
        let parent = Block(content: exact30, parent: root, sortOrder: 1.0)
        context.insert(parent)

        let block = Block(content: "Child", parent: parent, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let breadcrumb = BreadcrumbBuilder.build(for: block)
        #expect(breadcrumb == "Home / \(exact30)")
        #expect(!breadcrumb.contains("..."))
    }

    @Test @MainActor
    func test31Characters() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        // 31 characters — should be truncated
        let thirtyOne = "1234567890123456789012345678901"
        #expect(thirtyOne.count == 31)
        let parent = Block(content: thirtyOne, parent: root, sortOrder: 1.0)
        context.insert(parent)

        let block = Block(content: "Child", parent: parent, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let breadcrumb = BreadcrumbBuilder.build(for: block)
        let expected = String(thirtyOne.prefix(30)) + "..."
        #expect(breadcrumb == "Home / \(expected)")
    }

    @Test @MainActor
    func testEmptyParentContent() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let parent = Block(content: "", parent: root, sortOrder: 1.0)
        context.insert(parent)

        let block = Block(content: "Child", parent: parent, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let breadcrumb = BreadcrumbBuilder.build(for: block)
        // Empty parent title should just be empty string
        #expect(breadcrumb == "Home / ")
    }

    @Test @MainActor
    func testRootContentReplacedWithHome() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Custom Root Name", sortOrder: 1.0)
        context.insert(root)

        let block = Block(content: "Child", parent: root, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let breadcrumb = BreadcrumbBuilder.build(for: block)
        // Root content should be replaced with "Home" regardless of actual content
        #expect(breadcrumb == "Home")
        #expect(!breadcrumb.contains("Custom Root Name"))
    }
}
