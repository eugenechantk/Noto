import Foundation
import SwiftData
import Testing
import NotoModels

struct BlockModelTests {
    @Test @MainActor
    func createAndUpdateBlock() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "hello", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        #expect(block.depth == 0)
        #expect(block.parent == nil)

        let oldUpdatedAt = block.updatedAt
        block.updateContent("hello world")
        try context.save()

        #expect(block.content == "hello world")
        #expect(block.updatedAt >= oldUpdatedAt)
    }

    @Test @MainActor
    func indentAndOutdent() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let a = Block(content: "A", sortOrder: 1.0)
        let b = Block(content: "B", sortOrder: 2.0)
        context.insert(a)
        context.insert(b)
        try context.save()

        #expect(b.indent(siblings: [a, b]))
        #expect(b.parent?.id == a.id)
        #expect(b.depth == 1)

        #expect(b.outdent())
        #expect(b.parent == nil)
        #expect(b.depth == 0)
    }

    @Test
    func sortOrderHelpers() {
        #expect(Block.sortOrderBetween(nil, nil) == 1.0)
        #expect(Block.sortOrderBetween(1.0, nil) == 2.0)
        #expect(Block.sortOrderBetween(nil, 2.0) == 1.0)
        #expect(Block.sortOrderBetween(1.0, 3.0) == 2.0)
    }
}
