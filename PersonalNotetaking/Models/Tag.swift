//
//  Tag.swift
//  PersonalNotetaking
//
//  Tag and BlockTag models for categorization.
//

import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var color: String?
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var blockTags: [BlockTag] = []

    init(
        id: UUID = UUID(),
        name: String,
        color: String? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = Date()
    }
}

@Model
final class BlockTag {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    // Relationships
    var block: Block?
    var tag: Tag?

    init(
        id: UUID = UUID(),
        block: Block,
        tag: Tag
    ) {
        self.id = id
        self.block = block
        self.tag = tag
        self.createdAt = Date()
    }
}
