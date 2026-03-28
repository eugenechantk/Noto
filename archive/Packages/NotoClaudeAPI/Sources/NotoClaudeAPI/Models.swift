import Foundation

// MARK: - Request

public struct MessagesRequest: Encodable, Sendable {
    public let model: String
    public let maxTokens: Int
    public let system: String?
    public let messages: [Message]
    public let tools: [ToolDefinition]?

    public init(
        model: String,
        maxTokens: Int,
        system: String?,
        messages: [Message],
        tools: [ToolDefinition]?
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
        self.tools = tools
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(system, forKey: .system)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(tools, forKey: .tools)
    }
}

// MARK: - Message

public struct Message: Codable, Sendable {
    public let role: String
    public let content: MessageContent

    public init(role: String, content: MessageContent) {
        self.role = role
        self.content = content
    }
}

// MARK: - MessageContent

public enum MessageContent: Sendable, Equatable {
    case text(String)
    case blocks([ContentBlock])
}

extension MessageContent: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            let blocks = try container.decode([ContentBlock].self)
            self = .blocks(blocks)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

// MARK: - ContentBlock

public enum ContentBlock: Sendable, Equatable {
    case text(TextBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)
}

extension ContentBlock: Codable {
    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try TextBlock(from: decoder))
        case "tool_use":
            self = .toolUse(try ToolUseBlock(from: decoder))
        case "tool_result":
            self = .toolResult(try ToolResultBlock(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown content block type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let block):
            try block.encode(to: encoder)
        case .toolUse(let block):
            try block.encode(to: encoder)
        case .toolResult(let block):
            try block.encode(to: encoder)
        }
    }
}

// MARK: - Block Types

public struct TextBlock: Codable, Sendable, Equatable {
    public let type: String
    public let text: String

    public init(text: String) {
        self.type = "text"
        self.text = text
    }
}

public struct ToolUseBlock: Codable, Sendable, Equatable {
    public let type: String
    public let id: String
    public let name: String
    public let input: JSONValue

    public init(id: String, name: String, input: JSONValue) {
        self.type = "tool_use"
        self.id = id
        self.name = name
        self.input = input
    }
}

public struct ToolResultBlock: Codable, Sendable, Equatable {
    public let type: String
    public let toolUseId: String
    public let content: String
    public let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }

    public init(toolUseId: String, content: String, isError: Bool? = nil) {
        self.type = "tool_result"
        self.toolUseId = toolUseId
        self.content = content
        self.isError = isError
    }
}

// MARK: - Response

public struct MessagesResponse: Codable, Sendable {
    public let id: String
    public let content: [ContentBlock]
    public let stopReason: String
    public let usage: Usage

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case stopReason = "stop_reason"
        case usage
    }

    public init(id: String, content: [ContentBlock], stopReason: String, usage: Usage) {
        self.id = id
        self.content = content
        self.stopReason = stopReason
        self.usage = usage
    }
}

public struct Usage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}
