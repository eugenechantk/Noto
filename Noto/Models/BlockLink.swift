//
//  BlockLink.swift
//  PersonalNotetaking
//
//  Tracks bidirectional references between blocks.
//

import Foundation
import SwiftData

@Model
final class BlockLink {
    @Attribute(.unique) var id: UUID
    var mentionText: String?
    var rangeStart: Int
    var rangeEnd: Int
    var createdAt: Date

    // Relationships
    var sourceBlock: Block?
    var targetBlock: Block?

    init(
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
