//
//  AIChatServiceTests.swift
//  NotoAIChatTests
//

import Foundation
import SwiftData
import Synchronization
import Testing
import NotoModels
import NotoSearchLegacy
import NotoClaudeAPI
@testable import NotoAIChat

// MARK: - Mock Client

final class MockClaudeClient: ClaudeAPIClientProtocol, Sendable {
    let responses: [MessagesResponse]
    private let _requests: Mutex<[MessagesRequest]> = Mutex([])

    var requests: [MessagesRequest] {
        _requests.withLock { $0 }
    }

    init(responses: [MessagesResponse]) {
        self.responses = responses
    }

    func sendMessage(_ request: MessagesRequest) async throws -> MessagesResponse {
        let index = _requests.withLock { requests in
            let idx = requests.count
            requests.append(request)
            return idx
        }
        guard index < responses.count else {
            throw ClaudeAPIError.invalidResponse
        }
        return responses[index]
    }
}

// MARK: - Helpers

private func makeUsage() -> Usage {
    Usage(inputTokens: 10, outputTokens: 5)
}

private func makeEndTurnResponse(text: String) -> MessagesResponse {
    MessagesResponse(
        id: "msg_1",
        content: [.text(TextBlock(text: text))],
        stopReason: "end_turn",
        usage: makeUsage()
    )
}

private func makeToolUseResponse(toolId: String, toolName: String, input: JSONValue) -> MessagesResponse {
    MessagesResponse(
        id: "msg_1",
        content: [
            .text(TextBlock(text: "Let me search.")),
            .toolUse(ToolUseBlock(id: toolId, name: toolName, input: input)),
        ],
        stopReason: "tool_use",
        usage: makeUsage()
    )
}

@MainActor
private func createTestContainer() throws -> ModelContainer {
    let schema = Schema([Block.self, BlockLink.self, BlockEmbedding.self, Tag.self, BlockTag.self, MetadataField.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - Tests

@Suite("AIChatService Tests")
struct AIChatServiceTests {

    @Test("Simple chat with no tool use returns text directly")
    @MainActor
    func simpleChatNoTools() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let mockClient = MockClaudeClient(responses: [
            makeEndTurnResponse(text: "Hello! How can I help you?")
        ])
        let mockSearch = MockSearchService()

        let service = AIChatService(
            client: mockClient,
            searchService: mockSearch,
            modelContext: context
        )

        let result = try await service.chat(userMessage: "Hi there")

        #expect(result.text == "Hello! How can I help you?")
        #expect(result.references.isEmpty)
        #expect(result.editProposal == nil)
        #expect(result.toolCallHistory.isEmpty)
    }

    @Test("Chat with search_notes tool call returns references")
    @MainActor
    func chatWithSearchTool() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let blockId = UUID()
        let mockSearch = MockSearchService()
        mockSearch.results = [
            SearchResult(id: blockId, content: "Self-growth note", breadcrumb: "Home / Today", hybridScore: 0.9)
        ]

        let mockClient = MockClaudeClient(responses: [
            makeToolUseResponse(
                toolId: "toolu_1",
                toolName: "search_notes",
                input: .object(["query": .string("self-growth")])
            ),
            makeEndTurnResponse(text: "Based on your notes, you've been thinking about self-growth.")
        ])

        let service = AIChatService(
            client: mockClient,
            searchService: mockSearch,
            modelContext: context
        )

        let result = try await service.chat(userMessage: "What have I been thinking about?")

        #expect(result.text == "Based on your notes, you've been thinking about self-growth.")
        #expect(result.references.count == 1)
        #expect(result.references[0].blockId == blockId)
        #expect(result.toolCallHistory.count == 1)
        #expect(result.toolCallHistory[0].toolName == "search_notes")
    }

    @Test("Chat with note context includes it in system prompt")
    @MainActor
    func chatWithNoteContext() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let mockClient = MockClaudeClient(responses: [
            makeEndTurnResponse(text: "This note is about your projects.")
        ])
        let mockSearch = MockSearchService()

        let service = AIChatService(
            client: mockClient,
            searchService: mockSearch,
            modelContext: context
        )

        let noteCtx = NoteContext(title: "Project Ideas", breadcrumb: "Home / Projects / Ideas")
        let result = try await service.chat(userMessage: "Tell me about this note", noteContext: noteCtx)

        #expect(result.text == "This note is about your projects.")
        // Verify the system prompt includes note context
        let request = mockClient.requests[0]
        #expect(request.system?.contains("Project Ideas") == true)
        #expect(request.system?.contains("Home / Projects / Ideas") == true)
    }

    @Test("Chat with suggest_edit captures edit proposal")
    @MainActor
    func chatWithSuggestEdit() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let parentId = UUID()
        let mockClient = MockClaudeClient(responses: [
            makeToolUseResponse(
                toolId: "toolu_1",
                toolName: "search_notes",
                input: .object(["query": .string("today")])
            ),
            makeToolUseResponse(
                toolId: "toolu_2",
                toolName: "suggest_edit",
                input: .object([
                    "description": .string("Add a new thought"),
                    "operations": .array([
                        .object([
                            "type": .string("add_block"),
                            "parent_id": .string(parentId.uuidString),
                            "content": .string("A new thought for today"),
                        ]),
                    ]),
                ])
            ),
            makeEndTurnResponse(text: "I've suggested adding a new thought."),
        ])
        let mockSearch = MockSearchService()
        mockSearch.results = [
            SearchResult(id: parentId, content: "Today's notes", breadcrumb: "Home / Today", hybridScore: 0.8)
        ]

        let service = AIChatService(
            client: mockClient,
            searchService: mockSearch,
            modelContext: context
        )

        let result = try await service.chat(userMessage: "Add a new thought to today's note")

        #expect(result.text == "I've suggested adding a new thought.")
        #expect(result.editProposal != nil)
        #expect(result.editProposal?.operations.count == 1)
        #expect(result.editProposal?.summary == "Add a new thought")
        #expect(result.toolCallHistory.count == 2)
    }
}

// MARK: - SystemPromptBuilder Tests

@Suite("SystemPromptBuilder Tests")
struct SystemPromptBuilderTests {
    @Test("Base prompt includes key instructions")
    func basePrompt() {
        let prompt = SystemPromptBuilder.build()
        #expect(prompt.contains("Noto"))
        #expect(prompt.contains("search_notes"))
        #expect(prompt.contains("suggest_edit"))
    }

    @Test("Prompt includes current date")
    func includesDate() {
        let date = Date(timeIntervalSince1970: 1_000_000_000)
        let prompt = SystemPromptBuilder.build(currentDate: date)
        #expect(prompt.contains("2001"))
    }

    @Test("Prompt includes note context when provided")
    func includesNoteContext() {
        let ctx = NoteContext(title: "My Project", breadcrumb: "Home / Projects / My Project")
        let prompt = SystemPromptBuilder.build(noteContext: ctx)
        #expect(prompt.contains("My Project"))
        #expect(prompt.contains("Home / Projects / My Project"))
        #expect(prompt.contains("currently viewing"))
    }

    @Test("Prompt without note context has no note section")
    func noNoteContext() {
        let prompt = SystemPromptBuilder.build()
        #expect(!prompt.contains("currently viewing"))
    }
}
