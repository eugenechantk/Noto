//
//  SearchService.swift
//  NotoSearch
//
//  Orchestrates the full search pipeline: flush dirty -> parse date ->
//  parallel FTS5 (+ semantic when available) -> hybrid rank -> build results.
//

import Foundation
import SwiftData
import os.log
import NotoModels
import NotoCore
import NotoDirtyTracker
import NotoFTS5
import NotoEmbedding

private let logger = Logger(subsystem: "com.noto", category: "SearchService")

public final class SearchService {

    public let fts5Database: FTS5Database
    public let dirtyTracker: DirtyTracker
    public let dirtyStore: DirtyStore
    public let modelContext: ModelContext

    private let dateFilterParser = DateFilterParser()
    private let hybridRanker = HybridRanker()

    public init(fts5Database: FTS5Database, dirtyTracker: DirtyTracker, dirtyStore: DirtyStore, modelContext: ModelContext) {
        self.fts5Database = fts5Database
        self.dirtyTracker = dirtyTracker
        self.dirtyStore = dirtyStore
        self.modelContext = modelContext
    }

    // MARK: - Index Freshness

    /// Flushes dirty blocks from memory to the dirty_blocks table,
    /// then processes them into the FTS5 index.
    @MainActor
    public func ensureIndexFresh() async {
        await dirtyTracker.flush()

        let indexer = FTS5Indexer(fts5Database: fts5Database, dirtyStore: dirtyStore, modelContext: modelContext)
        await indexer.flushAll()
    }

    // MARK: - Search

    /// Runs the full search pipeline for a raw query string.
    ///
    /// 1. Parse date filter from query
    /// 2. Short-circuit for empty/date-only queries
    /// 3. Run keyword search (and semantic when available)
    /// 4. Hybrid rank
    /// 5. Build SearchResults with breadcrumbs
    @MainActor
    public func search(rawQuery: String) async -> [SearchResult] {
        let query = dateFilterParser.parse(rawQuery)

        // Empty text + no date = nothing to search
        if query.text.isEmpty && query.dateRange == nil {
            return []
        }

        // Date-only: return all blocks in range sorted by recency
        if query.text.isEmpty, let dateRange = query.dateRange {
            return dateOnlySearch(dateRange: dateRange)
        }

        // Run keyword search
        let fts5Engine = FTS5Engine(fts5Database: fts5Database)
        let keywordResults = await fts5Engine.search(
            query: query.text,
            dateRange: query.dateRange,
            modelContext: modelContext
        )

        // Semantic search is only available when USearch is compiled in.
        // For now, pass empty semantic results -- HybridRanker will use alpha=1.0 (pure keyword).
        let semanticResults: [SemanticSearchResult] = []

        // Fetch block contents for exact match boost
        let allBlockIds = Set(keywordResults.map { $0.blockId })
        let blockContents = fetchBlockContents(blockIds: allBlockIds)

        // Hybrid rank
        let ranked = hybridRanker.rank(
            keyword: keywordResults,
            semantic: semanticResults,
            queryText: query.text,
            blockContents: blockContents
        )

        // Build final results with breadcrumbs
        return buildResults(from: ranked, blockContents: blockContents)
    }

    // MARK: - Private

    private func dateOnlySearch(dateRange: DateRange) -> [SearchResult] {
        let start = dateRange.start
        let end = dateRange.end
        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate<Block> { block in
                block.isArchived == false &&
                block.createdAt >= start &&
                block.createdAt <= end
            },
            sortBy: [SortDescriptor(\Block.updatedAt, order: .reverse)]
        )

        do {
            let blocks = try modelContext.fetch(descriptor)
            return blocks.map { block in
                SearchResult(
                    id: block.id,
                    content: block.content,
                    breadcrumb: BreadcrumbBuilder.build(for: block),
                    hybridScore: 1.0
                )
            }
        } catch {
            logger.error("dateOnlySearch fetch failed: \(error)")
            return []
        }
    }

    private func fetchBlockContents(blockIds: Set<UUID>) -> [UUID: String] {
        guard !blockIds.isEmpty else { return [:] }

        let ids = Array(blockIds)
        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate<Block> { block in
                ids.contains(block.id)
            }
        )

        do {
            let blocks = try modelContext.fetch(descriptor)
            return Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.content) })
        } catch {
            logger.error("fetchBlockContents failed: \(error)")
            return [:]
        }
    }

    private func buildResults(from ranked: [RankedResult], blockContents: [UUID: String]) -> [SearchResult] {
        let blockIds = ranked.map { $0.blockId }
        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate<Block> { block in
                blockIds.contains(block.id)
            }
        )

        let blocks: [Block]
        do {
            blocks = try modelContext.fetch(descriptor)
        } catch {
            logger.error("buildResults fetch failed: \(error)")
            return []
        }

        let blockMap = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })

        return ranked.compactMap { result in
            guard let block = blockMap[result.blockId] else { return nil }
            return SearchResult(
                id: block.id,
                content: block.content,
                breadcrumb: BreadcrumbBuilder.build(for: block),
                hybridScore: result.hybridScore
            )
        }
    }
}
