import Foundation
import OSLog

private let logger = Logger(subsystem: "com.noto.claudeapi", category: "ChatLoop")

/// A capped tool-use loop that drives tool_use -> execute -> tool_result cycles.
///
/// The loop sends messages to Claude, and when Claude responds with tool_use,
/// it executes the tools via the provided ToolExecutor, appends the results,
/// and continues until Claude responds with end_turn or the max iteration cap is hit.
public struct ChatLoop: Sendable {
    private let client: any ClaudeAPIClientProtocol
    private let config: ChatLoopConfig

    public init(client: any ClaudeAPIClientProtocol, config: ChatLoopConfig = .init()) {
        self.client = client
        self.config = config
    }

    public func run(
        system: String,
        messages: [Message],
        tools: [ToolDefinition],
        executor: any ToolExecutor
    ) async throws -> ChatLoopResult {
        var currentMessages = messages
        var toolCallHistory: [ToolCallRecord] = []
        var iteration = 0

        while iteration < config.maxToolIterations {
            let request = MessagesRequest(
                model: config.model,
                maxTokens: config.maxTokens,
                system: system,
                messages: currentMessages,
                tools: tools.isEmpty ? nil : tools
            )

            let response = try await client.sendMessage(request)

            if response.stopReason == "end_turn" {
                let text = extractText(from: response.content)
                logger.debug("ChatLoop completed with end_turn after \(iteration) iteration(s)")
                return ChatLoopResult(
                    finalResponse: text,
                    toolCallHistory: toolCallHistory,
                    iterationsUsed: iteration
                )
            }

            guard response.stopReason == "tool_use" else {
                throw ChatLoopError.unexpectedStopReason(response.stopReason)
            }

            let toolCalls = extractToolUses(from: response.content)
            var toolResults: [ContentBlock] = []

            for toolCall in toolCalls {
                logger.debug("Executing tool: \(toolCall.name) (id: \(toolCall.id))")
                let result = try await executor.execute(
                    toolUseId: toolCall.id,
                    name: toolCall.name,
                    input: toolCall.input
                )
                let resultBlock = ToolResultBlock(
                    toolUseId: result.toolUseId,
                    content: result.content,
                    isError: result.isError ? true : nil
                )
                toolResults.append(.toolResult(resultBlock))
                toolCallHistory.append(ToolCallRecord(
                    name: toolCall.name,
                    input: toolCall.input,
                    output: result.content
                ))
            }

            // Append assistant response (with tool_use blocks) and user tool_results
            currentMessages.append(Message(role: "assistant", content: .blocks(response.content)))
            currentMessages.append(Message(role: "user", content: .blocks(toolResults)))
            iteration += 1
        }

        // Hit max iterations — final call without tools to force a text response
        logger.debug("ChatLoop hit max iterations (\(config.maxToolIterations)), sending final request without tools")
        let finalRequest = MessagesRequest(
            model: config.model,
            maxTokens: config.maxTokens,
            system: system,
            messages: currentMessages,
            tools: nil
        )
        let finalResponse = try await client.sendMessage(finalRequest)
        let text = extractText(from: finalResponse.content)

        return ChatLoopResult(
            finalResponse: text,
            toolCallHistory: toolCallHistory,
            iterationsUsed: iteration
        )
    }

    // MARK: - Helpers

    private func extractText(from content: [ContentBlock]) -> String {
        content.compactMap { block in
            if case .text(let textBlock) = block {
                return textBlock.text
            }
            return nil
        }.joined(separator: "\n")
    }

    private func extractToolUses(from content: [ContentBlock]) -> [ToolUseBlock] {
        content.compactMap { block in
            if case .toolUse(let toolUseBlock) = block {
                return toolUseBlock
            }
            return nil
        }
    }
}
