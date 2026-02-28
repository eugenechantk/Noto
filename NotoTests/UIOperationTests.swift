//
//  UIOperationTests.swift
//  NotoTests
//
//  Tests for v1 UI operations: create, delete, edit, reorder,
//  indent/outdent, and node view flattening.
//

import Testing
import Foundation
import SwiftData
@testable import Noto

// MARK: - Block Creation Tests

struct BlockCreationTests {

    @Test @MainActor
    func testCreateFirstRootBlock() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        // Simulate creating the first block on an empty home screen
        let block = Block(content: "", sortOrder: Block.sortOrderForAppending(to: []))
        context.insert(block)
        try context.save()

        let descriptor = FetchDescriptor<Block>()
        let blocks = try context.fetch(descriptor)

        #expect(blocks.count == 1)
        #expect(blocks.first?.parent == nil)
        #expect(blocks.first?.depth == 0)
        #expect(blocks.first?.content == "")
        #expect(blocks.first?.sortOrder == 1.0)
    }

    @Test @MainActor
    func testCreateBlockAfterExisting() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block1 = Block(content: "First", sortOrder: 1.0)
        context.insert(block1)
        try context.save()

        // Simulate Return key: create sibling after block1 (last block)
        let newSortOrder = Block.sortOrderBetween(block1.sortOrder, nil)
        let block2 = Block(content: "", sortOrder: newSortOrder)
        context.insert(block2)
        try context.save()

        #expect(block2.sortOrder == 2.0)
        #expect(block2.parent == nil)
        #expect(block2.depth == 0)

        let descriptor = FetchDescriptor<Block>(sortBy: [SortDescriptor(\Block.sortOrder)])
        let blocks = try context.fetch(descriptor)
        #expect(blocks.count == 2)
        #expect(blocks[0].content == "First")
        #expect(blocks[1].content == "")
    }

    @Test @MainActor
    func testCreateBlockBetweenSiblings() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block1 = Block(content: "First", sortOrder: 1.0)
        let block2 = Block(content: "Third", sortOrder: 3.0)
        context.insert(block1)
        context.insert(block2)
        try context.save()

        // Insert between block1 and block2
        let midOrder = Block.sortOrderBetween(block1.sortOrder, block2.sortOrder)
        let blockMid = Block(content: "Second", sortOrder: midOrder)
        context.insert(blockMid)
        try context.save()

        #expect(midOrder == 2.0)

        let descriptor = FetchDescriptor<Block>(sortBy: [SortDescriptor(\Block.sortOrder)])
        let blocks = try context.fetch(descriptor)
        #expect(blocks[0].content == "First")
        #expect(blocks[1].content == "Second")
        #expect(blocks[2].content == "Third")
    }

    @Test @MainActor
    func testCreateChildInNodeView() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let parentNode = Block(content: "Parent Node", sortOrder: 1.0)
        context.insert(parentNode)
        try context.save()

        // Simulate creating a child in node view
        let childSortOrder = Block.sortOrderForAppending(to: parentNode.sortedChildren)
        let child = Block(content: "", parent: parentNode, sortOrder: childSortOrder)
        context.insert(child)
        try context.save()

        #expect(child.parent?.id == parentNode.id)
        #expect(child.depth == parentNode.depth + 1)
        #expect(child.depth == 1)
        #expect(child.sortOrder == 1.0)
        #expect(parentNode.children.count == 1)
    }
}

// MARK: - Block Deletion Tests

struct BlockDeletionTests {

    @Test @MainActor
    func testDeleteEmptyBlock() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block1 = Block(content: "Keep", sortOrder: 1.0)
        let block2 = Block(content: "", sortOrder: 2.0)
        context.insert(block1)
        context.insert(block2)
        try context.save()

        // Simulate backspace on empty block: only delete if empty
        #expect(block2.content.isEmpty)
        context.delete(block2)
        try context.save()

        let descriptor = FetchDescriptor<Block>()
        let blocks = try context.fetch(descriptor)
        #expect(blocks.count == 1)
        #expect(blocks.first?.content == "Keep")
    }

    @Test @MainActor
    func testDeleteBlockCascadesToChildren() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let parent = Block(content: "", sortOrder: 1.0)
        context.insert(parent)

        let child = Block(content: "Child", parent: parent, sortOrder: 1.0)
        let grandchild = Block(content: "Grandchild", parent: child, sortOrder: 1.0)
        context.insert(child)
        context.insert(grandchild)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Block>()).count == 3)

        // Delete parent — cascade should remove child and grandchild
        context.delete(parent)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Block>()).count == 0)
    }

    @Test @MainActor
    func testDeleteNonEmptyBlockIgnored() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "Has content", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        // Simulate the guard: don't delete if content is non-empty
        let shouldDelete = block.content.isEmpty
        #expect(shouldDelete == false)

        let descriptor = FetchDescriptor<Block>()
        let blocks = try context.fetch(descriptor)
        #expect(blocks.count == 1)
    }
}

// MARK: - Block Editing Tests

struct BlockEditingTests {

    @Test @MainActor
    func testEditBlockContent() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "Original", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        block.content = "Updated"
        try context.save()

        #expect(block.content == "Updated")
    }

    @Test @MainActor
    func testEditBlockUpdatesTimestamp() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "Original", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let originalTimestamp = block.updatedAt

        try await Task.sleep(nanoseconds: 10_000_000)

        block.updateContent("Edited")
        try context.save()

        #expect(block.content == "Edited")
        #expect(block.updatedAt > originalTimestamp)
    }
}

// MARK: - Reorder Tests

struct ReorderTests {

    @Test @MainActor
    func testReorderMovesBlockDown() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let a = Block(content: "A", sortOrder: 1.0)
        let b = Block(content: "B", sortOrder: 2.0)
        let c = Block(content: "C", sortOrder: 3.0)
        context.insert(a)
        context.insert(b)
        context.insert(c)
        try context.save()

        // Simulate onMove: move A (index 0) to after C (destination index 3)
        var blocks = [a, b, c]
        blocks.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        for (index, block) in blocks.enumerated() {
            block.sortOrder = Double(index) + 1.0
        }
        try context.save()

        let sorted = blocks.sorted { $0.sortOrder < $1.sortOrder }
        #expect(sorted[0].content == "B")
        #expect(sorted[1].content == "C")
        #expect(sorted[2].content == "A")
    }

    @Test @MainActor
    func testReorderMovesBlockUp() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let a = Block(content: "A", sortOrder: 1.0)
        let b = Block(content: "B", sortOrder: 2.0)
        let c = Block(content: "C", sortOrder: 3.0)
        context.insert(a)
        context.insert(b)
        context.insert(c)
        try context.save()

        // Simulate onMove: move C (index 2) to before A (destination index 0)
        var blocks = [a, b, c]
        blocks.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        for (index, block) in blocks.enumerated() {
            block.sortOrder = Double(index) + 1.0
        }
        try context.save()

        let sorted = blocks.sorted { $0.sortOrder < $1.sortOrder }
        #expect(sorted[0].content == "C")
        #expect(sorted[1].content == "A")
        #expect(sorted[2].content == "B")
    }

    @Test @MainActor
    func testReorderPreservesContent() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let a = Block(content: "Alpha", sortOrder: 1.0)
        let b = Block(content: "Beta", sortOrder: 2.0)
        let c = Block(content: "Gamma", sortOrder: 3.0)
        context.insert(a)
        context.insert(b)
        context.insert(c)
        try context.save()

        // Reorder: move B to the end
        var blocks = [a, b, c]
        blocks.move(fromOffsets: IndexSet(integer: 1), toOffset: 3)
        for (index, block) in blocks.enumerated() {
            block.sortOrder = Double(index) + 1.0
        }
        try context.save()

        // Content unchanged
        #expect(a.content == "Alpha")
        #expect(b.content == "Beta")
        #expect(c.content == "Gamma")
    }
}

// MARK: - Reorganize (Indent / Outdent) Tests

struct ReorganizeTests {

    @Test @MainActor
    func testIndentMakesChildOfPreviousSibling() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let a = Block(content: "A", sortOrder: 1.0)
        let b = Block(content: "B", sortOrder: 2.0)
        context.insert(a)
        context.insert(b)
        try context.save()

        let result = b.indent(siblings: [a, b])

        #expect(result == true)
        #expect(b.parent?.id == a.id)
        #expect(b.depth == 1)
    }

    @Test @MainActor
    func testIndentFirstSiblingFails() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let a = Block(content: "A", sortOrder: 1.0)
        let b = Block(content: "B", sortOrder: 2.0)
        context.insert(a)
        context.insert(b)
        try context.save()

        // A is the first sibling, no previous sibling to indent under
        let result = a.indent(siblings: [a, b])

        #expect(result == false)
        #expect(a.parent == nil)
        #expect(a.depth == 0)
    }

    @Test @MainActor
    func testOutdentMakesSiblingOfParent() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let parent = Block(content: "Parent", sortOrder: 1.0)
        context.insert(parent)

        let child = Block(content: "Child", parent: parent, sortOrder: 1.0)
        context.insert(child)
        try context.save()

        #expect(child.depth == 1)
        #expect(child.parent?.id == parent.id)

        let result = child.outdent()

        #expect(result == true)
        #expect(child.parent == nil)
        #expect(child.depth == 0)
    }

    @Test @MainActor
    func testOutdentRootBlockFails() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)
        try context.save()

        let result = root.outdent()

        #expect(result == false)
        #expect(root.parent == nil)
        #expect(root.depth == 0)
    }

    @Test @MainActor
    func testIndentUpdatesDescendantDepths() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let a = Block(content: "A", sortOrder: 1.0)
        let b = Block(content: "B", sortOrder: 2.0)
        context.insert(a)
        context.insert(b)

        let bChild = Block(content: "B-child", parent: b, sortOrder: 1.0)
        let bGrandchild = Block(content: "B-grandchild", parent: bChild, sortOrder: 1.0)
        context.insert(bChild)
        context.insert(bGrandchild)
        try context.save()

        #expect(b.depth == 0)
        #expect(bChild.depth == 1)
        #expect(bGrandchild.depth == 2)

        // Indent B under A
        let result = b.indent(siblings: [a, b])

        #expect(result == true)
        #expect(b.depth == 1)
        #expect(bChild.depth == 2)
        #expect(bGrandchild.depth == 3)
    }
}

// MARK: - Node View Flattening Tests

struct NodeViewFlatteningTests {

    @Test @MainActor
    func testFlattenCollapsedShowsChildrenAndGrandchildren() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        // Build: node → child → grandchild → great-grandchild
        let node = Block(content: "Node", sortOrder: 1.0)
        context.insert(node)

        let child = Block(content: "Child", parent: node, sortOrder: 1.0)
        context.insert(child)

        let grandchild = Block(content: "Grandchild", parent: child, sortOrder: 1.0)
        context.insert(grandchild)

        let greatGrandchild = Block(content: "Great-grandchild", parent: grandchild, sortOrder: 1.0)
        context.insert(greatGrandchild)
        try context.save()

        let flat = node.flattenedDescendants(expanded: false)

        // Collapsed: child + grandchild visible, great-grandchild hidden
        #expect(flat.count == 2)
        #expect(flat[0].block.content == "Child")
        #expect(flat[1].block.content == "Grandchild")
    }

    @Test @MainActor
    func testFlattenExpandedShowsAllDescendants() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let node = Block(content: "Node", sortOrder: 1.0)
        context.insert(node)

        let child = Block(content: "Child", parent: node, sortOrder: 1.0)
        context.insert(child)

        let grandchild = Block(content: "Grandchild", parent: child, sortOrder: 1.0)
        context.insert(grandchild)

        let greatGrandchild = Block(content: "Great-grandchild", parent: grandchild, sortOrder: 1.0)
        context.insert(greatGrandchild)
        try context.save()

        let flat = node.flattenedDescendants(expanded: true)

        // Expanded: all 3 descendants visible
        #expect(flat.count == 3)
        #expect(flat[0].block.content == "Child")
        #expect(flat[1].block.content == "Grandchild")
        #expect(flat[2].block.content == "Great-grandchild")
    }

    @Test @MainActor
    func testFlattenIndentLevelFormula() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let node = Block(content: "Node", sortOrder: 1.0)
        context.insert(node)

        let child = Block(content: "Child", parent: node, sortOrder: 1.0)
        context.insert(child)

        let grandchild = Block(content: "Grandchild", parent: child, sortOrder: 1.0)
        context.insert(grandchild)

        let greatGrandchild = Block(content: "Great-grandchild", parent: grandchild, sortOrder: 1.0)
        context.insert(greatGrandchild)
        try context.save()

        let flat = node.flattenedDescendants(expanded: true)

        // indent = block.depth - node.depth - 1
        // child:            depth 1 - 0 - 1 = 0
        // grandchild:       depth 2 - 0 - 1 = 1
        // great-grandchild: depth 3 - 0 - 1 = 2
        #expect(flat[0].indentLevel == 0)
        #expect(flat[1].indentLevel == 1)
        #expect(flat[2].indentLevel == 2)
    }

    @Test @MainActor
    func testFlattenDirectChildrenHaveIndentZero() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let node = Block(content: "Node", sortOrder: 1.0)
        context.insert(node)

        let child1 = Block(content: "Child 1", parent: node, sortOrder: 1.0)
        let child2 = Block(content: "Child 2", parent: node, sortOrder: 2.0)
        let child3 = Block(content: "Child 3", parent: node, sortOrder: 3.0)
        context.insert(child1)
        context.insert(child2)
        context.insert(child3)
        try context.save()

        let flat = node.flattenedDescendants(expanded: false)

        #expect(flat.count == 3)
        for entry in flat {
            #expect(entry.indentLevel == 0)
        }
    }

    @Test @MainActor
    func testFlattenPreservesSortOrder() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let node = Block(content: "Node", sortOrder: 1.0)
        context.insert(node)

        // Insert out of order
        let childC = Block(content: "C", parent: node, sortOrder: 3.0)
        let childA = Block(content: "A", parent: node, sortOrder: 1.0)
        let childB = Block(content: "B", parent: node, sortOrder: 2.0)
        context.insert(childC)
        context.insert(childA)
        context.insert(childB)
        try context.save()

        let flat = node.flattenedDescendants(expanded: false)

        #expect(flat.count == 3)
        #expect(flat[0].block.content == "A")
        #expect(flat[1].block.content == "B")
        #expect(flat[2].block.content == "C")
    }
}
