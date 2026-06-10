import Foundation
import Testing
@testable import NotoSearch

/// Test case index
/// 1. testSmallNoteBecomesSingleChunk — whole-note path with title header (SC1)
/// 2. testLargeNoteSplitsPerSectionWithContextualHeaders — `title > heading` prefix per section (SC1)
/// 3. testOversizedSectionSplitsIntoParts — greedy line split under the token cap, distinct stable IDs (SC1)
/// 4. testTinyNoteProducesNoChunks — below the minimum token floor (SC1)
/// 5. testHeadingMatchingTitleIsNotDuplicatedInHeader — header stays `title`, not `title > title` (SC1)
/// 6. testChunkingIsDeterministic — same document → identical IDs and hashes (SC1)
/// 7. testModelVersionChangesContentHash — hash includes model version, driving full re-embed on swap (SC1, SC3)
/// 8. testCJKTokenEstimateCountsCharacters — CJK ≈ one token per character (SC1)
/// 9. testLatinTokenEstimateScalesWithWords — Latin ≈ chars/4 per word (SC1)
struct SemanticChunkerTests {
    private let chunker = SemanticChunker(modelVersion: "test-v1")

    @Test func testSmallNoteBecomesSingleChunk() {
        let document = makeDocument(
            title: "Garden Plan",
            sections: [("Garden Plan", 1, "Start tomato seedlings indoors in February.")]
        )
        let chunks = chunker.chunks(for: document)
        #expect(chunks.count == 1)
        #expect(chunks[0].embeddedText.hasPrefix("Garden Plan\n"))
        #expect(chunks[0].heading == "Garden Plan")
        #expect(chunks[0].noteID == document.id)
    }

    @Test func testLargeNoteSplitsPerSectionWithContextualHeaders() {
        let document = makeDocument(
            title: "Launch Notes",
            sections: [
                ("Acquisition", 2, longText(approximateTokens: 250)),
                ("Monetization", 2, longText(approximateTokens: 250)),
            ]
        )
        let chunks = chunker.chunks(for: document)
        #expect(chunks.count == 2)
        #expect(chunks[0].embeddedText.hasPrefix("Launch Notes > Acquisition\n"))
        #expect(chunks[1].embeddedText.hasPrefix("Launch Notes > Monetization\n"))
        #expect(chunks[0].snippetText.hasPrefix("The quarterly review"))
    }

    @Test func testOversizedSectionSplitsIntoParts() {
        let document = makeDocument(
            title: "Big Note",
            sections: [("Huge Section", 2, longText(approximateTokens: 1_300))]
        )
        let chunks = chunker.chunks(for: document)
        #expect(chunks.count >= 3)
        for chunk in chunks {
            #expect(SemanticChunker.estimatedTokens(chunk.snippetText) <= 400 + 50)
            #expect(chunk.embeddedText.hasPrefix("Big Note > Huge Section\n"))
        }
        #expect(Set(chunks.map(\.id)).count == chunks.count)
    }

    @Test func testTinyNoteProducesNoChunks() {
        let document = makeDocument(
            title: "x",
            sections: [("x", nil, "ok")],
            plainText: "ok"
        )
        #expect(chunker.chunks(for: document).isEmpty)
    }

    @Test func testHeadingMatchingTitleIsNotDuplicatedInHeader() {
        let document = makeDocument(
            title: "Daily 2026-06-10",
            sections: [
                ("Daily 2026-06-10", nil, longText(approximateTokens: 250)),
                ("Reflections", 2, longText(approximateTokens: 250)),
            ]
        )
        let chunks = chunker.chunks(for: document)
        #expect(chunks[0].embeddedText.hasPrefix("Daily 2026-06-10\nThe quarterly"))
        #expect(chunks[1].embeddedText.hasPrefix("Daily 2026-06-10 > Reflections\n"))
    }

    @Test func testChunkingIsDeterministic() {
        let id = UUID()
        let make = {
            makeDocument(
                id: id,
                title: "Stable",
                sections: [("Part", 2, longText(approximateTokens: 500))]
            )
        }
        let first = chunker.chunks(for: make())
        let second = chunker.chunks(for: make())
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.contentHash) == second.map(\.contentHash))
    }

    @Test func testModelVersionChangesContentHash() {
        let document = makeDocument(
            title: "Note",
            sections: [("Note", nil, "Some meaningful body content here.")]
        )
        let v1 = SemanticChunker(modelVersion: "v1").chunks(for: document)
        let v2 = SemanticChunker(modelVersion: "v2").chunks(for: document)
        #expect(v1[0].contentHash != v2[0].contentHash)
        #expect(v1[0].id == v2[0].id)
    }

    @Test func testCJKTokenEstimateCountsCharacters() {
        let text = "今天和房东谈续租的事情"
        let estimate = SemanticChunker.estimatedTokens(text)
        #expect(estimate >= 10)
        #expect(estimate <= 14)
    }

    @Test func testLatinTokenEstimateScalesWithWords() {
        let estimate = SemanticChunker.estimatedTokens("budget review meeting")
        #expect(estimate >= 3)
        #expect(estimate <= 7)
    }
}
