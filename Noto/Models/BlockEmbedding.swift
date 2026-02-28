//
//  BlockEmbedding.swift
//  Noto
//
//  Stores vector embeddings for semantic search.
//

import Foundation
import SwiftData

@Model
final class BlockEmbedding {
    @Attribute(.unique) var id: UUID
    var embedding: [Float]
    var modelVersion: String
    var generatedAt: Date
    var contentHash: String

    // Relationships
    var block: Block?

    init(
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
