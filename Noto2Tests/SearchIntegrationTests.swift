import Foundation
import NotoSearch
import Testing
@testable import Noto2

/// Test case index
/// 1. hybridSearchFindsTitleAndBodyHits — indexes a temp vault through the same coordinator the app uses,
///    then runs `HybridNoteSearch` with the Search screen's request shape; a title-only match and a body-only
///    match both come back, an unrelated note does not, and a filed capture is findable by its body (SC3, SC1)
/// 2. dedupedByNoteKeepsFirstRowPerNote — note + section hits of one file collapse to the best-ranked row (SC3)
/// 3. requestCarriesSemanticGate — the screen's request uses the calibrated floor and relative gap (SC3)
struct SearchIntegrationTests {
    @Test func dedupedByNoteKeepsFirstRowPerNote() {
        let a = UUID(), b = UUID()
        func row(_ note: UUID, _ title: String) -> SearchResult {
            SearchResult(id: UUID(), kind: .note, noteID: note, fileURL: URL(fileURLWithPath: "/v/\(title).md"), title: title, breadcrumb: "", snippet: "", lineStart: nil, score: 1, updatedAt: nil)
        }
        let out = SearchModel.dedupedByNote([row(a, "a1"), row(b, "b1"), row(a, "a2")])
        #expect(out.map(\.title) == ["a1", "b1"])
        // A later row with a real snippet replaces a bare (snippet == title) first row, keeping position.
        func bare(_ note: UUID, _ title: String) -> SearchResult {
            SearchResult(id: UUID(), kind: .section, noteID: note, fileURL: URL(fileURLWithPath: "/v/x.md"), title: title, breadcrumb: "", snippet: title, lineStart: nil, score: 1, updatedAt: nil)
        }
        func rich(_ note: UUID, _ title: String) -> SearchResult {
            SearchResult(id: UUID(), kind: .note, noteID: note, fileURL: URL(fileURLWithPath: "/v/x.md"), title: title, breadcrumb: "", snippet: "…the roadmap…", lineStart: nil, score: 1, updatedAt: nil)
        }
        let preferred = SearchModel.dedupedByNote([bare(a, "A"), row(b, "B"), rich(a, "A")])
        #expect(preferred.map(\.title) == ["A", "B"])
        #expect(preferred[0].snippet == "…the roadmap…")
    }

    @Test func requestCarriesSemanticGate() {
        let request = SearchModel.makeRequest(query: "granite")
        #expect(request.scope == .titleAndContent)
        #expect(request.semanticMinScore == SearchModel.semanticMinScore)
        #expect(request.semanticRelativeGap == SearchModel.semanticRelativeGap)
        #expect(request.semanticPeakMargin == SearchModel.semanticPeakMargin)
    }

    @Test func hybridSearchFindsTitleAndBodyHits() async throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("Noto2SearchVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        try "# Granite embeddings\n\nNotes about the on-device model.\n".write(to: vault.appendingPathComponent("Granite embeddings.md"), atomically: true, encoding: .utf8)
        try "# Weekend\n\nWe talked about granite countertops for the kitchen.\n".write(to: vault.appendingPathComponent("Weekend.md"), atomically: true, encoding: .utf8)
        try "# Unrelated\n\nNothing to see here.\n".write(to: vault.appendingPathComponent("Unrelated.md"), atomically: true, encoding: .utf8)
        var filing = CaptureFilingService(vaultURL: vault)
        filing.now = { Date(timeIntervalSince1970: 1_787_000_000) }
        let filed = try filing.file("Remember the quartzite sample from the showroom")

        _ = try await SearchIndexController.shared.rebuildIndex(vaultURL: vault)

        let granite = try HybridNoteSearch.run(
            SearchModel.makeRequest(query: "granite"),
            vaultURL: vault,
            embedQuery: { _ in nil }
        )
        let graniteTitles = Set(granite.map(\.title))
        #expect(graniteTitles.contains("Granite embeddings"))   // title hit
        #expect(graniteTitles.contains("Weekend"))              // body-only hit
        #expect(!graniteTitles.contains("Unrelated"))

        let capture = try HybridNoteSearch.run(
            SearchModel.makeRequest(query: "quartzite"),
            vaultURL: vault,
            embedQuery: { _ in nil }
        )
        #expect(capture.contains { $0.fileURL.standardizedFileURL == filed.fileURL.standardizedFileURL })
    }
}
