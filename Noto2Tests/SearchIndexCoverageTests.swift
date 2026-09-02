import Foundation
import Testing
@testable import Noto2

// Test index (bug 030 — "no results" must not blame spelling while the index
// is still behind the vault):
// 1. summaryShowsDenominatorWhileIndexLagsVault — "741 / 1131 notes" exposes a stalled index
// 2. summaryDropsDenominatorOnceCaughtUp — equal counts read as a plain total
// 3. summaryPluralizesSingleNote — "1 note", not "1 notes"
// 4. summaryWithoutAnIndexReadsAsNoNotes — nil index count degrades to "no notes"
// 5. partialIndexIsNotPresentedAsAMiss — partial state says so and never mentions spelling
// 6. completeIndexIsPresentedAsAGenuineMiss — complete state keeps the honest "no match" wording
// 7. descriptionQuotesTheQueryInBothStates — the searched term is echoed either way

@Suite("Search index coverage wording")
struct SearchIndexCoverageTests {
    @Test("A lagging index shows indexed / total so the shortfall is visible")
    func summaryShowsDenominatorWhileIndexLagsVault() {
        #expect(SearchIndexCoverage.summary(indexedNotes: 741, vaultNotes: 1131) == "741 / 1131 notes")
    }

    @Test("A caught-up index shows a plain total, not a redundant fraction")
    func summaryDropsDenominatorOnceCaughtUp() {
        #expect(SearchIndexCoverage.summary(indexedNotes: 1131, vaultNotes: 1131) == "1131 notes")
    }

    @Test("A single indexed note is pluralized correctly")
    func summaryPluralizesSingleNote() {
        #expect(SearchIndexCoverage.summary(indexedNotes: 1, vaultNotes: 1) == "1 note")
        #expect(SearchIndexCoverage.summary(indexedNotes: 1, vaultNotes: 12) == "1 / 12 notes")
    }

    @Test("An index that has not reported yet reads as no notes")
    func summaryWithoutAnIndexReadsAsNoNotes() {
        let noIndexYet: Int? = nil
        #expect(SearchIndexCoverage.summary(indexedNotes: noIndexYet, vaultNotes: 1131) == "no notes")
    }

    @Test("A partial index is announced as indexing, never as a spelling problem")
    func partialIndexIsNotPresentedAsAMiss() {
        #expect(SearchIndexCoverage.noResultsTitle(isPartial: true) == "Still Indexing")
        let description = SearchIndexCoverage.noResultsDescription(
            query: "roadmap", isPartial: true, indexedNotes: 3, vaultNotes: 1131
        )
        #expect(description.contains("3 / 1131 notes"))
        #expect(!description.lowercased().contains("spelling"))
    }

    @Test("A complete index still reports an honest miss")
    func completeIndexIsPresentedAsAGenuineMiss() {
        #expect(SearchIndexCoverage.noResultsTitle(isPartial: false) == "No Results")
        let description = SearchIndexCoverage.noResultsDescription(
            query: "roadmap", isPartial: false, indexedNotes: 1131, vaultNotes: 1131
        )
        #expect(description.lowercased().contains("spelling"))
        #expect(!description.contains("1131"))
    }

    @Test("The searched term is echoed back in both states")
    func descriptionQuotesTheQueryInBothStates() {
        for isPartial in [true, false] {
            let description = SearchIndexCoverage.noResultsDescription(
                query: "Q2 roadmap", isPartial: isPartial, indexedNotes: 10, vaultNotes: 1131
            )
            #expect(description.contains("“Q2 roadmap”"))
        }
    }
}
