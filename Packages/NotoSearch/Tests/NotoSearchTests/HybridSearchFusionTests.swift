import Foundation
import Testing
@testable import NotoSearch

/// Test case index
/// 1. testKeywordOnlyPassthroughWhenSemanticEmpty — fusion is a no-op without semantic hits (SC5)
/// 2. testConsensusOutranksSingleListWins — a note in both lists beats a note in only one (SC5)
/// 3. testSemanticOnlyNoteGetsSynthesizedResult — chunk snippet + lineStart + section kind (SC5)
/// 4. testWholeNoteSemanticHitSynthesizesNoteKind — heading == title → .note, no lineStart (SC5)
/// 5. testKeywordResultsForSameNoteStayTogether — note's section results are kept, no duplicates (SC5)
/// 6. testLimitIsRespected — fused list never exceeds limit (SC5)
/// 7. testPerNoteRowCapPreventsSlotStarvation — a note with many section rows emits at most 2, so more distinct notes fit (bug 019)
struct HybridSearchFusionTests {
    private let vaultURL = URL(fileURLWithPath: "/tmp/vault")

    private func keywordResult(noteID: UUID, title: String, kind: SearchResultKind = .note, id: UUID = UUID()) -> SearchResult {
        SearchResult(
            id: id, kind: kind, noteID: noteID,
            fileURL: vaultURL.appendingPathComponent("\(title).md"),
            title: title, breadcrumb: "", snippet: "kw snippet",
            lineStart: kind == .section ? 5 : nil, score: 1, updatedAt: nil
        )
    }

    private func semanticHit(noteID: UUID, title: String, heading: String? = nil, score: Float) -> SemanticSearchHit {
        SemanticSearchHit(
            chunkID: UUID(), noteID: noteID,
            relativePath: "\(title).md", noteTitle: title,
            heading: heading ?? title, snippet: "semantic snippet",
            lineStart: 12, score: score
        )
    }

    @Test func testKeywordOnlyPassthroughWhenSemanticEmpty() {
        let results = [keywordResult(noteID: UUID(), title: "A"), keywordResult(noteID: UUID(), title: "B")]
        let fused = HybridSearchFusion.fuse(keyword: results, semantic: [], vaultURL: vaultURL, limit: 50)
        #expect(fused.map(\.id) == results.map(\.id))
    }

    @Test func testConsensusOutranksSingleListWins() {
        let noteA = UUID()  // keyword #1 only
        let noteB = UUID()  // keyword #2 AND semantic #1
        let noteC = UUID()  // semantic #2 only
        let keyword = [keywordResult(noteID: noteA, title: "A"), keywordResult(noteID: noteB, title: "B")]
        let semantic = [semanticHit(noteID: noteB, title: "B", score: 0.9), semanticHit(noteID: noteC, title: "C", score: 0.8)]

        let fused = HybridSearchFusion.fuse(keyword: keyword, semantic: semantic, vaultURL: vaultURL, limit: 50)
        let noteOrder = fused.map(\.noteID)
        #expect(noteOrder.first == noteB)
        #expect(noteOrder.contains(noteA))
        #expect(noteOrder.contains(noteC))
        #expect(noteOrder.firstIndex(of: noteA)! < noteOrder.firstIndex(of: noteC)!)
    }

    @Test func testSemanticOnlyNoteGetsSynthesizedResult() {
        let noteID = UUID()
        let hit = semanticHit(noteID: noteID, title: "Rent Note", heading: "Lease", score: 0.7)
        let fused = HybridSearchFusion.fuse(keyword: [], semantic: [hit], vaultURL: vaultURL, limit: 50)

        #expect(fused.count == 1)
        #expect(fused[0].noteID == noteID)
        #expect(fused[0].kind == .section)
        #expect(fused[0].lineStart == 12)
        #expect(fused[0].snippet == "semantic snippet")
        #expect(fused[0].title == "Rent Note")
        #expect(fused[0].fileURL == vaultURL.appendingPathComponent("Rent Note.md"))
    }

    @Test func testWholeNoteSemanticHitSynthesizesNoteKind() {
        let hit = semanticHit(noteID: UUID(), title: "Daily", score: 0.7)
        let fused = HybridSearchFusion.fuse(keyword: [], semantic: [hit], vaultURL: vaultURL, limit: 50)
        #expect(fused[0].kind == .note)
        #expect(fused[0].lineStart == nil)
    }

    @Test func testKeywordResultsForSameNoteStayTogether() {
        let noteID = UUID()
        let noteResult = keywordResult(noteID: noteID, title: "Doc")
        let sectionResult = keywordResult(noteID: noteID, title: "Doc", kind: .section)
        let semantic = [semanticHit(noteID: noteID, title: "Doc", score: 0.9)]

        let fused = HybridSearchFusion.fuse(
            keyword: [noteResult, sectionResult],
            semantic: semantic,
            vaultURL: vaultURL,
            limit: 50
        )
        #expect(fused.count == 2)
        #expect(fused.map(\.id) == [noteResult.id, sectionResult.id])
    }

    @Test func testPerNoteRowCapPreventsSlotStarvation() {
        let hog = UUID()
        let hogRows = [keywordResult(noteID: hog, title: "Hog")]
            + (0..<4).map { _ in keywordResult(noteID: hog, title: "Hog", kind: .section) }
        let others = (0..<5).map { keywordResult(noteID: UUID(), title: "Other\($0)") }
        let semantic = [semanticHit(noteID: hog, title: "Hog", score: 0.9)]

        let fused = HybridSearchFusion.fuse(
            keyword: hogRows + others, semantic: semantic, vaultURL: vaultURL, limit: 8
        )
        #expect(fused.filter { $0.noteID == hog }.count == 2)
        #expect(Set(fused.map(\.noteID)).count >= 6)
    }

    @Test func testLimitIsRespected() {
        let keyword = (0..<10).map { keywordResult(noteID: UUID(), title: "K\($0)") }
        let semantic = (0..<10).map { semanticHit(noteID: UUID(), title: "S\($0)", score: Float(10 - $0) / 10) }
        let fused = HybridSearchFusion.fuse(keyword: keyword, semantic: semantic, vaultURL: vaultURL, limit: 7)
        #expect(fused.count == 7)
    }
}
