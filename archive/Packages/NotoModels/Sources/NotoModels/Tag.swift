//
//  Tag.swift
//  NotoModels
//
//  Tag and BlockTag models for categorization.
//

import Foundation
import SwiftData

@Model
public final class Tag {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var color: String?
    public var createdAt: Date

    @Relationship(deleteRule: .cascade)
    public var blockTags: [BlockTag] = []

    public init(
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
public final class BlockTag {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date

    // Relationships
    public var block: Block?
    public var tag: Tag?

    public init(
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
