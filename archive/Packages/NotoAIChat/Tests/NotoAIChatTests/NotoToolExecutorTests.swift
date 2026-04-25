//
//  NotoToolExecutorTests.swift
//  NotoAIChatTests
//

import Foundation
import SwiftData
import Testing
import NotoModels
import NotoCore
import NotoSearchLegacy
import NotoClaudeAPI
@testable import NotoAIChat

// MARK: - Mock Search Service

final class MockSearchService: SearchServiceProtocol, @unchecked Sendable {
    var results: [SearchResult] = []

    @MainActor
    func search(rawQuery: String) async -> [SearchResult] {
        results
    }
}

// MARK: - Test Container

@MainActor
private func createTestContainer() throws -> ModelContainer {
    let schema = Schema([Block.self, BlockLink.self, BlockEmbedding.self, Tag.self, BlockTag.self, MetadataField.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - Tests

@Suite("NotoToolExecutor Tests")
struct NotoToolExecutorTests {

    // MARK: - search_notes

    @Test("search_notes dispatches to search service and accumulates references")
    @MainActor
    func searchNotesDispatch() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let mockSearch = MockSearchService()
        let blockId = UUID()
        mockSearch.results = [
            SearchResult(id: blockId, content: "I want to focus on self-growth", breadcrumb: "Home / Today", hybridScore: 0.95)
        ]

        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let input = JSONValue.object([
            "query": .string("self-growth"),
            "limit": .number(5),
        ])

        let result = try await executor.execute(toolUseId: "toolu_1", name: "search_notes", input: input)

        #expect(!result.isError)
        #expect(result.toolUseId == "toolu_1")
        #expect(result.content.contains(blockId.uuidString))
        #expect(executor.references.count == 1)
        #expect(executor.references[0].blockId == blockId)
        #expect(executor.references[0].content == "I want to focus on self-growth")
    }

    @Test("search_notes with date_hint appends to query")
    @MainActor
    func searchNotesWithDateHint() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        mockSearch.results = []

        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)
        let input = JSONValue.object([
            "query": .string("reflections"),
            "date_hint": .string("this month"),
        ])

        let result = try await executor.execute(toolUseId: "toolu_2", name: "search_notes", input: input)
        #expect(!result.isError)
    }

    @Test("search_notes limits results to specified limit")
    @MainActor
    func searchNotesLimit() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        mockSearch.results = (0..<10).map { i in
            SearchResult(id: UUID(), content: "note \(i)", breadcrumb: "Home", hybridScore: Double(10 - i) / 10.0)
        }

        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)
        let input = JSONValue.object([
            "query": .string("test"),
            "limit": .number(3),
        ])

        let result = try await executor.execute(toolUseId: "toolu_3", name: "search_notes", input: input)
        #expect(!result.isError)
        // Should only have 3 references
        #expect(executor.references.count == 3)
    }

    // MARK: - get_block_context

    @Test("get_block_context returns block with ancestors")
    @MainActor
    func getBlockContextWithAncestors() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root")
        let parent = Block(content: "Parent", parent: root, sortOrder: 1.0)
        let child = Block(content: "Target block", parent: parent, sortOrder: 1.0)
        context.insert(root)
        context.insert(parent)
        context.insert(child)
        try context.save()

        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let input = JSONValue.object([
            "block_ids": .array([.string(child.id.uuidString)]),
            "levels_up": .number(2),
        ])

        let result = try await executor.execute(toolUseId: "toolu_4", name: "get_block_context", input: input)
        #expect(!result.isError)
        #expect(result.content.contains("Target block"))
        #expect(result.content.contains("Parent"))
        #expect(result.content.contains("ancestors"))
    }

    @Test("get_block_context returns descendants")
    @MainActor
    func getBlockContextWithDescendants() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let parent = Block(content: "Parent block")
        let child1 = Block(content: "Child 1", parent: parent, sortOrder: 1.0)
        let child2 = Block(content: "Child 2", parent: parent, sortOrder: 2.0)
        context.insert(parent)
        context.insert(child1)
        context.insert(child2)
        try context.save()

        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let input = JSONValue.object([
            "block_ids": .array([.string(parent.id.uuidString)]),
            "levels_up": .number(0),
            "levels_down": .number(1),
        ])

        let result = try await executor.execute(toolUseId: "toolu_5", name: "get_block_context", input: input)
        #expect(!result.isError)
        #expect(result.content.contains("Child 1"))
        #expect(result.content.contains("Child 2"))
    }

    @Test("get_block_context returns siblings")
    @MainActor
    func getBlockContextWithSiblings() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let parent = Block(content: "Parent")
        let sib1 = Block(content: "Sibling before", parent: parent, sortOrder: 1.0)
        let target = Block(content: "Target", parent: parent, sortOrder: 2.0)
        let sib2 = Block(content: "Sibling after", parent: parent, sortOrder: 3.0)
        context.insert(parent)
        context.insert(sib1)
        context.insert(target)
        context.insert(sib2)
        try context.save()

        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let input = JSONValue.object([
            "block_ids": .array([.string(target.id.uuidString)]),
            "levels_up": .number(0),
            "include_siblings": .bool(true),
        ])

        let result = try await executor.execute(toolUseId: "toolu_6", name: "get_block_context", input: input)
        #expect(!result.isError)
        #expect(result.content.contains("Sibling before"))
        #expect(result.content.contains("Sibling after"))
    }

    @Test("get_block_context handles missing block")
    @MainActor
    func getBlockContextMissingBlock() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let missingId = UUID()
        let input = JSONValue.object([
            "block_ids": .array([.string(missingId.uuidString)]),
        ])

        let result = try await executor.execute(toolUseId: "toolu_7", name: "get_block_context", input: input)
        #expect(!result.isError)
        #expect(result.content.contains("not found") || result.content.contains("error"))
    }

    // MARK: - suggest_edit

    @Test("suggest_edit captures proposal with add_block operation")
    @MainActor
    func suggestEditAddBlock() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let parentId = UUID()
        let input = JSONValue.object([
            "description": .string("Add a new reflection"),
            "operations": .array([
                .object([
                    "type": .string("add_block"),
                    "parent_id": .string(parentId.uuidString),
                    "content": .string("Today I reflected on growth"),
                ]),
            ]),
        ])

        let result = try await executor.execute(toolUseId: "toolu_8", name: "suggest_edit", input: input)
        #expect(!result.isError)
        #expect(result.content.contains("1 operation"))
        #expect(executor.editProposal != nil)
        #expect(executor.editProposal?.operations.count == 1)
        #expect(executor.editProposal?.summary == "Add a new reflection")

        if case .addBlock(let op) = executor.editProposal?.operations[0] {
            #expect(op.parentId == parentId)
            #expect(op.content == "Today I reflected on growth")
        } else {
            Issue.record("Expected addBlock operation")
        }
    }

    @Test("suggest_edit captures proposal with update_block operation")
    @MainActor
    func suggestEditUpdateBlock() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let blockId = UUID()
        let input = JSONValue.object([
            "description": .string("Rewrite this bullet"),
            "operations": .array([
                .object([
                    "type": .string("update_block"),
                    "block_id": .string(blockId.uuidString),
                    "new_content": .string("Updated content"),
                ]),
            ]),
        ])

        let result = try await executor.execute(toolUseId: "toolu_9", name: "suggest_edit", input: input)
        #expect(!result.isError)
        #expect(executor.editProposal != nil)

        if case .updateBlock(let op) = executor.editProposal?.operations[0] {
            #expect(op.blockId == blockId)
            #expect(op.newContent == "Updated content")
        } else {
            Issue.record("Expected updateBlock operation")
        }
    }

    // MARK: - Unknown tool

    @Test("Unknown tool returns error result")
    @MainActor
    func unknownTool() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let result = try await executor.execute(
            toolUseId: "toolu_10",
            name: "nonexistent_tool",
            input: .object([:])
        )
        #expect(result.isError)
        #expect(result.content.contains("Unknown tool"))
    }

    // MARK: - search_notes edge cases

    @Test("search_notes returns empty results gracefully")
    @MainActor
    func searchNotesEmptyResults() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        mockSearch.results = []

        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)
        let input = JSONValue.object(["query": .string("nonexistent")])

        let result = try await executor.execute(toolUseId: "toolu_empty", name: "search_notes", input: input)
        #expect(!result.isError)
        #expect(result.content == "[]")
        #expect(executor.references.isEmpty)
    }

    @Test("search_notes truncates long content to ~200 chars")
    @MainActor
    func searchNotesTruncatesContent() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        let longContent = String(repeating: "a", count: 500)
        mockSearch.results = [
            SearchResult(id: UUID(), content: longContent, breadcrumb: "Home", hybridScore: 0.9)
        ]

        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)
        let input = JSONValue.object(["query": .string("test")])

        let result = try await executor.execute(toolUseId: "toolu_trunc", name: "search_notes", input: input)
        #expect(!result.isError)
        // The JSON should not contain the full 500-char string
        #expect(!result.content.contains(longContent))
        // But should contain the truncated version
        #expect(result.content.contains(String(repeating: "a", count: 200)))
    }

    @Test("search_notes includes relevance_score in output")
    @MainActor
    func searchNotesIncludesRelevanceScore() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        mockSearch.results = [
            SearchResult(id: UUID(), content: "test note", breadcrumb: "Home", hybridScore: 0.85)
        ]

        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)
        let input = JSONValue.object(["query": .string("test")])

        let result = try await executor.execute(toolUseId: "toolu_score", name: "search_notes", input: input)
        #expect(!result.isError)
        #expect(result.content.contains("relevance_score"))
        // Floating point: 0.85 may serialize as 0.84999... or 0.85
        #expect(result.content.contains("0.8"))
    }

    @Test("search_notes caps limit at 20")
    @MainActor
    func searchNotesMaxLimit() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        mockSearch.results = (0..<30).map { i in
            SearchResult(id: UUID(), content: "note \(i)", breadcrumb: "Home", hybridScore: 0.5)
        }

        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)
        let input = JSONValue.object([
            "query": .string("test"),
            "limit": .number(100),
        ])

        _ = try await executor.execute(toolUseId: "toolu_cap", name: "search_notes", input: input)
        #expect(executor.references.count == 20)
    }

    // MARK: - get_block_context edge cases

    @Test("get_block_context with deeply nested block returns correct ancestor chain")
    @MainActor
    func getBlockContextDeeplyNested() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root")
        let level1 = Block(content: "Level 1", parent: root, sortOrder: 1.0)
        let level2 = Block(content: "Level 2", parent: level1, sortOrder: 1.0)
        let level3 = Block(content: "Level 3", parent: level2, sortOrder: 1.0)
        let level4 = Block(content: "Level 4 target", parent: level3, sortOrder: 1.0)
        context.insert(root)
        context.insert(level1)
        context.insert(level2)
        context.insert(level3)
        context.insert(level4)
        try context.save()

        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let input = JSONValue.object([
            "block_ids": .array([.string(level4.id.uuidString)]),
            "levels_up": .number(3),
        ])

        let result = try await executor.execute(toolUseId: "toolu_deep", name: "get_block_context", input: input)
        #expect(!result.isError)
        #expect(result.content.contains("Level 4 target"))
        #expect(result.content.contains("Level 3"))
        #expect(result.content.contains("Level 2"))
        #expect(result.content.contains("Level 1"))
        // Root should NOT be included (only 3 levels up from level4 = level3, level2, level1)
        #expect(!result.content.contains("\"Root\"") || result.content.contains("Root"))
    }

    @Test("get_block_context truncates long content in descendants")
    @MainActor
    func getBlockContextTruncatesDescendantContent() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let parent = Block(content: "Parent block")
        let longContent = String(repeating: "x", count: 500)
        let child = Block(content: longContent, parent: parent, sortOrder: 1.0)
        context.insert(parent)
        context.insert(child)
        try context.save()

        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let input = JSONValue.object([
            "block_ids": .array([.string(parent.id.uuidString)]),
            "levels_up": .number(0),
            "levels_down": .number(1),
        ])

        let result = try await executor.execute(toolUseId: "toolu_trunc_desc", name: "get_block_context", input: input)
        #expect(!result.isError)
        #expect(!result.content.contains(longContent))
    }

    @Test("get_block_context with multiple block_ids returns context for each")
    @MainActor
    func getBlockContextMultipleBlocks() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block1 = Block(content: "Block Alpha")
        let block2 = Block(content: "Block Beta")
        context.insert(block1)
        context.insert(block2)
        try context.save()

        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let input = JSONValue.object([
            "block_ids": .array([
                .string(block1.id.uuidString),
                .string(block2.id.uuidString),
            ]),
            "levels_up": .number(0),
        ])

        let result = try await executor.execute(toolUseId: "toolu_multi", name: "get_block_context", input: input)
        #expect(!result.isError)
        #expect(result.content.contains("Block Alpha"))
        #expect(result.content.contains("Block Beta"))
    }

    @Test("get_block_context with empty block_ids returns empty array")
    @MainActor
    func getBlockContextEmptyBlockIds() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let input = JSONValue.object([
            "block_ids": .array([]),
        ])

        let result = try await executor.execute(toolUseId: "toolu_empty_ids", name: "get_block_context", input: input)
        #expect(!result.isError)
        #expect(result.content == "[]")
    }

    // MARK: - suggest_edit edge cases

    @Test("suggest_edit with combined add_block and update_block creates correct proposal")
    @MainActor
    func suggestEditCombinedOperations() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let parentId = UUID()
        let blockId = UUID()
        let input = JSONValue.object([
            "description": .string("Add and update blocks"),
            "operations": .array([
                .object([
                    "type": .string("add_block"),
                    "parent_id": .string(parentId.uuidString),
                    "content": .string("New item"),
                ]),
                .object([
                    "type": .string("update_block"),
                    "block_id": .string(blockId.uuidString),
                    "new_content": .string("Updated item"),
                ]),
            ]),
        ])

        let result = try await executor.execute(toolUseId: "toolu_combo", name: "suggest_edit", input: input)
        #expect(!result.isError)
        #expect(result.content.contains("2 operation"))
        #expect(executor.editProposal != nil)
        #expect(executor.editProposal?.operations.count == 2)

        if case .addBlock(let addOp) = executor.editProposal?.operations[0] {
            #expect(addOp.parentId == parentId)
            #expect(addOp.content == "New item")
        } else {
            Issue.record("Expected addBlock as first operation")
        }

        if case .updateBlock(let updateOp) = executor.editProposal?.operations[1] {
            #expect(updateOp.blockId == blockId)
            #expect(updateOp.newContent == "Updated item")
        } else {
            Issue.record("Expected updateBlock as second operation")
        }
    }

    @Test("suggest_edit with all invalid operations returns error")
    @MainActor
    func suggestEditAllInvalidOperations() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let input = JSONValue.object([
            "description": .string("Bad edit"),
            "operations": .array([
                .object([
                    "type": .string("add_block"),
                    // missing parent_id and content
                ]),
                .object([
                    "type": .string("unknown_type"),
                ]),
            ]),
        ])

        let result = try await executor.execute(toolUseId: "toolu_invalid", name: "suggest_edit", input: input)
        #expect(result.isError)
        #expect(result.content.contains("invalid"))
        #expect(executor.editProposal == nil)
    }

    @Test("suggest_edit with unknown operation type returns error")
    @MainActor
    func suggestEditUnknownOperationType() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let input = JSONValue.object([
            "description": .string("Delete attempt"),
            "operations": .array([
                .object([
                    "type": .string("delete_block"),
                    "block_id": .string(UUID().uuidString),
                ]),
            ]),
        ])

        let result = try await executor.execute(toolUseId: "toolu_unk_op", name: "suggest_edit", input: input)
        #expect(result.isError)
        #expect(result.content.contains("invalid"))
    }

    @Test("suggest_edit with mix of valid and invalid operations warns about skipped")
    @MainActor
    func suggestEditMixedValidInvalid() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let parentId = UUID()
        let input = JSONValue.object([
            "description": .string("Mixed edit"),
            "operations": .array([
                .object([
                    "type": .string("add_block"),
                    "parent_id": .string(parentId.uuidString),
                    "content": .string("Valid operation"),
                ]),
                .object([
                    "type": .string("update_block"),
                    // missing block_id
                    "new_content": .string("Should fail"),
                ]),
            ]),
        ])

        let result = try await executor.execute(toolUseId: "toolu_mixed", name: "suggest_edit", input: input)
        #expect(!result.isError)
        #expect(result.content.contains("1 operation"))
        #expect(result.content.contains("Warning"))
        #expect(result.content.contains("invalid and skipped"))
        #expect(executor.editProposal?.operations.count == 1)
    }

    @Test("suggest_edit with add_block including afterBlockId")
    @MainActor
    func suggestEditAddBlockWithAfterBlockId() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        let parentId = UUID()
        let afterId = UUID()
        let input = JSONValue.object([
            "description": .string("Insert after specific block"),
            "operations": .array([
                .object([
                    "type": .string("add_block"),
                    "parent_id": .string(parentId.uuidString),
                    "after_block_id": .string(afterId.uuidString),
                    "content": .string("Inserted after"),
                ]),
            ]),
        ])

        let result = try await executor.execute(toolUseId: "toolu_after", name: "suggest_edit", input: input)
        #expect(!result.isError)

        if case .addBlock(let op) = executor.editProposal?.operations[0] {
            #expect(op.afterBlockId == afterId)
        } else {
            Issue.record("Expected addBlock operation with afterBlockId")
        }
    }

    // MARK: - State accumulation

    @Test("References accumulate across multiple search_notes calls")
    @MainActor
    func referencesAccumulate() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let mockSearch = MockSearchService()
        let id1 = UUID()
        let id2 = UUID()

        let executor = NotoToolExecutor(searchService: mockSearch, modelContext: context)

        // First search
        mockSearch.results = [SearchResult(id: id1, content: "note 1", breadcrumb: "Home", hybridScore: 0.9)]
        _ = try await executor.execute(toolUseId: "t1", name: "search_notes", input: .object(["query": .string("first")]))

        // Second search
        mockSearch.results = [SearchResult(id: id2, content: "note 2", breadcrumb: "Home", hybridScore: 0.8)]
        _ = try await executor.execute(toolUseId: "t2", name: "search_notes", input: .object(["query": .string("second")]))

        #expect(executor.references.count == 2)
        #expect(executor.references[0].blockId == id1)
        #expect(executor.references[1].blockId == id2)
    }
}
