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

#if canImport(USearch)
import NotoHNSW
#endif

private let logger = Logger(subsystem: "com.noto", category: "SearchService")

public final class SearchService {

    public let fts5Database: FTS5Database
    public let dirtyTracker: DirtyTracker
    public let dirtyStore: DirtyStore
    public let modelContext: ModelContext

    private let dateFilterParser = DateFilterParser()
    private let hybridRanker = HybridRanker()

    #if canImport(USearch)
    private let embeddingModel: EmbeddingModel?
    private let hnswIndex: HNSWIndex?
    private let vectorKeyStore: VectorKeyStore?
    #endif

    #if canImport(USearch)
    public init(
        fts5Database: FTS5Database,
        dirtyTracker: DirtyTracker,
        dirtyStore: DirtyStore,
        modelContext: ModelContext,
        embeddingModel: EmbeddingModel?,
        hnswIndex: HNSWIndex?,
        vectorKeyStore: VectorKeyStore?
    ) {
        self.fts5Database = fts5Database
        self.dirtyTracker = dirtyTracker
        self.dirtyStore = dirtyStore
        self.modelContext = modelContext
        self.embeddingModel = embeddingModel
        self.hnswIndex = hnswIndex
        self.vectorKeyStore = vectorKeyStore
    }
    #else
    public init(fts5Database: FTS5Database, dirtyTracker: DirtyTracker, dirtyStore: DirtyStore, modelContext: ModelContext) {
        self.fts5Database = fts5Database
        self.dirtyTracker = dirtyTracker
        self.dirtyStore = dirtyStore
        self.modelContext = modelContext
    }
    #endif

    // MARK: - Index Freshness

    /// Flushes dirty blocks from memory to the dirty_blocks table,
    /// then processes them through both FTS5 and embedding pipelines.
    @MainActor
    public func ensureIndexFresh() async {
        await dirtyTracker.flush()

        let fts5Indexer = FTS5Indexer(fts5Database: fts5Database, dirtyStore: dirtyStore, modelContext: modelContext)

        #if canImport(USearch)
        if let embeddingModel = embeddingModel, let hnswIndex = hnswIndex {
            // Coordinate both pipelines from the same dirty batch
            let embeddingIndexer = EmbeddingIndexer(embeddingModel: embeddingModel, hnswIndex: hnswIndex, modelContext: modelContext)
            var totalProcessed = 0

            while true {
                let batch = await dirtyStore.fetchDirtyBatch(limit: 50)
                if batch.isEmpty { break }

                // Process through both pipelines
                await fts5Indexer.processBatch(batch)
                await embeddingIndexer.processDirtyBlocks(blockIds: batch.map { ($0.blockId, $0.operation) })

                // Remove after both succeed
                let processedIds = batch.map { $0.blockId }
                await dirtyStore.removeDirty(blockIds: processedIds)
                totalProcessed += processedIds.count
            }

            if totalProcessed > 0 {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                await dirtyStore.setMetadata(key: "lastFullReconciliationAt", value: timestamp)
                logger.info("ensureIndexFresh processed \(totalProcessed) dirty blocks (FTS5 + embedding)")
            }
        } else {
            // Fallback: keyword-only
            await fts5Indexer.flushAll()
        }
        #else
        await fts5Indexer.flushAll()
        #endif
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
        let keywordResults: [KeywordSearchResult]
        let semanticResults: [SemanticSearchResult]

        #if canImport(USearch)
        if let embeddingModel = embeddingModel, let hnswIndex = hnswIndex {
            // Run keyword and semantic search in parallel
            async let keywordTask = fts5Engine.search(
                query: query.text,
                dateRange: query.dateRange,
                modelContext: modelContext
            )
            async let semanticTask = SemanticEngine(
                embeddingModel: embeddingModel,
                hnswIndex: hnswIndex
            ).search(
                query: query.text,
                dateRange: query.dateRange,
                modelContext: modelContext
            )

            keywordResults = await keywordTask
            semanticResults = await semanticTask
        } else {
            keywordResults = await fts5Engine.search(
                query: query.text,
                dateRange: query.dateRange,
                modelContext: modelContext
            )
            semanticResults = []
        }
        #else
        keywordResults = await fts5Engine.search(
            query: query.text,
            dateRange: query.dateRange,
            modelContext: modelContext
        )
        semanticResults = []
        #endif

        // Fetch block contents for exact match boost
        let allBlockIds = Set(keywordResults.map { $0.blockId } + semanticResults.map { $0.blockId })
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
