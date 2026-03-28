//
//  UserMessageExtension.swift
//  NotoAIChat
//

import Foundation

/// Extension data for a user message block.
public struct UserMessageExtension: Codable, Sendable {
    public let role: ChatBlockRole
    public let turnIndex: Int

    public init(turnIndex: Int) {
        self.role = .userMessage
        self.turnIndex = turnIndex
    }
}
