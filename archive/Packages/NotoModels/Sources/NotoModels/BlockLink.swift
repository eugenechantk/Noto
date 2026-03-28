//
//  BlockLink.swift
//  NotoModels
//
//  Tracks bidirectional references between blocks.
//

import Foundation
import SwiftData

@Model
public final class BlockLink {
    @Attribute(.unique) public var id: UUID
    public var mentionText: String?
    public var rangeStart: Int
    public var rangeEnd: Int
    public var createdAt: Date

    // Relationships
    public var sourceBlock: Block?
    public var targetBlock: Block?

    public init(
        id: UUID = UUID(),
        sourceBlock: Block,
        targetBlock: Block,
        mentionText: String? = nil,
        rangeStart: Int = 0,
        rangeEnd: Int = 0
    ) {
        self.id = id
        self.sourceBlock = sourceBlock
        self.targetBlock = targetBlock
        self.mentionText = mentionText
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.createdAt = Date()
    }
}
