import Foundation

/// Wording for how much of the vault the keyword index currently covers.
///
/// Noto 2 keeps its own search index (separate app container from Noto), so on
/// a fresh install — or a phone whose vault lives in iCloud, where note bodies
/// start out evicted — the index legitimately lags the vault for a while. In
/// that window an honest "nothing matches" and "this note is not indexed yet"
/// look identical, which reads as "search is broken". These strings make the
/// difference visible; the view only decides where to put them.
enum SearchIndexCoverage {
    /// "741 / 1131 notes" while the index lags the vault, "741 notes" once it
    /// has caught up (or when the vault total is unknown). The denominator is
    /// what makes a stalled index legible at a glance.
    static func summary(indexedNotes: Int?, vaultNotes: Int?) -> String {
        guard let indexedNotes else { return "no notes" }
        if let vaultNotes, vaultNotes != indexedNotes {
            return "\(indexedNotes) / \(vaultNotes) notes"
        }
        return "\(indexedNotes) note\(indexedNotes == 1 ? "" : "s")"
    }

    /// Title for the empty result list.
    static func noResultsTitle(isPartial: Bool) -> String {
        isPartial ? "Still Indexing" : "No Results"
    }

    /// Body for the empty result list. When the index is behind the vault the
    /// user needs to know the miss may not be real — telling them to check
    /// their spelling in that state is actively misleading.
    static func noResultsDescription(query: String, isPartial: Bool, indexedNotes: Int?, vaultNotes: Int?) -> String {
        guard isPartial else {
            return "No notes match “\(query)”. Check the spelling or try a new search."
        }
        let coverage = summary(indexedNotes: indexedNotes, vaultNotes: vaultNotes)
        return "Only \(coverage) are searchable so far, so “\(query)” may be in a note that has not been indexed yet."
    }
}
