import Foundation
import NotoChat
import Testing
@testable import Noto2

// Test index (bug 031 — an index-change refresh must not kill the in-flight
// AI summary, and a fallback must say why it fell back):
// 1. sameQueryAndNotesDoesNotRestartAStreamingSummary — the reported failure
// 2. sameQueryAndNotesDoesNotRestartAFinishedSummary — a done summary is not redone
// 3. newQueryStartsASummary — typing a different query still summarizes
// 4. changedResultSetStartsASummary — same query, notes appeared → resummarize
// 5. idleAndFailedStatesAlwaysStart — nothing to preserve, so always (re)start
// 6. httpStatusesMapToActionableReasons — 401/402/429/5xx read differently
// 7. networkAndProtocolErrorsMapToActionableReasons — offline vs timeout vs empty

@Suite("Search summary stability")
struct SearchSummaryStabilityTests {
    private let noteA = UUID()
    private let noteB = UUID()

    @Test("An index-change refresh does not restart a streaming summary")
    func sameQueryAndNotesDoesNotRestartAStreamingSummary() {
        #expect(SearchModel.shouldStartSummary(
            summarizedQuery: "startup",
            summarizedNoteIDs: [noteA, noteB],
            state: .streaming,
            query: "startup",
            noteIDs: [noteA, noteB]
        ) == false)
    }

    @Test("An index-change refresh does not redo a finished summary")
    func sameQueryAndNotesDoesNotRestartAFinishedSummary() {
        #expect(SearchModel.shouldStartSummary(
            summarizedQuery: "startup",
            summarizedNoteIDs: [noteA],
            state: .done,
            query: "startup",
            noteIDs: [noteA]
        ) == false)
    }

    @Test("A different query always starts a new summary")
    func newQueryStartsASummary() {
        #expect(SearchModel.shouldStartSummary(
            summarizedQuery: "startup",
            summarizedNoteIDs: [noteA],
            state: .streaming,
            query: "money",
            noteIDs: [noteA]
        ))
    }

    @Test("Same query but a changed result set starts a new summary")
    func changedResultSetStartsASummary() {
        // The index filled in and a new note now matches — the old summary no
        // longer covers the answer on screen.
        #expect(SearchModel.shouldStartSummary(
            summarizedQuery: "startup",
            summarizedNoteIDs: [noteA],
            state: .done,
            query: "startup",
            noteIDs: [noteA, noteB]
        ))
    }

    @Test("Idle and failed states always start a summary")
    func idleAndFailedStatesAlwaysStart() {
        for state in [SearchModel.SummaryState.idle, .failed("boom"), .needsKey] {
            #expect(SearchModel.shouldStartSummary(
                summarizedQuery: "startup",
                summarizedNoteIDs: [noteA],
                state: state,
                query: "startup",
                noteIDs: [noteA]
            ))
        }
    }

    @Test("HTTP failures map to reasons the user can act on")
    func httpStatusesMapToActionableReasons() {
        let cases: [(Int, String)] = [
            (401, "key rejected"),
            (403, "key rejected"),
            (402, "out of credits"),
            (429, "rate limited"),
            (503, "provider error 503"),
            (418, "HTTP 418"),
        ]
        for (status, expected) in cases {
            #expect(SearchModel.shortReason(for: LLMError.http(status: status, body: "")) == expected)
        }
    }

    @Test("Network and protocol failures map to reasons the user can act on")
    func networkAndProtocolErrorsMapToActionableReasons() {
        #expect(SearchModel.shortReason(for: LLMError.emptyResponse) == "empty response")
        #expect(SearchModel.shortReason(for: LLMError.missingAPIKey) == "no API key")
        #expect(SearchModel.shortReason(for: URLError(.notConnectedToInternet)) == "no network")
        #expect(SearchModel.shortReason(for: URLError(.timedOut)) == "timed out")
        #expect(SearchModel.shortReason(for: URLError(.cancelled)) == "interrupted")
    }
}
