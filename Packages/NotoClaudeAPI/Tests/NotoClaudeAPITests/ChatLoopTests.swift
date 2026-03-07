import Testing
import Foundation
import Synchronization
@testable import NotoClaudeAPI

// MARK: - Mock Client

/// A mock API client that returns pre-configured responses in sequence.
/// Uses Mutex for thread-safe request tracking in async contexts.
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

// MARK: - Mock Executor

/// A mock tool executor that returns canned results.
struct MockToolExecutor: ToolExecutor {
    let handler: @Sendable (String, String, JSONValue) -> ToolResult

    init(handler: @escaping @Sendable (String, String, JSONValue) -> ToolResult) {
        self.handler = handler
    }

    func execute(toolUseId: String, name: String, input: JSONValue) async throws -> ToolResult {
        handler(toolUseId, name, input)
    }
}

// MARK: - Helper

func makeUsage() -> Usage {
    Usage(inputTokens: 10, outputTokens: 5)
}

func makeEndTurnResponse(text: String, id: String = "msg_1") -> MessagesResponse {
    MessagesResponse(
        id: id,
        content: [.text(TextBlock(text: text))],
        stopReason: "end_turn",
        usage: makeUsage()
    )
}

func makeToolUseResponse(
    toolId: String = "toolu_1",
    toolName: String = "search_notes",
    input: JSONValue = .object(["query": .string("test")]),
    id: String = "msg_1"
) -> MessagesResponse {
    MessagesResponse(
        id: id,
        content: [
            .text(TextBlock(text: "Let me search for that.")),
            .toolUse(ToolUseBlock(id: toolId, name: toolName, input: input))
        ],
        stopReason: "tool_use",
        usage: makeUsage()
    )
}

// MARK: - Tests

@Suite("ChatLoop Tests")
struct ChatLoopTests {

    @Test("End turn on first response exits loop immediately")
    func endTurnImmediate() async throws {
        let client = MockClaudeClient(responses: [
            makeEndTurnResponse(text: "Hello!")
        ])
        let executor = MockToolExecutor { id, _, _ in
            ToolResult(toolUseId: id, content: "should not be called")
        }
        let loop = ChatLoop(client: client, config: ChatLoopConfig())

        let result = try await loop.run(
            system: "You are helpful.",
            messages: [Message(role: "user", content: .text("Hi"))],
            tools: [],
            executor: executor
        )

        #expect(result.finalResponse == "Hello!")
        #expect(result.toolCallHistory.isEmpty)
        #expect(result.iterationsUsed == 0)
        #expect(client.requests.count == 1)
    }

    @Test("Tool use followed by end turn completes in 1 iteration")
    func toolUseThenEndTurn() async throws {
        let client = MockClaudeClient(responses: [
            makeToolUseResponse(toolId: "toolu_1", toolName: "search_notes"),
            makeEndTurnResponse(text: "Based on your notes...")
        ])
        let executor = MockToolExecutor { id, name, _ in
            ToolResult(toolUseId: id, content: "{\"results\": [\"note1\"]}")
        }
        let loop = ChatLoop(client: client, config: ChatLoopConfig())

        let result = try await loop.run(
            system: "System",
            messages: [Message(role: "user", content: .text("Search my notes"))],
            tools: [],
            executor: executor
        )

        #expect(result.finalResponse == "Based on your notes...")
        #expect(result.toolCallHistory.count == 1)
        #expect(result.toolCallHistory[0].name == "search_notes")
        #expect(result.toolCallHistory[0].output == "{\"results\": [\"note1\"]}")
        #expect(result.iterationsUsed == 1)
        #expect(client.requests.count == 2)
    }

    @Test("Max iterations cap is respected")
    func maxIterationsCap() async throws {
        let maxIter = 3
        // Return tool_use for maxIter calls, then final end_turn for the no-tools call
        var responses: [MessagesResponse] = []
        for i in 0..<maxIter {
            responses.append(makeToolUseResponse(toolId: "toolu_\(i)", toolName: "search_notes"))
        }
        responses.append(makeEndTurnResponse(text: "Final answer after cap"))

        let client = MockClaudeClient(responses: responses)
        let executor = MockToolExecutor { id, _, _ in
            ToolResult(toolUseId: id, content: "result")
        }
        let config = ChatLoopConfig(maxToolIterations: maxIter)
        let loop = ChatLoop(client: client, config: config)

        let result = try await loop.run(
            system: "System",
            messages: [Message(role: "user", content: .text("Keep searching"))],
            tools: [],
            executor: executor
        )

        #expect(result.finalResponse == "Final answer after cap")
        #expect(result.toolCallHistory.count == maxIter)
        #expect(result.iterationsUsed == maxIter)
        // maxIter tool_use calls + 1 final call without tools
        #expect(client.requests.count == maxIter + 1)

        // Verify the final request has no tools
        let finalRequest = client.requests.last!
        #expect(finalRequest.tools == nil)
    }

    @Test("Correct message threading: assistant tool_use then user tool_result")
    func messageThreading() async throws {
        let client = MockClaudeClient(responses: [
            makeToolUseResponse(toolId: "toolu_1", toolName: "search"),
            makeEndTurnResponse(text: "Done")
        ])
        let executor = MockToolExecutor { id, _, _ in
            ToolResult(toolUseId: id, content: "search result")
        }
        let loop = ChatLoop(client: client, config: ChatLoopConfig())

        _ = try await loop.run(
            system: "System",
            messages: [Message(role: "user", content: .text("Search"))],
            tools: [],
            executor: executor
        )

        // The second request should have 3 messages:
        // 1. Original user message
        // 2. Assistant message with tool_use
        // 3. User message with tool_result
        let secondRequest = client.requests[1]
        #expect(secondRequest.messages.count == 3)
        #expect(secondRequest.messages[0].role == "user")
        #expect(secondRequest.messages[1].role == "assistant")
        #expect(secondRequest.messages[2].role == "user")

        // Verify the assistant message contains the tool_use block
        if case .blocks(let blocks) = secondRequest.messages[1].content {
            let hasToolUse = blocks.contains { block in
                if case .toolUse = block { return true }
                return false
            }
            #expect(hasToolUse)
        } else {
            Issue.record("Expected blocks content for assistant message")
        }

        // Verify the user message contains the tool_result block
        if case .blocks(let blocks) = secondRequest.messages[2].content {
            let hasToolResult = blocks.contains { block in
                if case .toolResult(let result) = block {
                    return result.toolUseId == "toolu_1"
                }
                return false
            }
            #expect(hasToolResult)
        } else {
            Issue.record("Expected blocks content for tool result message")
        }
    }

    @Test("Unexpected stop reason throws error")
    func unexpectedStopReason() async throws {
        let client = MockClaudeClient(responses: [
            MessagesResponse(
                id: "msg_1",
                content: [.text(TextBlock(text: "Partial"))],
                stopReason: "max_tokens",
                usage: makeUsage()
            )
        ])
        let executor = MockToolExecutor { id, _, _ in
            ToolResult(toolUseId: id, content: "")
        }
        let loop = ChatLoop(client: client, config: ChatLoopConfig())

        await #expect(throws: ChatLoopError.self) {
            try await loop.run(
                system: "System",
                messages: [Message(role: "user", content: .text("Hi"))],
                tools: [],
                executor: executor
            )
        }
    }

    @Test("Multiple tool calls in single response are all executed")
    func multipleToolCallsInOneResponse() async throws {
        let multiToolResponse = MessagesResponse(
            id: "msg_1",
            content: [
                .toolUse(ToolUseBlock(id: "toolu_1", name: "search", input: .string("a"))),
                .toolUse(ToolUseBlock(id: "toolu_2", name: "get_context", input: .string("b")))
            ],
            stopReason: "tool_use",
            usage: makeUsage()
        )
        let client = MockClaudeClient(responses: [
            multiToolResponse,
            makeEndTurnResponse(text: "All done")
        ])

        let executor = MockToolExecutor { id, name, _ in
            ToolResult(toolUseId: id, content: "result for \(name)")
        }
        let loop = ChatLoop(client: client, config: ChatLoopConfig())

        let result = try await loop.run(
            system: "System",
            messages: [Message(role: "user", content: .text("Multi"))],
            tools: [],
            executor: executor
        )

        #expect(result.toolCallHistory.count == 2)
        #expect(result.toolCallHistory[0].name == "search")
        #expect(result.toolCallHistory[1].name == "get_context")
        #expect(result.iterationsUsed == 1)
    }

    @Test("Tool error results have isError set")
    func toolErrorResult() async throws {
        let client = MockClaudeClient(responses: [
            makeToolUseResponse(toolId: "toolu_1", toolName: "bad_tool"),
            makeEndTurnResponse(text: "Sorry, that failed")
        ])
        let executor = MockToolExecutor { id, _, _ in
            ToolResult(toolUseId: id, content: "Unknown tool", isError: true)
        }
        let loop = ChatLoop(client: client, config: ChatLoopConfig())

        let result = try await loop.run(
            system: "System",
            messages: [Message(role: "user", content: .text("Use bad tool"))],
            tools: [],
            executor: executor
        )

        // Verify the tool result in the request has is_error set
        let secondRequest = client.requests[1]
        if case .blocks(let blocks) = secondRequest.messages[2].content,
           case .toolResult(let resultBlock) = blocks[0] {
            #expect(resultBlock.isError == true)
        } else {
            Issue.record("Expected tool result with isError")
        }

        #expect(result.finalResponse == "Sorry, that failed")
    }

    @Test("Multi-iteration tool chain works correctly")
    func multiIterationToolChain() async throws {
        let client = MockClaudeClient(responses: [
            makeToolUseResponse(toolId: "toolu_1", toolName: "search_notes"),
            makeToolUseResponse(toolId: "toolu_2", toolName: "get_block_context"),
            makeToolUseResponse(toolId: "toolu_3", toolName: "suggest_edit"),
            makeEndTurnResponse(text: "I've suggested the edit.")
        ])
        let executor = MockToolExecutor { id, name, _ in
            ToolResult(toolUseId: id, content: "result from \(name)")
        }
        let loop = ChatLoop(client: client, config: ChatLoopConfig(maxToolIterations: 5))

        let result = try await loop.run(
            system: "System",
            messages: [Message(role: "user", content: .text("Edit my notes"))],
            tools: [],
            executor: executor
        )

        #expect(result.finalResponse == "I've suggested the edit.")
        #expect(result.toolCallHistory.count == 3)
        #expect(result.toolCallHistory[0].name == "search_notes")
        #expect(result.toolCallHistory[1].name == "get_block_context")
        #expect(result.toolCallHistory[2].name == "suggest_edit")
        #expect(result.iterationsUsed == 3)
        #expect(client.requests.count == 4)
    }
}
