//
//  ChatBlockRole.swift
//  NotoAIChat
//

import Foundation

/// Discriminator for the type of chat block stored in extensionData.
public enum ChatBlockRole: String, Codable, Sendable {
    case conversation
    case userMessage
    case aiResponse
    case suggestedEdit
}
