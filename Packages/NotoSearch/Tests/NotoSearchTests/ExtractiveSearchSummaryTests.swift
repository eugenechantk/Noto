import Testing
@testable import NotoSearch

struct ExtractiveSearchSummaryTests {
    @Test func queryRelevantSentencesWinAndRemainAttributed() {
        let summary = ExtractiveSearchSummary.text(
            query: "roadmap",
            sources: [
                .init(title: "Project Plan", body: "This is generic background. The product roadmap prioritizes search and capture."),
                .init(title: "Meeting", body: "Review the roadmap with the design team on Thursday."),
            ]
        )

        #expect(summary.contains("The product roadmap prioritizes search and capture. — Project Plan"))
        #expect(summary.contains("Review the roadmap with the design team on Thursday. — Meeting"))
    }

    @Test func coversDistinctSourcesBeforeRepeatingOne() {
        let summary = ExtractiveSearchSummary.text(
            query: "project",
            sources: [
                .init(title: "A", body: "The project has a first important detail. The project has a second important detail."),
                .init(title: "B", body: "The project also appears in this separate note."),
            ],
            limit: 2
        )

        #expect(summary.components(separatedBy: "\n").count == 2)
        #expect(summary.contains("— A"))
        #expect(summary.contains("— B"))
    }

    @Test func cleansMarkdownAndDeduplicatesVerbatimClaims() {
        let summary = ExtractiveSearchSummary.text(
            query: "prototype",
            sources: [
                .init(title: "Tasks", body: "# Prototype\n- [ ] Build the **prototype** for Friday's review."),
                .init(title: "Duplicate", body: "Build the **prototype** for Friday's review."),
            ]
        )

        #expect(summary == "• Build the prototype for Friday's review. — Tasks")
        #expect(!summary.contains("[ ]"))
        #expect(!summary.contains("**"))
    }

    @Test func noTermOverlapFallsBackToSearchRankOrder() {
        let summary = ExtractiveSearchSummary.text(
            query: "完全不同",
            sources: [
                .init(title: "First", body: "The first ranked note still provides a useful concrete sentence."),
                .init(title: "Second", body: "The second ranked note contributes another concrete sentence."),
            ],
            limit: 1
        )

        #expect(summary == "• The first ranked note still provides a useful concrete sentence. — First")
    }
}
