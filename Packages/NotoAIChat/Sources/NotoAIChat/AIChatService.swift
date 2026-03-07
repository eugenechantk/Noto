//
//  AIChatService.swift
//  NotoAIChat
//

import Foundation
import SwiftData
import os.log
import NotoClaudeAPI

private let logger = Logger(subsystem: "com.noto", category: "AIChatService")

/// Thin orchestrator that creates a ChatLoop + NotoToolExecutor and returns a ChatResult.
public final class AIChatService: @unchecked Sendable {
    private let client: any ClaudeAPIClientProtocol
    public let hasAPIKey: Bool
    private let config: ChatLoopConfig
    private let searchService: any SearchServiceProtocol
    private let modelContext: ModelContext

    public init(
        apiKey: String,
        searchService: any SearchServiceProtocol,
        modelContext: ModelContext,
        config: ChatLoopConfig = ChatLoopConfig()
    ) {
        self.client = ClaudeAPIClient(apiKey: apiKey)
        self.hasAPIKey = !apiKey.isEmpty
        self.config = config
        self.searchService = searchService
        self.modelContext = modelContext
    }

    /// Internal init for testing with a mock client.
    init(
        client: any ClaudeAPIClientProtocol,
        searchService: any SearchServiceProtocol,
        modelContext: ModelContext,
        config: ChatLoopConfig = ChatLoopConfig()
    ) {
        self.client = client
        self.hasAPIKey = true
        self.config = config
        self.searchService = searchService
        self.modelContext = modelContext
    }

    /// Run a single chat turn: sends the user message through the ChatLoop
    /// with Noto tools, and returns a ChatResult with text, references, and optional edit proposal.
    public func chat(
        userMessage: String,
        history: [Message] = [],
        noteContext: NoteContext? = nil
    ) async throws -> ChatResult {
        let executor = NotoToolExecutor(
            searchService: searchService,
            modelContext: modelContext
        )

        let system = SystemPromptBuilder.build(noteContext: noteContext)
        let messages = history + [Message(role: "user", content: .text(userMessage))]

        let loop = ChatLoop(client: client, config: config)
        let loopResult = try await loop.run(
            system: system,
            messages: messages,
            tools: NotoToolDefinitions.all,
            executor: executor
        )

        let toolHistory = loopResult.toolCallHistory.map { record in
            ToolCallRecord(
                toolName: record.name,
                input: jsonValueToString(record.input),
                output: record.output
            )
        }

        logger.debug("Chat completed: \(loopResult.iterationsUsed) iterations, \(executor.references.count) refs, hasEdit=\(executor.editProposal != nil)")

        return ChatResult(
            text: loopResult.finalResponse,
            references: executor.references,
            editProposal: executor.editProposal,
            toolCallHistory: toolHistory
        )
    }

    private func jsonValueToString(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
