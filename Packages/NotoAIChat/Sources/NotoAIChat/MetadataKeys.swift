//
//  MetadataKeys.swift
//  NotoAIChat
//

import Foundation

/// Constants for MetadataField keys used in AI chat blocks.
/// These keys are stored in MetadataField.fieldName for queryable attributes.
public enum AIChatMetadataKeys {
    /// The chat block role (conversation, userMessage, aiResponse, suggestedEdit).
    public static let role = "noto.ai.role"

    /// The edit status for suggested edit blocks (pending, accepted, dismissed).
    public static let status = "noto.ai.status"

    /// The turn index within a conversation (0-based).
    public static let turnIndex = "noto.ai.turnIndex"
}
