import Foundation

/// The one shared entry point for hybrid (keyword + semantic) note search.
/// The search sheet's semantic stage and the chat agent's `search` tool both
/// run through here, so ranking semantics never drift between surfaces.
///
/// The embedding model is injected as a closure (`embedQuery`) because only
/// the app layer links it; returning `nil` from the closure degrades the
/// search to keyword-only.
public enum HybridNoteSearch {
    public struct Request: Sendable {
        public var query: String
        public var scope: SearchScope
        public var dateFilter: SearchDateFilter
        /// Restricts both legs to notes inside this vault folder (any depth).
        /// Normalized via `SearchFolderFilter.normalizedPrefix`.
        public var folderPrefix: String?
        public var keywordLimit: Int
        public var semanticLimit: Int
        public var limit: Int
        /// Absolute cosine floor for semantic chunk hits. The default matches
        /// `SemanticSearcher.search`'s historical floor.
        public var semanticMinScore: Float
        /// When set, semantic hits must also score within this distance of the
        /// best semantic hit. Embedding models with a high similarity floor
        /// (granite: unrelated text ≈ 0.70, related ≈ 0.80+) otherwise surface
        /// every note in a small vault as a "meaning" match. `nil` disables.
        public var semanticRelativeGap: Float?
        /// When set, the semantic leg is used only if the best hit stands at least
        /// this far above the median of the fetched hits. Gibberish queries score
        /// flat (granite: top − median ≈ 0.04); real queries peak (≥ 0.11), so
        /// this keeps "no results" reachable. `nil` disables. Needs ≥ 4 hits.
        public var semanticPeakMargin: Float?

        public init(
            query: String,
            scope: SearchScope = .titleAndContent,
            dateFilter: SearchDateFilter = SearchDateFilter(),
            folderPrefix: String? = nil,
            keywordLimit: Int = 150,
            semanticLimit: Int = 50,
            limit: Int = 100,
            semanticMinScore: Float = 0.2,
            semanticRelativeGap: Float? = nil,
            semanticPeakMargin: Float? = nil
        ) {
            self.query = query
            self.scope = scope
            self.dateFilter = dateFilter
            self.folderPrefix = folderPrefix
            self.keywordLimit = keywordLimit
            self.semanticLimit = semanticLimit
            self.limit = limit
            self.semanticMinScore = semanticMinScore
            self.semanticRelativeGap = semanticRelativeGap
            self.semanticPeakMargin = semanticPeakMargin
        }
    }

    /// One-shot hybrid search: keyword leg (date-filtered in SQL) + semantic
    /// leg (date-filtered against the note catalog) fused with RRF.
    public static func run(
        _ request: Request,
        vaultURL: URL,
        indexDirectory: URL? = nil,
        embedQuery: (String) throws -> [Float]?
    ) throws -> [SearchResult] {
        let directory = indexDirectory ?? MarkdownSearchIndexer.defaultIndexDirectory(for: vaultURL)
        let store = try SearchIndexStore(indexDirectory: directory)
        let keyword = try store.search(
            query: request.query,
            scope: request.scope,
            vaultURL: vaultURL,
            limit: request.keywordLimit,
            dateFilter: request.dateFilter,
            folderPrefix: request.folderPrefix
        )
        return fuseWithSemantic(
            keyword: keyword,
            request: request,
            vaultURL: vaultURL,
            indexDirectory: directory,
            embedQuery: embedQuery
        ) ?? keyword
    }

    /// Fusion half, reusable by callers that already ran (and displayed) the
    /// keyword leg — the search sheet's two-stage flow. Returns `nil` when the
    /// Keeps only hits within `gap` of the best hit's score (hits arrive sorted
    /// by score descending). Pure; exposed for tests.
    public static func applyRelativeGap(_ hits: [SemanticSearchHit], gap: Float?) -> [SemanticSearchHit] {
        guard let gap, let best = hits.map(\.score).max() else { return hits }
        let floor = best - gap
        return hits.filter { $0.score >= floor }
    }

    /// True when the top score clears the median by at least `margin` (or when
    /// the test is disabled / there are too few scores to judge). Pure; for tests.
    public static func passesPeakTest(scores: [Float], margin: Float?) -> Bool {
        guard let margin, scores.count >= 4 else { return true }
        let sorted = scores.sorted(by: >)
        let median = sorted[sorted.count / 2]
        return sorted[0] - median >= margin
    }

    /// semantic leg has nothing to add, so callers keep their keyword list.
    public static func fuseWithSemantic(
        keyword: [SearchResult],
        request: Request,
        vaultURL: URL,
        indexDirectory: URL? = nil,
        embedQuery: (String) throws -> [Float]?
    ) -> [SearchResult]? {
        guard request.scope == .titleAndContent else { return nil }
        let directory = indexDirectory ?? MarkdownSearchIndexer.defaultIndexDirectory(for: vaultURL)

        var hits: [SemanticSearchHit]
        do {
            guard let vector = try embedQuery(request.query) else { return nil }
            // Fetch broadly when the peak test is on so the median reflects the
            // corpus baseline, then apply the floor.
            let fetchFloor = request.semanticPeakMargin == nil ? request.semanticMinScore : min(request.semanticMinScore, 0.2)
            hits = try SemanticSearcher(indexDirectory: directory)
                .search(queryVector: vector, limit: request.semanticLimit, minScore: fetchFloor)
        } catch {
            return nil
        }
        guard passesPeakTest(scores: hits.map(\.score), margin: request.semanticPeakMargin) else { return nil }
        hits = hits.filter { $0.score >= request.semanticMinScore }
        hits = applyRelativeGap(hits, gap: request.semanticRelativeGap)

        if let folder = SearchFolderFilter.normalizedPrefix(request.folderPrefix) {
            hits = hits.filter { SearchFolderFilter.matches(relativePath: $0.relativePath, normalizedPrefix: folder) }
        }

        let filteredHits: [SemanticSearchHit]
        if request.dateFilter.isActive {
            guard let dates = try? SearchIndexStore(indexDirectory: directory).noteDates() else { return nil }
            filteredHits = hits.filter { hit in
                let noteDates = dates[hit.noteID]
                return request.dateFilter.matches(created: noteDates?.created, updated: noteDates?.updated)
            }
        } else {
            filteredHits = hits
        }
        guard !filteredHits.isEmpty else { return nil }

        return HybridSearchFusion.fuse(
            keyword: keyword,
            semantic: filteredHits,
            vaultURL: vaultURL,
            limit: request.limit
        )
    }
}
