import Testing
import Foundation
@testable import NotoClaudeAPI

@Suite("Models Codable Tests")
struct ModelsTests {

    // MARK: - TextBlock

    @Test("TextBlock encode/decode round trip")
    func textBlockRoundTrip() throws {
        let block = TextBlock(text: "Hello, world!")
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(TextBlock.self, from: data)
        #expect(decoded.type == "text")
        #expect(decoded.text == "Hello, world!")
    }

    // MARK: - ToolUseBlock

    @Test("ToolUseBlock encode/decode round trip")
    func toolUseBlockRoundTrip() throws {
        let block = ToolUseBlock(
            id: "toolu_123",
            name: "search_notes",
            input: .object(["query": .string("self-growth")])
        )
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(ToolUseBlock.self, from: data)
        #expect(decoded.type == "tool_use")
        #expect(decoded.id == "toolu_123")
        #expect(decoded.name == "search_notes")
        #expect(decoded.input["query"]?.stringValue == "self-growth")
    }

    // MARK: - ToolResultBlock

    @Test("ToolResultBlock encode/decode round trip")
    func toolResultBlockRoundTrip() throws {
        let block = ToolResultBlock(
            toolUseId: "toolu_123",
            content: "{\"results\": []}",
            isError: nil
        )
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(ToolResultBlock.self, from: data)
        #expect(decoded.type == "tool_result")
        #expect(decoded.toolUseId == "toolu_123")
        #expect(decoded.content == "{\"results\": []}")
        #expect(decoded.isError == nil)
    }

    @Test("ToolResultBlock with isError encodes correctly")
    func toolResultBlockWithError() throws {
        let block = ToolResultBlock(
            toolUseId: "toolu_456",
            content: "Tool not found",
            isError: true
        )
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(ToolResultBlock.self, from: data)
        #expect(decoded.isError == true)
    }

    // MARK: - ContentBlock

    @Test("ContentBlock text variant encode/decode")
    func contentBlockText() throws {
        let block = ContentBlock.text(TextBlock(text: "Hello"))
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(ContentBlock.self, from: data)
        if case .text(let textBlock) = decoded {
            #expect(textBlock.text == "Hello")
        } else {
            Issue.record("Expected text block")
        }
    }

    @Test("ContentBlock toolUse variant encode/decode")
    func contentBlockToolUse() throws {
        let block = ContentBlock.toolUse(ToolUseBlock(
            id: "toolu_1",
            name: "search",
            input: .object(["q": .string("test")])
        ))
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(ContentBlock.self, from: data)
        if case .toolUse(let toolUseBlock) = decoded {
            #expect(toolUseBlock.name == "search")
        } else {
            Issue.record("Expected toolUse block")
        }
    }

    @Test("ContentBlock toolResult variant encode/decode")
    func contentBlockToolResult() throws {
        let block = ContentBlock.toolResult(ToolResultBlock(
            toolUseId: "toolu_1",
            content: "result data"
        ))
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(ContentBlock.self, from: data)
        if case .toolResult(let resultBlock) = decoded {
            #expect(resultBlock.toolUseId == "toolu_1")
        } else {
            Issue.record("Expected toolResult block")
        }
    }

    // MARK: - MessageContent

    @Test("MessageContent text encodes as string")
    func messageContentText() throws {
        let content = MessageContent.text("Hello")
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MessageContent.self, from: data)
        if case .text(let text) = decoded {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test("MessageContent blocks encodes as array")
    func messageContentBlocks() throws {
        let content = MessageContent.blocks([
            .text(TextBlock(text: "Hello")),
            .toolUse(ToolUseBlock(id: "t1", name: "search", input: .null))
        ])
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MessageContent.self, from: data)
        if case .blocks(let blocks) = decoded {
            #expect(blocks.count == 2)
        } else {
            Issue.record("Expected blocks content")
        }
    }

    // MARK: - Message

    @Test("Message encode/decode round trip")
    func messageRoundTrip() throws {
        let message = Message(role: "user", content: .text("Hi"))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.role == "user")
    }

    // MARK: - MessagesResponse

    @Test("MessagesResponse decode from JSON")
    func messagesResponseDecode() throws {
        let json = """
        {
            "id": "msg_123",
            "content": [{"type": "text", "text": "Hello!"}],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 5}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MessagesResponse.self, from: json)
        #expect(response.id == "msg_123")
        #expect(response.stopReason == "end_turn")
        #expect(response.usage.inputTokens == 10)
        #expect(response.usage.outputTokens == 5)
        #expect(response.content.count == 1)
    }

    // MARK: - MessagesRequest

    @Test("MessagesRequest encodes with snake_case keys")
    func messagesRequestEncoding() throws {
        let request = MessagesRequest(
            model: "claude-sonnet-4-6",
            maxTokens: 1024,
            system: "You are helpful",
            messages: [Message(role: "user", content: .text("Hi"))],
            tools: nil
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        #expect(json["max_tokens"]?.numberValue == 1024)
        #expect(json["model"]?.stringValue == "claude-sonnet-4-6")
        #expect(json["system"]?.stringValue == "You are helpful")
    }

    // MARK: - Usage

    @Test("Usage decode with snake_case keys")
    func usageDecode() throws {
        let json = """
        {"input_tokens": 100, "output_tokens": 50}
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(Usage.self, from: json)
        #expect(usage.inputTokens == 100)
        #expect(usage.outputTokens == 50)
    }
}
