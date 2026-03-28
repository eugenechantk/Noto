//
//  BlockEmbedding.swift
//  NotoModels
//
//  Stores vector embeddings for semantic search.
//

import Foundation
import SwiftData

@Model
public final class BlockEmbedding {
    @Attribute(.unique) public var id: UUID
    public var embedding: [Float]
    public var modelVersion: String
    public var generatedAt: Date
    public var contentHash: String

    // Relationships
    public var block: Block?

    public init(
        id: UUID = UUID(),
        block: Block,
        embedding: [Float],
        modelVersion: String,
        contentHash: String
    ) {
        self.id = id
        self.block = block
        self.embedding = embedding
        self.modelVersion = modelVersion
        self.generatedAt = Date()
        self.contentHash = contentHash
    }
}
