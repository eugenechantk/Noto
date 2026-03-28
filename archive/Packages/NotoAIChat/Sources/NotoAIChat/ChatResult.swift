//
//  ChatResult.swift
//  NotoAIChat
//

import Foundation

/// The result of a single AI chat turn, returned by AIChatService.
public struct ChatResult: Sendable {
    public let text: String
    public let references: [BlockReference]
    public let editProposal: EditProposal?
    public let toolCallHistory: [ToolCallRecord]

    public init(
        text: String,
        references: [BlockReference],
        editProposal: EditProposal?,
        toolCallHistory: [ToolCallRecord]
    ) {
        self.text = text
        self.references = references
        self.editProposal = editProposal
        self.toolCallHistory = toolCallHistory
    }
}
