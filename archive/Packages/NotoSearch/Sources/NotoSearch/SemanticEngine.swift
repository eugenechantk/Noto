//
//  SemanticEngine.swift
//  NotoSearch
//
//  Query execution for semantic search. Embeds query text, searches HNSW,
//  applies similarity threshold and optional date post-filtering.
//

#if canImport(USearch)
import Foundation
import SwiftData
import os.log
import NotoModels
import NotoCore
import NotoEmbedding
import NotoHNSW

private let logger = Logger(subsystem: "com.noto", category: "SemanticEngine")

public struct SemanticEngine {

    public let embeddingModel: EmbeddingModel
    public let hnswIndex: HNSWIndex

    private static let similarityThreshold: Float = 0.3
    private static let overFetchCount = 200

    public init(embeddingModel: EmbeddingModel, hnswIndex: HNSWIndex) {
        self.embeddingModel = embeddingModel
        self.hnswIndex = hnswIndex
    }

    /// Searches for blocks semantically similar to the query.
    ///
    /// 1. Strips markdown from query
    /// 2. Embeds the query via CoreML
    /// 3. Searches HNSW for nearest 200 vectors
    /// 4. Converts distances to cosine similarity (1 - distance)
    /// 5. Filters by threshold >= 0.3
    /// 6. Optionally filters by date range via SwiftData
    /// 7. Returns sorted by similarity descending
    public func search(
        query: String,
        dateRange: DateRange?,
        modelContext: ModelContext
    ) async -> [SemanticSearchResult] {
        let plainQuery = PlainTextExtractor.plainText(from: query)

        guard !plainQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        // Embed the query
        let queryVector: [Float]
        do {
            queryVector = try embeddingModel.embed(plainQuery)
        } catch {
            logger.error("Failed to embed query: \(error)")
            return []
        }

        // Search HNSW
        let rawResults = await hnswIndex.search(vector: queryVector, count: Self.overFetchCount)

        // Convert distance to similarity and filter by threshold
        var candidates: [SemanticSearchResult] = []
        for (blockId, distance) in rawResults {
            let similarity = 1.0 - distance
            if similarity >= Self.similarityThreshold {
                candidates.append(SemanticSearchResult(blockId: blockId, similarity: similarity))
            }
        }

        // Date post-filter if needed
        if let dateRange = dateRange, !candidates.isEmpty {
            let blockIds = candidates.map { $0.blockId }
            let passingIds = fetchBlocksInDateRange(blockIds: blockIds, dateRange: dateRange, modelContext: modelContext)
            candidates = candidates.filter { passingIds.contains($0.blockId) }
        }

        // Sort by similarity descending
        candidates.sort { $0.similarity > $1.similarity }

        return candidates
    }

    // MARK: - Private

    private func fetchBlocksInDateRange(
        blockIds: [UUID],
        dateRange: DateRange,
        modelContext: ModelContext
    ) -> Set<UUID> {
        let start = dateRange.start
        let end = dateRange.end

        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate<Block> { block in
                blockIds.contains(block.id) && block.createdAt >= start && block.createdAt <= end
            }
        )

        do {
            let blocks = try modelContext.fetch(descriptor)
            return Set(blocks.map { $0.id })
        } catch {
            logger.error("Date post-filter fetch failed: \(error)")
            return Set(blockIds) // fail-open: return all on error
        }
    }
}
#endif
