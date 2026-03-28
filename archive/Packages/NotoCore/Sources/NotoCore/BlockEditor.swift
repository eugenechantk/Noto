//
//  BlockEditor.swift
//  NotoCore
//
//  Middle layer (ViewModel / Use Case) that manages block mutations
//  for the outline editor. Translates line-level editing operations
//  into Block model changes persisted via SwiftData.
//
//  Each editor instance represents a "zoomed in" view of a specific
//  block. It shows the block's content (line 0) plus its descendants.
//

import Foundation
import SwiftData
import os.log
import NotoModels

private let logger = Logger(subsystem: "com.noto", category: "BlockEditor")

/// A flattened entry for display: a Block and its indent level relative to the root.
public struct BlockEntry {
    public let block: Block
    public let indentLevel: Int
}

@MainActor
public class BlockEditor {

    // MARK: - Properties

    public let root: Block
    public let modelContext: ModelContext
    /// Retain the container to prevent SwiftData from resetting the backing store.
    private var retainedContainer: ModelContainer?
    public var expanded: Bool

    /// Flattened list of blocks for display. Line 0 is always the root.
    public private(set) var entries: [BlockEntry] = []

    // MARK: - Init

    public init(root: Block, modelContext: ModelContext, expanded: Bool = false, retainContainer: ModelContainer? = nil) {
        self.root = root
        self.modelContext = modelContext
        self.expanded = expanded
        self.retainedContainer = retainContainer
        reload()
    }

    // MARK: - Reload

    /// Rebuild the flattened entries list from the block tree.
    public func reload() {
        var result: [BlockEntry] = []

        // Line 0: the root itself
        result.append(BlockEntry(block: root, indentLevel: 0))

        // Children (and descendants if expanded)
        if expanded {
            let descendants = root.flattenedDescendants(expanded: true)
            for entry in descendants {
                result.append(BlockEntry(block: entry.block, indentLevel: entry.indentLevel))
            }
        } else {
            for child in root.sortedChildren where !child.isArchived {
                result.append(BlockEntry(block: child, indentLevel: 0))
            }
        }

        entries = result
    }

    // MARK: - Line ↔ Block Mapping

    public func block(atLine index: Int) -> Block? {
        guard index >= 0, index < entries.count else { return nil }
        return entries[index].block
    }

    // MARK: - Update Content

    public func updateContent(atLine index: Int, newContent: String) {
        guard let block = block(atLine: index) else { return }
        block.content = newContent
        block.updatedAt = Date()
    }

    // MARK: - Insert Line

    /// Insert a new empty block after the given line. Returns the new block.
    @discardableResult
    public func insertLine(afterLine index: Int) -> Block {
        let referenceBlock = block(atLine: index) ?? root

        let newBlock: Block

        if index == 0 {
            // Insert after title → create child of root at the top
            let firstChildSort = entries.count > 1 ? entries[1].block.sortOrder : 1.0
            newBlock = Block(content: "", parent: root, sortOrder: firstChildSort - 1.0)
            newBlock.depth = root.depth + 1
        } else {
            // Insert after a child/descendant → create sibling of that block
            let parent = referenceBlock.parent ?? root
            let refSortOrder = referenceBlock.sortOrder

            // Find next sibling's sort order from entries for fractional indexing
            let nextSiblingSort = findNextSiblingSortOrder(afterLine: index, parent: parent)
            let sortOrder = nextSiblingSort != nil
                ? (refSortOrder + nextSiblingSort!) / 2.0
                : refSortOrder + 1.0

            newBlock = Block(content: "", parent: parent, sortOrder: sortOrder)
            newBlock.depth = referenceBlock.depth
        }

        modelContext.insert(newBlock)
        reload()
        return newBlock
    }

    // MARK: - Delete Line

    public func deleteLine(atLine index: Int) {
        // Cannot delete the root (line 0)
        guard index > 0, index < entries.count else { return }

        let blockToDelete = entries[index].block
        let blockIndent = entries[index].indentLevel

        // Find the range of contiguous descendants (deeper indent after this line)
        var endIndex = index + 1
        while endIndex < entries.count && entries[endIndex].indentLevel > blockIndent {
            endIndex += 1
        }

        // Remove the block and its descendants from entries in one slice
        entries.removeSubrange(index..<endIndex)

        // SwiftData cascade delete handles descendants automatically
        modelContext.delete(blockToDelete)
    }

    // MARK: - Indent Line

    public func indentLine(atLine index: Int) {
        // Cannot indent root (line 0)
        guard index > 0, let block = block(atLine: index) else { return }

        // Find previous sibling by scanning entries backwards
        let parentId = block.parent?.id
        var prevSibling: Block?
        for i in stride(from: index - 1, through: 1, by: -1) {
            if entries[i].block.parent?.id == parentId {
                prevSibling = entries[i].block
                break
            }
        }
        guard let prevSibling else { return } // no previous sibling → no-op

        // Reparent: block becomes first child of previous sibling
        // Scan entries forward from prevSibling to find its first child
        let prevSiblingLine = entries.firstIndex(where: { $0.block.id == prevSibling.id })!
        var firstChildSort = 1.0
        for i in (prevSiblingLine + 1)..<entries.count {
            if entries[i].block.parent?.id == prevSibling.id {
                firstChildSort = entries[i].block.sortOrder
                break
            }
        }
        block.move(to: prevSibling, sortOrder: firstChildSort - 1)

        reload()
    }

    // MARK: - Outdent Line

    public func outdentLine(atLine index: Int) {
        // Cannot outdent root (line 0)
        guard index > 0, let block = block(atLine: index) else { return }

        // Cannot outdent direct children of root (already at top level in this view)
        guard let parent = block.parent, parent.id != root.id else { return }

        // Reparent: block becomes sibling of its current parent
        let grandparent = parent.parent
        let sortOrder = parent.sortOrder + 1

        // Push parent's later siblings forward
        let grandparentChildren = (grandparent?.sortedChildren ?? []).filter { !$0.isArchived }
        for sibling in grandparentChildren where sibling.sortOrder > parent.sortOrder {
            sibling.sortOrder += 1
        }

        block.move(to: grandparent, sortOrder: sortOrder)

        reload()
    }

    // MARK: - Move / Reorder

    public func moveLine(from source: Int, to destination: Int) {
        // Cannot move root (line 0)
        guard source > 0, source < entries.count else { return }
        guard destination > 0, destination <= entries.count else { return }
        guard source != destination, source != destination - 1 else { return }

        let block = entries[source].block

        // Remove from entries, insert at new position
        entries.remove(at: source)
        let insertAt = destination > source ? destination - 1 : destination
        let clampedInsert = max(1, min(insertAt, entries.count))
        entries.insert(BlockEntry(block: block, indentLevel: entries[0].indentLevel), at: clampedInsert)

        // Calculate sortOrder from neighboring siblings in entries
        let parentId = block.parent?.id
        var prevSiblingSort: Double?
        for i in stride(from: clampedInsert - 1, through: 1, by: -1) {
            if entries[i].block.parent?.id == parentId {
                prevSiblingSort = entries[i].block.sortOrder
                break
            }
        }
        var nextSiblingSort: Double?
        for i in (clampedInsert + 1)..<entries.count {
            if entries[i].block.parent?.id == parentId {
                nextSiblingSort = entries[i].block.sortOrder
                break
            }
        }

        if let prev = prevSiblingSort, let next = nextSiblingSort {
            block.sortOrder = (prev + next) / 2.0
        } else if let prev = prevSiblingSort {
            block.sortOrder = prev + 1.0
        } else if let next = nextSiblingSort {
            block.sortOrder = next - 1.0
        } else {
            block.sortOrder = 1.0
        }

        reload()
    }

    // MARK: - Helpers

    /// Scan entries after the given line to find the next block with the same parent.
    private func findNextSiblingSortOrder(afterLine index: Int, parent: Block) -> Double? {
        for i in (index + 1)..<entries.count {
            let candidate = entries[i].block
            if candidate.parent?.id == parent.id {
                return candidate.sortOrder
            }
        }
        return nil
    }
}
