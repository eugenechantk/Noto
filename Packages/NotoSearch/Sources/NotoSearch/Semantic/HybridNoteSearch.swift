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
        public var keywordLimit: Int
        public var semanticLimit: Int
        public var limit: Int

        public init(
            query: String,
            scope: SearchScope = .titleAndContent,
            dateFilter: SearchDateFilter = SearchDateFilter(),
            keywordLimit: Int = 150,
            semanticLimit: Int = 50,
            limit: Int = 100
        ) {
            self.query = query
            self.scope = scope
            self.dateFilter = dateFilter
            self.keywordLimit = keywordLimit
            self.semanticLimit = semanticLimit
            self.limit = limit
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
            dateFilter: request.dateFilter
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

        let hits: [SemanticSearchHit]
        do {
            guard let vector = try embedQuery(request.query) else { return nil }
            hits = try SemanticSearcher(indexDirectory: directory)
                .search(queryVector: vector, limit: request.semanticLimit)
        } catch {
            return nil
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
