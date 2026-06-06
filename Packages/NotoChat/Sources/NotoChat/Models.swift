import Foundation

/// Default model — cheapest reliable Gemini tool-caller on OpenRouter.
/// Swappable via `ChatAgent.model` / `ChatRequest.model`.
public let defaultModel = "google/gemini-3.1-flash-lite"

// MARK: - JSON value (for tool parameter schemas / arbitrary JSON)

/// A minimal Codable JSON value, used to express tool parameter JSON Schemas.
public indirect enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: - Chat messages

public enum ChatRole: String, Codable, Sendable {
    case system, user, assistant, tool
}

/// One tool call requested by the model.
public struct ToolCall: Codable, Sendable, Equatable, Identifiable {
    public struct Function: Codable, Sendable, Equatable {
        public var name: String
        /// Raw JSON arguments string (as the model emits it).
        public var arguments: String
        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }
    public var id: String
    public var type: String
    public var function: Function

    public init(id: String, type: String = "function", function: Function) {
        self.id = id
        self.type = type
        self.function = function
    }
}

/// An OpenAI-compatible chat message.
public struct ChatMessage: Codable, Sendable, Equatable {
    public var role: ChatRole
    public var content: String?
    public var toolCalls: [ToolCall]?
    public var toolCallID: String?
    public var name: String?

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    public init(role: ChatRole,
                content: String? = nil,
                toolCalls: [ToolCall]? = nil,
                toolCallID: String? = nil,
                name: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
    }

    public static func system(_ text: String) -> ChatMessage { .init(role: .system, content: text) }
    public static func user(_ text: String) -> ChatMessage { .init(role: .user, content: text) }
    public static func assistant(_ text: String) -> ChatMessage { .init(role: .assistant, content: text) }
    /// A tool result message answering a specific tool call.
    public static func toolResult(_ output: String, callID: String, name: String) -> ChatMessage {
        .init(role: .tool, content: output, toolCallID: callID, name: name)
    }
}

// MARK: - Tool definitions

/// An OpenAI-compatible function/tool definition advertised to the model.
public struct ToolDefinition: Codable, Sendable, Equatable {
    public struct Function: Codable, Sendable, Equatable {
        public var name: String
        public var description: String
        public var parameters: JSONValue
        public init(name: String, description: String, parameters: JSONValue) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }
    public var type: String
    public var function: Function
    public init(type: String = "function", function: Function) {
        self.type = type
        self.function = function
    }
}

// MARK: - Request

/// High-level request the client turns into an OpenAI-compatible payload.
public struct ChatRequest: Sendable {
    public var model: String
    public var messages: [ChatMessage]
    public var tools: [ToolDefinition]
    public var temperature: Double?
    public var maxTokens: Int?

    public init(model: String = defaultModel,
                messages: [ChatMessage],
                tools: [ToolDefinition] = [],
                temperature: Double? = nil,
                maxTokens: Int? = nil) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

/// Wire payload for POST /chat/completions.
struct ChatCompletionPayload: Encodable {
    let model: String
    let messages: [ChatMessage]
    let tools: [ToolDefinition]?
    let toolChoice: String?
    let stream: Bool
    let temperature: Double?
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream, temperature
        case toolChoice = "tool_choice"
        case maxTokens = "max_tokens"
    }

    init(_ request: ChatRequest, stream: Bool) {
        self.model = request.model
        self.messages = request.messages
        self.tools = request.tools.isEmpty ? nil : request.tools
        self.toolChoice = request.tools.isEmpty ? nil : "auto"
        self.stream = stream
        self.temperature = request.temperature
        self.maxTokens = request.maxTokens
    }
}

// MARK: - Responses

/// Non-streaming completion response (only the bits we use).
struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        let message: ChatMessage
        let finishReason: String?
        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    let choices: [Choice]
}

/// Streaming chunk (only the bits we use).
struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let toolCalls: [ToolCallDelta]?
            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
        let delta: Delta
        let finishReason: String?
        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }
    let choices: [Choice]
}

struct ToolCallDelta: Decodable {
    struct FunctionDelta: Decodable {
        let name: String?
        let arguments: String?
    }
    let index: Int
    let id: String?
    let type: String?
    let function: FunctionDelta?
}

// MARK: - Streaming events

/// Events emitted by `LLMClienting.stream`.
public enum ChatStreamEvent: Sendable, Equatable {
    /// An incremental chunk of assistant text.
    case textDelta(String)
    /// The fully-assembled tool calls (emitted once the model finishes requesting tools).
    case toolCalls([ToolCall])
    /// The model finished this turn. `reason` e.g. "stop" or "tool_calls".
    case finished(reason: String?)
}

// MARK: - Errors

public enum LLMError: Error, Sendable, Equatable {
    case missingAPIKey
    case http(status: Int, body: String)
    case emptyResponse
    case decoding(String)
}
