//
//  AIChatViewModelTests.swift
//  NotoAIChatTests
//
//  Integration tests for AIChatViewModel: end-to-end flow with mock API client
//  but real persistence (in-memory SwiftData).
//

import Foundation
import SwiftData
import Synchronization
import Testing
import NotoModels
import NotoSearch
import NotoClaudeAPI
import NotoDirtyTracker
@testable import NotoAIChat

// MARK: - Mock Client

private final class VMTestMockClient: ClaudeAPIClientProtocol, Sendable {
    let responses: [MessagesResponse]
    private let _callCount: Mutex<Int> = Mutex(0)

    init(responses: [MessagesResponse]) {
        self.responses = responses
    }

    func sendMessage(_ request: MessagesRequest) async throws -> MessagesResponse {
        let idx = _callCount.withLock { count in
            let idx = count
            count += 1
            return idx
        }
        guard idx < responses.count else {
            throw ClaudeAPIError.invalidResponse
        }
        return responses[idx]
    }
}

// MARK: - Helpers

private func makeUsage() -> Usage {
    Usage(inputTokens: 10, outputTokens: 5)
}

private func makeEndTurnResponse(text: String) -> MessagesResponse {
    MessagesResponse(
        id: "msg_\(UUID().uuidString.prefix(8))",
        content: [.text(TextBlock(text: text))],
        stopReason: "end_turn",
        usage: makeUsage()
    )
}

private func makeToolUseResponse(toolId: String, toolName: String, input: JSONValue) -> MessagesResponse {
    MessagesResponse(
        id: "msg_\(UUID().uuidString.prefix(8))",
        content: [
            .text(TextBlock(text: "Searching...")),
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

@MainActor
private func createTestDirtyTracker() async -> DirtyTracker {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = DirtyStore(directory: dir)
    await store.createTablesIfNeeded()
    return DirtyTracker(dirtyStore: store)
}

// MARK: - Tests

@Suite("AIChatViewModel Tests")
struct AIChatViewModelTests {

    @Test("sendMessage creates conversation, persists user and AI messages, updates state")
    @MainActor
    func sendMessageEndToEnd() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let dirtyTracker = await createTestDirtyTracker()

        let mockSearch = MockSearchService()
        let mockClient = VMTestMockClient(responses: [
            makeEndTurnResponse(text: "Hello! I can help you with your notes.")
        ])

        let chatService = AIChatService(
            client: mockClient,
            searchService: mockSearch,
            modelContext: context
        )

        let viewModel = AIChatViewModel(
            chatService: chatService,
            modelContext: context,
            dirtyTracker: dirtyTracker
        )

        #expect(viewModel.messages.isEmpty)

        await viewModel.sendMessage("Hi there")

        // Should have user message + AI response
        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[0].role == ChatMessage.ChatMessageRole.user)
        #expect(viewModel.messages[0].text == "Hi there")
        #expect(viewModel.messages[1].role == ChatMessage.ChatMessageRole.ai)
        #expect(viewModel.messages[1].text == "Hello! I can help you with your notes.")

        #expect(viewModel.state == .complete)

        // Verify persistence
        let conversations = AIChatBlockStore.fetchConversations(context: context)
        #expect(conversations.count == 1)
        let messages = AIChatBlockStore.fetchMessages(for: conversations[0])
        #expect(messages.count == 2)
    }

    @Test("sendMessage with tool call persists references")
    @MainActor
    func sendMessageWithSearch() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let dirtyTracker = await createTestDirtyTracker()

        let blockId = UUID()
        let mockSearch = MockSearchService()
        mockSearch.results = [
            SearchResult(id: blockId, content: "My growth plan", breadcrumb: "Home / Plans", hybridScore: 0.9)
        ]

        let mockClient = VMTestMockClient(responses: [
            makeToolUseResponse(
                toolId: "toolu_1",
                toolName: "search_notes",
                input: .object(["query": .string("growth")])
            ),
            makeEndTurnResponse(text: "I found your growth plan note.")
        ])

        let chatService = AIChatService(
            client: mockClient,
            searchService: mockSearch,
            modelContext: context
        )

        let viewModel = AIChatViewModel(
            chatService: chatService,
            modelContext: context,
            dirtyTracker: dirtyTracker
        )

        await viewModel.sendMessage("What's my growth plan?")

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[1].references.count == 1)
        #expect(viewModel.messages[1].references[0].blockId == blockId)
    }

    @Test("sendMessage with suggest_edit creates edit proposal message")
    @MainActor
    func sendMessageWithSuggestEdit() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let dirtyTracker = await createTestDirtyTracker()

        let parentId = UUID()
        let mockSearch = MockSearchService()
        mockSearch.results = [
            SearchResult(id: parentId, content: "Today's notes", breadcrumb: "Home / Today", hybridScore: 0.8)
        ]

        let mockClient = VMTestMockClient(responses: [
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
                        ])
                    ])
                ])
            ),
            makeEndTurnResponse(text: "I've proposed adding a new thought.")
        ])

        let chatService = AIChatService(
            client: mockClient,
            searchService: mockSearch,
            modelContext: context
        )

        let viewModel = AIChatViewModel(
            chatService: chatService,
            modelContext: context,
            dirtyTracker: dirtyTracker
        )

        await viewModel.sendMessage("Add a thought to today's note")

        // user + ai + suggested edit = 3 messages
        #expect(viewModel.messages.count == 3)
        #expect(viewModel.messages[0].role == ChatMessage.ChatMessageRole.user)
        #expect(viewModel.messages[1].role == ChatMessage.ChatMessageRole.ai)
        #expect(viewModel.messages[2].role == ChatMessage.ChatMessageRole.suggestedEdit)
        #expect(viewModel.messages[2].editProposal != nil)
        #expect(viewModel.messages[2].editStatus == .pending)
    }

    @Test("sendMessage handles API error gracefully")
    @MainActor
    func sendMessageAPIError() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let dirtyTracker = await createTestDirtyTracker()

        let mockSearch = MockSearchService()
        let mockClient = VMTestMockClient(responses: [])

        let chatService = AIChatService(
            client: mockClient,
            searchService: mockSearch,
            modelContext: context
        )

        let viewModel = AIChatViewModel(
            chatService: chatService,
            modelContext: context,
            dirtyTracker: dirtyTracker
        )

        await viewModel.sendMessage("Hello")

        // User message was added before API call
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].role == ChatMessage.ChatMessageRole.user)

        if case .error = viewModel.state {
            // Expected
        } else {
            Issue.record("Expected .error state")
        }
    }

    @Test("Multiple turns accumulate messages correctly")
    @MainActor
    func multipleTurns() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let dirtyTracker = await createTestDirtyTracker()

        let mockSearch = MockSearchService()
        let mockClient = VMTestMockClient(responses: [
            makeEndTurnResponse(text: "First response"),
            makeEndTurnResponse(text: "Second response"),
        ])

        let chatService = AIChatService(
            client: mockClient,
            searchService: mockSearch,
            modelContext: context
        )

        let viewModel = AIChatViewModel(
            chatService: chatService,
            modelContext: context,
            dirtyTracker: dirtyTracker
        )

        await viewModel.sendMessage("First question")
        await viewModel.sendMessage("Second question")

        #expect(viewModel.messages.count == 4)
        #expect(viewModel.messages[0].text == "First question")
        #expect(viewModel.messages[1].text == "First response")
        #expect(viewModel.messages[2].text == "Second question")
        #expect(viewModel.messages[3].text == "Second response")

        // Conversation should have 4 children
        let conversations = AIChatBlockStore.fetchConversations(context: context)
        #expect(conversations.count == 1)
        let messages = AIChatBlockStore.fetchMessages(for: conversations[0])
        #expect(messages.count == 4)
    }

    @Test("Empty message is ignored")
    @MainActor
    func emptyMessageIgnored() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let dirtyTracker = await createTestDirtyTracker()

        let mockSearch = MockSearchService()
        let mockClient = VMTestMockClient(responses: [])

        let chatService = AIChatService(
            client: mockClient,
            searchService: mockSearch,
            modelContext: context
        )

        let viewModel = AIChatViewModel(
            chatService: chatService,
            modelContext: context,
            dirtyTracker: dirtyTracker
        )

        await viewModel.sendMessage("   ")

        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.state == .idle)
    }

    @Test("loadConversation restores messages from persisted blocks")
    @MainActor
    func loadConversation() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let dirtyTracker = await createTestDirtyTracker()

        // Create conversation with messages directly via AIChatBlockStore
        let conversation = AIChatBlockStore.createConversation(
            context: context,
            dirtyTracker: dirtyTracker
        )
        AIChatBlockStore.addUserMessage(
            content: "Previous question",
            to: conversation,
            context: context,
            dirtyTracker: dirtyTracker
        )
        AIChatBlockStore.addAIResponse(
            text: "Previous answer",
            references: [BlockReference(blockId: UUID(), content: "ref content")],
            to: conversation,
            context: context,
            dirtyTracker: dirtyTracker
        )
        try context.save()

        let mockSearch = MockSearchService()
        let mockClient = VMTestMockClient(responses: [
            makeEndTurnResponse(text: "Continuing our chat")
        ])

        let chatService = AIChatService(
            client: mockClient,
            searchService: mockSearch,
            modelContext: context
        )

        let viewModel = AIChatViewModel(
            chatService: chatService,
            modelContext: context,
            dirtyTracker: dirtyTracker
        )

        viewModel.loadConversation(conversation)

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[0].role == ChatMessage.ChatMessageRole.user)
        #expect(viewModel.messages[0].text == "Previous question")
        #expect(viewModel.messages[1].role == ChatMessage.ChatMessageRole.ai)
        #expect(viewModel.messages[1].text == "Previous answer")
        #expect(viewModel.messages[1].references.count == 1)

        // Continue the conversation
        await viewModel.sendMessage("Follow up")

        #expect(viewModel.messages.count == 4)
        #expect(viewModel.messages[3].text == "Continuing our chat")
    }
}
