import Foundation

/// Reciprocal Rank Fusion of the keyword (FTS/BM25) and semantic (cosine)
/// result lists.
///
/// RRF is score-agnostic — only rank positions matter — which sidesteps the
/// fact that BM25 scores and cosine similarities live in incompatible
/// distributions. k=60 is the canonical constant (Cormack et al. 2009;
/// Elasticsearch/Azure default); the optimum is flat across [20, 100].
public enum HybridSearchFusion {
    /// Fuses note-level rankings: each note's best keyword rank and best
    /// semantic rank contribute `1/(k + rank)`. Notes are emitted in fused
    /// order; a note keeps its keyword display results, and a semantic-only
    /// note gets one synthesized result from its best chunk.
    public static func fuse(
        keyword: [SearchResult],
        semantic: [SemanticSearchHit],
        vaultURL: URL,
        k: Double = 60,
        limit: Int = 50,
        maxResultsPerNote: Int = 2
    ) -> [SearchResult] {
        guard !semantic.isEmpty else { return Array(keyword.prefix(limit)) }

        // Note-level rank = position of the note's first (best) appearance.
        var keywordRank: [UUID: Int] = [:]
        for result in keyword where keywordRank[result.noteID] == nil {
            keywordRank[result.noteID] = keywordRank.count
        }
        var semanticRank: [UUID: Int] = [:]
        var bestHit: [UUID: SemanticSearchHit] = [:]
        for hit in semantic where semanticRank[hit.noteID] == nil {
            semanticRank[hit.noteID] = semanticRank.count
            bestHit[hit.noteID] = hit
        }

        var fusedScores: [UUID: Double] = [:]
        for (noteID, rank) in keywordRank {
            fusedScores[noteID, default: 0] += 1.0 / (k + Double(rank + 1))
        }
        for (noteID, rank) in semanticRank {
            fusedScores[noteID, default: 0] += 1.0 / (k + Double(rank + 1))
        }

        let orderedNoteIDs = fusedScores
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                // Deterministic tie-break: keyword rank, then semantic rank.
                let lhsKeyword = keywordRank[lhs.key] ?? Int.max
                let rhsKeyword = keywordRank[rhs.key] ?? Int.max
                if lhsKeyword != rhsKeyword { return lhsKeyword < rhsKeyword }
                return (semanticRank[lhs.key] ?? Int.max) < (semanticRank[rhs.key] ?? Int.max)
            }
            .map(\.key)

        var keywordResultsByNote: [UUID: [SearchResult]] = [:]
        for result in keyword {
            keywordResultsByNote[result.noteID, default: []].append(result)
        }

        var fused: [SearchResult] = []
        for noteID in orderedNoteIDs {
            guard fused.count < limit else { break }
            let fusedScore = fusedScores[noteID] ?? 0

            if let kwResults = keywordResultsByNote[noteID] {
                // Cap rows per note: a note with many matching sections must
                // not starve lower-ranked notes out of the fused list
                // (bug 019 — one note consumed 4 of the top 8 slots).
                for result in kwResults.prefix(maxResultsPerNote) {
                    guard fused.count < limit else { break }
                    fused.append(result.withScore(fusedScore))
                }
            } else if let hit = bestHit[noteID] {
                fused.append(syntheticResult(for: hit, vaultURL: vaultURL, score: fusedScore))
            }
        }
        return fused
    }

    /// A display result for a note that only the semantic leg found.
    private static func syntheticResult(
        for hit: SemanticSearchHit,
        vaultURL: URL,
        score: Double
    ) -> SearchResult {
        let fileURL = vaultURL.appendingPathComponent(hit.relativePath)
        if hit.kind == .image {
            return SearchResult(
                id: hit.chunkID,
                kind: .section,
                noteID: hit.noteID,
                fileURL: fileURL,
                title: hit.noteTitle,
                breadcrumb: "\(hit.relativePath)/image: \(hit.heading)",
                snippet: hit.snippet.isEmpty ? hit.heading : hit.snippet,
                lineStart: hit.lineStart,
                score: score,
                updatedAt: nil
            )
        }
        let isWholeNote = hit.heading == hit.noteTitle
        let folderPath = (hit.relativePath as NSString).deletingLastPathComponent
        let breadcrumb = isWholeNote
            ? (folderPath == "." ? "" : folderPath)
            : "\(hit.relativePath)/\(hit.heading)"
        return SearchResult(
            id: hit.chunkID,
            kind: isWholeNote ? .note : .section,
            noteID: hit.noteID,
            fileURL: fileURL,
            title: hit.noteTitle,
            breadcrumb: breadcrumb,
            snippet: hit.snippet.isEmpty ? hit.noteTitle : hit.snippet,
            lineStart: isWholeNote ? nil : hit.lineStart,
            score: score,
            updatedAt: nil
        )
    }
}

private extension SearchResult {
    func withScore(_ newScore: Double) -> SearchResult {
        SearchResult(
            id: id,
            kind: kind,
            noteID: noteID,
            fileURL: fileURL,
            title: title,
            breadcrumb: breadcrumb,
            snippet: snippet,
            lineStart: lineStart,
            score: newScore,
            updatedAt: updatedAt
        )
    }
}
