//
//  ConversationExtension.swift
//  NotoAIChat
//

import Foundation

/// Extension data for a conversation root block.
public struct ConversationExtension: Codable, Sendable {
    public let role: ChatBlockRole
    public let createdAt: Date
    public var noteContextBlockId: UUID?

    public init(createdAt: Date = Date(), noteContextBlockId: UUID? = nil) {
        self.role = .conversation
        self.createdAt = createdAt
        self.noteContextBlockId = noteContextBlockId
    }
}
