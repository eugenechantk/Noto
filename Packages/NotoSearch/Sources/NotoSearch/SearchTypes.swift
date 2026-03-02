//
//  SearchTypes.swift
//  NotoSearch
//
//  Shared types for the hybrid search pipeline.
//

import Foundation

public struct DateRange {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

public struct SearchQuery {
    public let text: String
    public let dateRange: DateRange?

    public init(text: String, dateRange: DateRange?) {
        self.text = text
        self.dateRange = dateRange
    }
}

public struct SearchResult: Identifiable {
    public let id: UUID
    public let content: String
    public let breadcrumb: String
    public let hybridScore: Double

    public init(id: UUID, content: String, breadcrumb: String, hybridScore: Double) {
        self.id = id
        self.content = content
        self.breadcrumb = breadcrumb
        self.hybridScore = hybridScore
    }
}

public struct KeywordSearchResult {
    public let blockId: UUID
    public let bm25Score: Double

    public init(blockId: UUID, bm25Score: Double) {
        self.blockId = blockId
        self.bm25Score = bm25Score
    }
}

public struct SemanticSearchResult {
    public let blockId: UUID
    public let similarity: Float

    public init(blockId: UUID, similarity: Float) {
        self.blockId = blockId
        self.similarity = similarity
    }
}

public struct RankedResult {
    public let blockId: UUID
    public let hybridScore: Double

    public init(blockId: UUID, hybridScore: Double) {
        self.blockId = blockId
        self.hybridScore = hybridScore
    }
}
