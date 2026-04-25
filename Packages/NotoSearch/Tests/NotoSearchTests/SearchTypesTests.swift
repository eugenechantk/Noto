import Foundation
import Testing
import NotoSearch

@Suite("SearchTypes")
struct SearchTypesTests {
    @Test("Search result distinguishes note and section matches")
    func searchResultKindDistinguishesResultGranularity() {
        let noteID = UUID()
        let result = SearchResult(
            id: UUID(),
            kind: .section,
            noteID: noteID,
            fileURL: URL(fileURLWithPath: "/tmp/Noto/Captures/Example.md"),
            title: "Acquisition",
            breadcrumb: "Captures / Example",
            snippet: "TikTok launch loop",
            lineStart: 12,
            score: 0.92,
            updatedAt: nil
        )

        #expect(result.kind == .section)
        #expect(result.noteID == noteID)
        #expect(result.lineStart == 12)
    }

    @Test("Search document carries heading-bounded sections")
    func searchDocumentCarriesSections() {
        let noteID = UUID()
        let section = SearchSection(
            id: UUID(),
            noteID: noteID,
            heading: "Pricing",
            level: 2,
            lineStart: 20,
            lineEnd: 34,
            sectionIndex: 1,
            contentHash: "section-hash",
            plainText: "Subscription tests and conversion notes"
        )
        let document = SearchDocument(
            id: noteID,
            relativePath: "Captures/Example.md",
            title: "Example",
            folderPath: "Captures",
            contentHash: "note-hash",
            plainText: "Full note text",
            sections: [section]
        )

        #expect(document.sections == [section])
        #expect(document.sections.first?.heading == "Pricing")
    }
}
