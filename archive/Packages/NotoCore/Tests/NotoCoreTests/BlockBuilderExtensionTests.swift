import Foundation
import SwiftData
import Testing
import NotoCore
import NotoModels

struct BlockBuilderExtensionTests {

    @Test @MainActor
    func addBlockBetweenTwoSiblings() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let parent = Block(content: "Parent", sortOrder: 1.0)
        context.insert(parent)
        let childA = Block(content: "A", parent: parent, sortOrder: 1.0)
        context.insert(childA)
        let childB = Block(content: "B", parent: parent, sortOrder: 2.0)
        context.insert(childB)

        let inserted = BlockBuilder.addBlock(
            content: "Between",
            parent: parent,
            afterSibling: childA,
            context: context
        )

        #expect(inserted.sortOrder > childA.sortOrder)
        #expect(inserted.sortOrder < childB.sortOrder)
        #expect(inserted.parent?.id == parent.id)
        #expect(inserted.depth == parent.depth + 1)
    }

    @Test @MainActor
    func addBlockAtEndOfChildren() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let parent = Block(content: "Parent", sortOrder: 1.0)
        context.insert(parent)
        let childA = Block(content: "A", parent: parent, sortOrder: 1.0)
        context.insert(childA)
        let childB = Block(content: "B", parent: parent, sortOrder: 2.0)
        context.insert(childB)

        let appended = BlockBuilder.addBlock(
            content: "End",
            parent: parent,
            context: context
        )

        #expect(appended.sortOrder > childB.sortOrder)
        #expect(appended.parent?.id == parent.id)
    }

    @Test @MainActor
    func addBlockToEmptyParent() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let parent = Block(content: "Empty Parent", sortOrder: 1.0)
        context.insert(parent)

        let child = BlockBuilder.addBlock(
            content: "First Child",
            parent: parent,
            context: context
        )

        #expect(child.content == "First Child")
        #expect(child.sortOrder == 1.0)
        #expect(child.parent?.id == parent.id)
        #expect(child.depth == parent.depth + 1)
    }

    @Test @MainActor
    func updateEditableBlock() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "Original", sortOrder: 1.0, isContentEditableByUser: true)
        context.insert(block)
        let originalUpdatedAt = block.updatedAt

        // Small delay so updatedAt differs
        try BlockBuilder.updateBlock(block, newContent: "Updated")

        #expect(block.content == "Updated")
        #expect(block.updatedAt >= originalUpdatedAt)
    }

    @Test @MainActor
    func updateNonEditableBlockThrows() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "Locked", sortOrder: 1.0, isContentEditableByUser: false)
        context.insert(block)

        #expect(throws: BlockBuilderError.notEditable(block.id)) {
            try BlockBuilder.updateBlock(block, newContent: "Should fail")
        }
        #expect(block.content == "Locked")
    }

    @Test @MainActor
    func archiveDeletableBlock() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "Deletable", sortOrder: 1.0, isDeletable: true)
        context.insert(block)

        #expect(!block.isArchived)
        try BlockBuilder.archiveBlock(block)
        #expect(block.isArchived)
    }

    @Test @MainActor
    func archiveNonDeletableBlockThrows() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "Protected", sortOrder: 1.0, isDeletable: false)
        context.insert(block)

        #expect(throws: BlockBuilderError.notDeletable(block.id)) {
            try BlockBuilder.archiveBlock(block)
        }
        #expect(!block.isArchived)
    }
}
