import Foundation

/// Result of executing a tool call.
public struct ToolResult: Sendable {
    public let toolUseId: String
    public let content: String
    public let isError: Bool

    public init(toolUseId: String, content: String, isError: Bool = false) {
        self.toolUseId = toolUseId
        self.content = content
        self.isError = isError
    }
}

/// Protocol for executing tool calls locally.
/// Implement this to define how each tool name is handled.
public protocol ToolExecutor: Sendable {
    func execute(toolUseId: String, name: String, input: JSONValue) async throws -> ToolResult
}
