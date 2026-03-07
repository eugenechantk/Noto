//
//  ToolCallRecord.swift
//  NotoAIChat
//

import Foundation

/// Record of a tool invocation made during an AI response.
public struct ToolCallRecord: Codable, Sendable {
    public let toolName: String
    public let input: String
    public let output: String

    public init(toolName: String, input: String, output: String) {
        self.toolName = toolName
        self.input = input
        self.output = output
    }
}
