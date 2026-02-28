//
//  SearchIndex.swift
//  Noto
//
//  Full-text search index for keyword search.
//

import Foundation
import SwiftData

@Model
final class SearchIndex {
    @Attribute(.unique) var id: UUID
    var blockId: UUID
    var searchableText: String
    var tokens: [String]
    var lastIndexedAt: Date

    init(
        id: UUID = UUID(),
        blockId: UUID,
        searchableText: String,
        tokens: [String]
    ) {
        self.id = id
        self.blockId = blockId
        self.searchableText = searchableText
        self.tokens = tokens
        self.lastIndexedAt = Date()
    }

    /// Create a SearchIndex from a Block
    convenience init(block: Block) {
        let text = block.content.lowercased()
        let tokenized = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        self.init(
            blockId: block.id,
            searchableText: text,
            tokens: tokenized
        )
    }

    /// Update the index for a block
    func update(from block: Block) {
        self.searchableText = block.content.lowercased()
        self.tokens = searchableText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        self.lastIndexedAt = Date()
    }
}
