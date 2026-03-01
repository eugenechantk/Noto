//
//  Block.swift
//  Noto
//
//  Core entity for outline-based note-taking.
//

import Foundation
import SwiftData

@Model
final class Block: Hashable {
    static func == (lhs: Block, rhs: Block) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    @Attribute(.unique) var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Double
    var depth: Int
    var isArchived: Bool
    var extensionData: Data?

    // Relationships
    var parent: Block?

    @Relationship(deleteRule: .cascade, inverse: \Block.parent)
    var children: [Block] = []

    @Relationship(deleteRule: .cascade, inverse: \BlockLink.sourceBlock)
    var outgoingLinks: [BlockLink] = []

    @Relationship(deleteRule: .cascade)
    var tags: [BlockTag] = []

    @Relationship(deleteRule: .cascade)
    var embedding: BlockEmbedding?

    @Relationship(deleteRule: .cascade)
    var metadataFields: [MetadataField] = []

    init(
        id: UUID = UUID(),
        content: String = "",
        parent: Block? = nil,
        sortOrder: Double = 0.0,
        isArchived: Bool = false,
        extensionData: Data? = nil
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
    }

    // MARK: - Computed Properties

    /// Returns children sorted by sortOrder
    var sortedChildren: [Block] {
        children.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Returns all descendants recursively
    var allDescendants: [Block] {
        var result: [Block] = []
        for child in children {
            result.append(child)
            result.append(contentsOf: child.allDescendants)
        }
        return result
    }

    // MARK: - Block Movement Operations

    /// Move this block to a new parent with a specific sort order
    func move(to newParent: Block?, sortOrder newSortOrder: Double) {
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
    func isDescendant(of ancestor: Block) -> Bool {
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
    func previousSibling(in siblings: [Block]) -> Block? {
        let sorted = siblings.sorted { $0.sortOrder < $1.sortOrder }
        guard let index = sorted.firstIndex(where: { $0.id == self.id }),
              index > 0 else {
            return nil
        }
        return sorted[index - 1]
    }

    /// Indent this block (make it a child of the previous sibling)
    func indent(siblings: [Block]) -> Bool {
        guard let prevSibling = previousSibling(in: siblings) else {
            return false
        }

        // Calculate new sort order (append to end of previous sibling's children)
        let newSortOrder = (prevSibling.sortedChildren.last?.sortOrder ?? 0) + 1.0
        move(to: prevSibling, sortOrder: newSortOrder)
        return true
    }

    /// Outdent this block (make it a sibling of its parent)
    func outdent() -> Bool {
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
    func updateContent(_ newContent: String) {
        self.content = newContent
        self.updatedAt = Date()
    }

    // MARK: - Sort Order Helpers

    /// Calculate sort order for inserting between two blocks
    static func sortOrderBetween(_ before: Double?, _ after: Double?) -> Double {
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
    static func sortOrderForAppending(to siblings: [Block]) -> Double {
        guard let lastSortOrder = siblings.map({ $0.sortOrder }).max() else {
            return 1.0
        }
        return lastSortOrder + 1.0
    }

    // MARK: - Node View Flattening

    /// Entry in a flattened block tree for display in NodeView.
    struct FlatEntry {
        let block: Block
        let indentLevel: Int
    }

    /// Flatten this block's descendants for display in NodeView.
    /// - Parameter expanded: If true, include ALL descendants. If false, include only children and grandchildren.
    /// - Returns: Array of `FlatEntry` with correct indent levels.
    func flattenedDescendants(expanded: Bool) -> [FlatEntry] {
        var result: [FlatEntry] = []
        for child in sortedChildren {
            result.append(FlatEntry(block: child, indentLevel: 0))
            if expanded {
                appendAllDescendants(of: child, rootDepth: self.depth, to: &result)
            } else {
                for grandchild in child.sortedChildren {
                    let indent = grandchild.depth - self.depth - 1
                    result.append(FlatEntry(block: grandchild, indentLevel: indent))
                }
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
