//
//  AIResponseExtension.swift
//  NotoAIChat
//

import Foundation

/// Extension data for an AI response block.
public struct AIResponseExtension: Codable, Sendable {
    public let role: ChatBlockRole
    public let turnIndex: Int
    public var references: [BlockReference]
    public var toolCalls: [ToolCallRecord]

    public init(turnIndex: Int, references: [BlockReference] = [], toolCalls: [ToolCallRecord] = []) {
        self.role = .aiResponse
        self.turnIndex = turnIndex
        self.references = references
        self.toolCalls = toolCalls
    }
}
