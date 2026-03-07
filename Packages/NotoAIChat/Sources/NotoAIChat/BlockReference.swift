//
//  BlockReference.swift
//  NotoAIChat
//

import Foundation

/// A snapshot reference to a source block cited in an AI response.
public struct BlockReference: Codable, Sendable {
    public let blockId: UUID
    public let content: String
    public var relevanceScore: Double?

    public init(blockId: UUID, content: String, relevanceScore: Double? = nil) {
        self.blockId = blockId
        self.content = content
        self.relevanceScore = relevanceScore
    }
}
