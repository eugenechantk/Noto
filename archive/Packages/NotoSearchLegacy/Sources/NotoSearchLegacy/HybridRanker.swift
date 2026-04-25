//
//  HybridRanker.swift
//  NotoSearchLegacy
//
//  Score normalization and combination for hybrid search ranking.
//  Normalizes BM25 (negative) and cosine similarity scores to [0,1],
//  then combines them with a weighted formula.
//

import Foundation

public struct HybridRanker {

    public let alpha: Double = 0.6 // keyword weight

    public init() {}

    /// Rank results from keyword and semantic engines into a unified scored list.
    ///
    /// - Parameters:
    ///   - keyword: BM25 results from FTS5 (scores are negative; more negative = better).
    ///   - semantic: Cosine similarity results from HNSW.
    ///   - queryText: Original query text for exact match boost (optional).
    ///   - blockContents: Map of blockId to content for exact match checking (optional).
    /// - Returns: Ranked results sorted by hybrid score descending.
    public func rank(
        keyword: [KeywordSearchResult],
        semantic: [SemanticSearchResult],
        queryText: String = "",
        blockContents: [UUID: String] = [:]
    ) -> [RankedResult] {

        // Short-circuit: both empty
        if keyword.isEmpty && semantic.isEmpty {
            return []
        }

        // Build lookup maps
        let keywordMap = Dictionary(uniqueKeysWithValues: keyword.map { ($0.blockId, $0.bm25Score) })
        let semanticMap = Dictionary(uniqueKeysWithValues: semantic.map { ($0.blockId, $0.similarity) })

        // Union all block IDs
        let allBlockIds = Set(keywordMap.keys).union(Set(semanticMap.keys))

        // Normalize keyword scores (BM25: negative, more negative = better)
        let normalizedKeyword: [UUID: Double]
        if keyword.isEmpty {
            normalizedKeyword = [:]
        } else if keyword.count == 1 {
            normalizedKeyword = [keyword[0].blockId: 1.0]
        } else {
            let scores = keyword.map { $0.bm25Score }
            let bestScore = scores.min()!  // most negative = best
            let worstScore = scores.max()! // least negative = worst
            let range = bestScore - worstScore // negative value
            if range == 0 {
                // All scores identical
                normalizedKeyword = Dictionary(uniqueKeysWithValues: keyword.map { ($0.blockId, 1.0) })
            } else {
                normalizedKeyword = Dictionary(uniqueKeysWithValues: keyword.map { result in
                    let normalized = (result.bm25Score - worstScore) / (bestScore - worstScore)
                    return (result.blockId, normalized)
                })
            }
        }

        // Normalize semantic scores (cosine similarity: higher = better)
        let normalizedSemantic: [UUID: Double]
        if semantic.isEmpty {
            normalizedSemantic = [:]
        } else if semantic.count == 1 {
            normalizedSemantic = [semantic[0].blockId: 1.0]
        } else {
            let sims = semantic.map { Double($0.similarity) }
            let minSim = sims.min()!
            let maxSim = sims.max()!
            let range = maxSim - minSim
            if range == 0 {
                normalizedSemantic = Dictionary(uniqueKeysWithValues: semantic.map { ($0.blockId, 1.0) })
            } else {
                normalizedSemantic = Dictionary(uniqueKeysWithValues: semantic.map { result in
                    let normalized = (Double(result.similarity) - minSim) / (maxSim - minSim)
                    return (result.blockId, normalized)
                })
            }
        }

        // Short-circuit alpha
        let effectiveAlpha: Double
        if keyword.isEmpty {
            effectiveAlpha = 0.0 // pure semantic
        } else if semantic.isEmpty {
            effectiveAlpha = 1.0 // pure keyword
        } else {
            effectiveAlpha = alpha
        }

        // Compute hybrid scores
        var results: [RankedResult] = []
        let lowerQuery = queryText.lowercased()

        for blockId in allBlockIds {
            var kw = normalizedKeyword[blockId] ?? 0.0
            let sem = normalizedSemantic[blockId] ?? 0.0

            // Exact match boost: multiply keyword score by 1.5
            if !lowerQuery.isEmpty, let content = blockContents[blockId] {
                if content.lowercased().contains(lowerQuery) {
                    kw = min(kw * 1.5, 1.0)
                }
            }

            let hybrid = effectiveAlpha * kw + (1 - effectiveAlpha) * sem
            results.append(RankedResult(blockId: blockId, hybridScore: min(hybrid, 1.0)))
        }

        // Sort descending by hybrid score
        results.sort { $0.hybridScore > $1.hybridScore }
        return results
    }
}
