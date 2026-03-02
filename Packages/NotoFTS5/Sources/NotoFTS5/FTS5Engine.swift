//
//  FTS5Engine.swift
//  NotoFTS5
//
//  Query execution for FTS5 keyword search with BM25 ranking
//  and optional date post-filtering via SwiftData.
//

import Foundation
import SwiftData
import NotoModels
import NotoCore
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "FTS5Engine")

public struct FTS5Engine {
    public let fts5Database: FTS5Database

    public init(fts5Database: FTS5Database) {
        self.fts5Database = fts5Database
    }

    /// Searches the FTS5 index and returns results ranked by BM25.
    /// Optionally post-filters by date range using SwiftData.
    public func search(
        query: String,
        dateRange: DateRange?,
        modelContext: ModelContext
    ) async -> [KeywordSearchResult] {
        let sanitized = FTS5Engine.sanitizeQuery(query)
        guard !sanitized.isEmpty else { return [] }

        let rawResults = await fts5Database.search(query: sanitized)
        guard !rawResults.isEmpty else { return [] }

        var results = rawResults.map { KeywordSearchResult(blockId: $0.blockId, bm25Score: $0.bm25Score) }

        if let dateRange = dateRange {
            let matchedIds = results.map { $0.blockId }
            let start = dateRange.start
            let end = dateRange.end

            let descriptor = FetchDescriptor<Block>(
                predicate: #Predicate<Block> { block in
                    matchedIds.contains(block.id) &&
                    block.createdAt >= start &&
                    block.createdAt <= end
                }
            )

            do {
                let filteredBlocks = try modelContext.fetch(descriptor)
                let filteredIds = Set(filteredBlocks.map { $0.id })
                results = results.filter { filteredIds.contains($0.blockId) }
            } catch {
                logger.error("Date post-filter fetch failed: \(error)")
                return []
            }
        }

        // BM25 scores are negative; more negative = better match. Already sorted by FTS5Database.
        return results
    }

    // MARK: - Query Sanitization

    /// Sanitizes user input for safe FTS5 MATCH queries.
    ///
    /// - Strips unbalanced quotes
    /// - Preserves intentional `*` at end of words (prefix search)
    /// - Wraps terms containing FTS5 special chars in double quotes
    public static func sanitizeQuery(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Handle quoted phrases: if balanced, pass through; if unbalanced, strip quotes
        let quoteCount = trimmed.filter { $0 == "\"" }.count
        if quoteCount >= 2 && quoteCount % 2 == 0 {
            // Balanced quotes — pass through as-is (user wants phrase search)
            return trimmed
        }

        // Strip all quotes for unbalanced cases
        let noQuotes = trimmed.replacingOccurrences(of: "\"", with: "")
        guard !noQuotes.isEmpty else { return "" }

        // Split into tokens and process each
        let fts5SpecialChars = CharacterSet(charactersIn: "(){}[]^~:+\\")
        let tokens = noQuotes.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        let sanitized = tokens.map { token -> String in
            // Preserve trailing * for prefix search
            let hasTrailingStar = token.hasSuffix("*")
            var clean = hasTrailingStar ? String(token.dropLast()) : token

            // Check if the token contains FTS5 special chars that need escaping
            if clean.unicodeScalars.contains(where: { fts5SpecialChars.contains($0) }) {
                // Wrap in double quotes to escape special chars
                clean = "\"\(clean)\""
            }

            return hasTrailingStar ? clean + "*" : clean
        }

        return sanitized.joined(separator: " ")
    }
}
