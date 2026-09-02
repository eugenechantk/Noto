import Foundation
import Testing
@testable import Noto2

/// Test case index
/// 1. tokensDedupeAndDropShortWords — query splits on non-alphanumerics, drops 1-char words, dedupes, longest first (SC3)
/// 2. segmentsEmphasizeMatchesCaseInsensitively — snippet splits into plain/emphasized runs around each match (SC3)
/// 3. noTokensLeavesSnippetPlain — empty query → one plain segment (SC3)
/// 4. overlappingTokensPreferLongest — "notes" beats "note" so the longer run is emphasized once (SC3)
/// 5. stemsMatchSingularAndPlural — "surfaces" emphasizes "surface" and "surfacing"; whole words only (SC3)
struct SnippetEmphasisTests {
    @Test func stemsMatchSingularAndPlural() {
        #expect(SnippetEmphasis.stems(for: "surfaces") == ["surfaces", "surface", "surfac"])
        #expect(SnippetEmphasis.stems(for: "is") == ["is"])
        let segments = SnippetEmphasis.segments(of: "the app surface, resurfacing later", query: "surfaces")
        #expect(segments == [
            .init(text: "the app ", emphasized: false),
            .init(text: "surface", emphasized: true),
            .init(text: ", resurfacing later", emphasized: false),
        ])
    }

    @Test func tokensDedupeAndDropShortWords() {
        #expect(SnippetEmphasis.tokens(from: "a Granite, granite embeddings!") == ["embeddings", "granite"])
    }

    @Test func segmentsEmphasizeMatchesCaseInsensitively() {
        let segments = SnippetEmphasis.segments(of: "Granite ships; Granite is fast", query: "granite")
        #expect(segments == [
            .init(text: "Granite", emphasized: true),
            .init(text: " ships; ", emphasized: false),
            .init(text: "Granite", emphasized: true),
            .init(text: " is fast", emphasized: false),
        ])
    }

    @Test func noTokensLeavesSnippetPlain() {
        #expect(SnippetEmphasis.segments(of: "plain text", query: "") == [.init(text: "plain text", emphasized: false)])
        #expect(SnippetEmphasis.segments(of: "plain text", query: "x") == [.init(text: "plain text", emphasized: false)])
    }

    @Test func overlappingTokensPreferLongest() {
        let segments = SnippetEmphasis.segments(of: "my notes", query: "note notes")
        #expect(segments == [.init(text: "my ", emphasized: false), .init(text: "notes", emphasized: true)])
    }
}
