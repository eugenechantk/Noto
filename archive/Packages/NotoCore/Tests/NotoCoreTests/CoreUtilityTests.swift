import Foundation
import SwiftData
import Testing
import NotoCore
import NotoModels

struct CoreUtilityTests {
    @Test
    func plainTextExtractorStripsFormatting() {
        let result = PlainTextExtractor.plainText(from: "**bold** and *italic* and `code`")
        #expect(result == "bold and italic and code")
    }

    @Test @MainActor
    func breadcrumbBuilderBuildsRootChain() throws {
        let root = Block(content: "Root", sortOrder: 1.0)
        let parent = Block(content: "Projects", parent: root, sortOrder: 1.0)
        let child = Block(content: "Roadmap", parent: parent, sortOrder: 1.0)

        let breadcrumb = BreadcrumbBuilder.build(for: child)
        #expect(breadcrumb == "Home / Projects")
    }

    @Test @MainActor
    func blockBuilderCreatesPath() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1.0)
        context.insert(root)

        let steps = [
            BuildStep(content: "A", sortOrder: 1.0),
            BuildStep(content: "B", sortOrder: 1.0),
        ]

        let deepest = BlockBuilder.buildPath(root: root, path: steps, context: context)
        #expect(deepest.content == "B")
        #expect(deepest.depth == 2)
    }
}
