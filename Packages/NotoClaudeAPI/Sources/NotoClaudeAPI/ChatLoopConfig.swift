import Foundation

/// Configuration for the ChatLoop.
public struct ChatLoopConfig: Sendable {
    public var model: String
    public var maxTokens: Int
    public var maxToolIterations: Int

    public init(
        model: String = "anthropic/claude-sonnet-4.6",
        maxTokens: Int = 4096,
        maxToolIterations: Int = 5
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.maxToolIterations = maxToolIterations
    }
}

/// Record of a single tool call made during a ChatLoop run.
public struct ToolCallRecord: Sendable {
    public let name: String
    public let input: JSONValue
    public let output: String

    public init(name: String, input: JSONValue, output: String) {
        self.name = name
        self.input = input
        self.output = output
    }
}

/// Result of a ChatLoop run.
public struct ChatLoopResult: Sendable {
    public let finalResponse: String
    public let toolCallHistory: [ToolCallRecord]
    public let iterationsUsed: Int

    public init(finalResponse: String, toolCallHistory: [ToolCallRecord], iterationsUsed: Int) {
        self.finalResponse = finalResponse
        self.toolCallHistory = toolCallHistory
        self.iterationsUsed = iterationsUsed
    }
}
