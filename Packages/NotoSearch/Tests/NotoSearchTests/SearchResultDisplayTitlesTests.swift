import Foundation
import Testing
@testable import NotoSearch

struct SearchResultDisplayTitlesTests {
    private func hit(_ name: String, title: String = "Section", score: Double = 0.82) -> SearchResult {
        SearchResult(id: UUID(), kind: .note, noteID: UUID(), fileURL: URL(fileURLWithPath: "/vault/\(name).md"),
                     title: title, breadcrumb: "Projects", snippet: "matching passage", lineStart: 12,
                     score: score, updatedAt: Date(timeIntervalSince1970: 200), createdAt: Date(timeIntervalSince1970: 100))
    }

    @Test func replacesOnlyTitlesAndPreservesRankingAndMatchIdentity() {
        let input = [hit("first", score: 0.92), hit("second", score: 0.80)]
        let output = SearchResultDisplayTitles.resolving(input) { "Title \($0.deletingPathExtension().lastPathComponent)" }
        #expect(output.map(\.title) == ["Title first", "Title second"])
        for (before, after) in zip(input, output) {
            #expect(before.id == after.id)
            #expect(before.kind == after.kind)
            #expect(before.noteID == after.noteID)
            #expect(before.fileURL == after.fileURL)
            #expect(before.breadcrumb == after.breadcrumb)
            #expect(before.snippet == after.snippet)
            #expect(before.lineStart == after.lineStart)
            #expect(before.score == after.score)
            #expect(before.updatedAt == after.updatedAt)
            #expect(before.createdAt == after.createdAt)
        }
    }

    @Test func unreadableOrBlankResolutionKeepsStoredTitle() {
        let input = [hit("gone", title: "Remembered"), hit("blank", title: "Stored")]
        #expect(SearchResultDisplayTitles.resolving(input) { $0.lastPathComponent == "gone.md" ? nil : " \n" } == input)
    }

    @Test func readsEachNoteOnlyOnceIncludingFailedReads() {
        let a = hit("a"), b = hit("b")
        var reads: [URL: Int] = [:]
        let output = SearchResultDisplayTitles.resolving([a, a, b, b]) { url in
            reads[url, default: 0] += 1
            return url == a.fileURL ? "Canonical" : nil
        }
        #expect(reads == [a.fileURL: 1, b.fileURL: 1])
        #expect(output.map(\.title) == ["Canonical", "Canonical", b.title, b.title])
    }
}
