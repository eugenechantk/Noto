//
//  EditOperation.swift
//  NotoAIChat
//

import Foundation

/// A single edit operation within an EditProposal.
public enum EditOperation: Codable, Sendable {
    case addBlock(AddBlockOp)
    case updateBlock(UpdateBlockOp)
}

/// Parameters for adding a new block.
public struct AddBlockOp: Codable, Sendable {
    public let parentId: UUID
    public let afterBlockId: UUID?
    public let content: String

    public init(parentId: UUID, afterBlockId: UUID? = nil, content: String) {
        self.parentId = parentId
        self.afterBlockId = afterBlockId
        self.content = content
    }
}

/// Parameters for updating an existing block's content.
public struct UpdateBlockOp: Codable, Sendable {
    public let blockId: UUID
    public let newContent: String

    public init(blockId: UUID, newContent: String) {
        self.blockId = blockId
        self.newContent = newContent
    }
}
