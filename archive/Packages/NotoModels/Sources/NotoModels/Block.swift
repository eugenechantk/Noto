//
//  Block.swift
//  NotoModels
//
//  Core entity for outline-based note-taking.
//

import Foundation
import SwiftData

@Model
public final class Block: Hashable {
    public static func == (lhs: Block, rhs: Block) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    @Attribute(.unique) public var id: UUID
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var sortOrder: Double
    public var depth: Int
    public var isArchived: Bool
    public var extensionData: Data?

    // Block protection properties — all default to true (unrestricted)
    public var isDeletable: Bool = true
    public var isContentEditableByUser: Bool = true
    public var isReorderable: Bool = true
    public var isMovable: Bool = true

    // Relationships
    public var parent: Block?

    @Relationship(deleteRule: .cascade, inverse: \Block.parent)
    public var children: [Block] = []

    @Relationship(deleteRule: .cascade, inverse: \BlockLink.sourceBlock)
    public var outgoingLinks: [BlockLink] = []

    @Relationship(deleteRule: .cascade)
    public var tags: [BlockTag] = []

    @Relationship(deleteRule: .cascade)
    public var embedding: BlockEmbedding?

    @Relationship(deleteRule: .cascade)
    public var metadataFields: [MetadataField] = []

    public init(
        id: UUID = UUID(),
        content: String = "",
        parent: Block? = nil,
        sortOrder: Double = 0.0,
        isArchived: Bool = false,
        extensionData: Data? = nil,
        isDeletable: Bool = true,
        isContentEditableByUser: Bool = true,
        isReorderable: Bool = true,
        isMovable: Bool = true
    ) {
        self.id = id
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortOrder = sortOrder
        self.depth = parent == nil ? 0 : parent!.depth + 1
        self.isArchived = isArchived
        self.extensionData = extensionData
        self.parent = parent
        self.isDeletable = isDeletable
        self.isContentEditableByUser = isContentEditableByUser
        self.isReorderable = isReorderable
        self.isMovable = isMovable
    }

    // MARK: - Computed Properties

    /// Returns children sorted by sortOrder
    public var sortedChildren: [Block] {
        children.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Returns all descendants recursively
    public var allDescendants: [Block] {
        var result: [Block] = []
        for child in children {
            result.append(child)
            result.append(contentsOf: child.allDescendants)
        }
        return result
    }

    // MARK: - Block Movement Operations

    /// Move this block to a new parent with a specific sort order
    public func move(to newParent: Block?, sortOrder newSortOrder: Double) {
        let oldDepth = depth
        let newDepth = newParent == nil ? 0 : newParent!.depth + 1
        let depthDelta = newDepth - oldDepth

        self.parent = newParent
        self.sortOrder = newSortOrder
        self.depth = newDepth
        self.updatedAt = Date()

        // Update all descendants' depth
        updateDescendantsDepth(by: depthDelta)
    }

    /// Recursively update descendants' depth
    private func updateDescendantsDepth(by delta: Int) {
        for child in children {
            child.depth += delta
            child.updatedAt = Date()
            child.updateDescendantsDepth(by: delta)
        }
    }

    /// Check if this block is a descendant of the given block
    public func isDescendant(of ancestor: Block) -> Bool {
        var current = self.parent
        while let p = current {
            if p.id == ancestor.id {
                return true
            }
            current = p.parent
        }
        return false
    }

    /// Get the previous sibling (for indent operation)
    public func previousSibling(in siblings: [Block]) -> Block? {
        let sorted = siblings.sorted { $0.sortOrder < $1.sortOrder }
        guard let index = sorted.firstIndex(where: { $0.id == self.id }),
              index > 0 else {
            return nil
        }
        return sorted[index - 1]
    }

    /// Indent this block (make it a child of the previous sibling)
    public func indent(siblings: [Block]) -> Bool {
        guard let prevSibling = previousSibling(in: siblings) else {
            return false
        }

        // Calculate new sort order (append to end of previous sibling's children)
        let newSortOrder = (prevSibling.sortedChildren.last?.sortOrder ?? 0) + 1.0
        move(to: prevSibling, sortOrder: newSortOrder)
        return true
    }

    /// Outdent this block (make it a sibling of its parent)
    public func outdent() -> Bool {
        guard let currentParent = parent else {
            return false // Already at root level
        }

        let grandparent = currentParent.parent
        // Place after current parent in grandparent's children
        let newSortOrder = currentParent.sortOrder + 0.001
        move(to: grandparent, sortOrder: newSortOrder)
        return true
    }

    /// Update content and timestamp
    public func updateContent(_ newContent: String) {
        self.content = newContent
        self.updatedAt = Date()
    }

    // MARK: - Sort Order Helpers

    /// Calculate sort order for inserting between two blocks
    public static func sortOrderBetween(_ before: Double?, _ after: Double?) -> Double {
        switch (before, after) {
        case (nil, nil):
            return 1.0
        case (let b?, nil):
            return b + 1.0
        case (nil, let a?):
            return a / 2.0
        case (let b?, let a?):
            return (b + a) / 2.0
        }
    }

    /// Calculate sort order for appending to a list
    public static func sortOrderForAppending(to siblings: [Block]) -> Double {
        guard let lastSortOrder = siblings.map({ $0.sortOrder }).max() else {
            return 1.0
        }
        return lastSortOrder + 1.0
    }

    // MARK: - Node View Flattening

    /// Entry in a flattened block tree for display in NodeView.
    public struct FlatEntry {
        public let block: Block
        public let indentLevel: Int

        public init(block: Block, indentLevel: Int) {
            self.block = block
            self.indentLevel = indentLevel
        }
    }

    /// Flatten this block's descendants for display in NodeView.
    /// - Parameter expanded: If true, include ALL descendants. If false, include only direct children.
    /// - Returns: Array of `FlatEntry` with correct indent levels.
    public func flattenedDescendants(expanded: Bool) -> [FlatEntry] {
        var result: [FlatEntry] = []
        for child in sortedChildren {
            result.append(FlatEntry(block: child, indentLevel: 0))
            if expanded {
                appendAllDescendants(of: child, rootDepth: self.depth, to: &result)
            }
        }
        return result
    }

    private func appendAllDescendants(of parent: Block, rootDepth: Int, to result: inout [FlatEntry]) {
        for child in parent.sortedChildren {
            let indentLevel = child.depth - rootDepth - 1
            result.append(FlatEntry(block: child, indentLevel: indentLevel))
            appendAllDescendants(of: child, rootDepth: rootDepth, to: &result)
        }
    }
}
