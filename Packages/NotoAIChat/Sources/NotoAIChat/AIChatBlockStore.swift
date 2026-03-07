//
//  AIChatBlockStore.swift
//  NotoAIChat
//

import Foundation
import SwiftData
import os.log
import NotoModels
import NotoCore
import NotoDirtyTracker

private let logger = Logger(subsystem: "com.noto", category: "AIChatBlockStore")

public struct AIChatBlockStore {

    // MARK: - Create

    /// Create a new conversation block under the AI Chat root.
    @MainActor
    @discardableResult
    public static func createConversation(
        noteContext: UUID? = nil,
        context: ModelContext,
        dirtyTracker: DirtyTracker
    ) -> Block {
        let root = AIChatRootService.ensureRoot(context: context)
        let ext = ConversationExtension(noteContextBlockId: noteContext)
        let block = Block(
            content: "Conversation",
            parent: root,
            sortOrder: Block.sortOrderForAppending(to: root.sortedChildren),
            extensionData: Block.encodeExtension(ext),
            isDeletable: true,
            isContentEditableByUser: false,
            isReorderable: false,
            isMovable: false
        )
        context.insert(block)
        addMetadata(block: block, role: .conversation, context: context)
        dirtyTracker.markDirty(block.id)
        logger.debug("Created conversation \(block.id.uuidString.prefix(8))")
        return block
    }

    /// Add a user message to a conversation.
    @MainActor
    @discardableResult
    public static func addUserMessage(
        content: String,
        to conversation: Block,
        context: ModelContext,
        dirtyTracker: DirtyTracker
    ) -> Block {
        let turnIndex = conversation.sortedChildren.count
        let ext = UserMessageExtension(turnIndex: turnIndex)
        let block = Block(
            content: content,
            parent: conversation,
            sortOrder: Block.sortOrderForAppending(to: conversation.sortedChildren),
            extensionData: Block.encodeExtension(ext)
        )
        context.insert(block)
        addMetadata(block: block, role: .userMessage, turnIndex: turnIndex, context: context)
        dirtyTracker.markDirty(block.id)
        logger.debug("Added user message \(block.id.uuidString.prefix(8)) turn=\(turnIndex)")
        return block
    }

    /// Add an AI response to a conversation.
    @MainActor
    @discardableResult
    public static func addAIResponse(
        text: String,
        references: [BlockReference] = [],
        toolCalls: [ToolCallRecord] = [],
        to conversation: Block,
        context: ModelContext,
        dirtyTracker: DirtyTracker
    ) -> Block {
        let turnIndex = conversation.sortedChildren.count
        let ext = AIResponseExtension(turnIndex: turnIndex, references: references, toolCalls: toolCalls)
        let block = Block(
            content: text,
            parent: conversation,
            sortOrder: Block.sortOrderForAppending(to: conversation.sortedChildren),
            extensionData: Block.encodeExtension(ext)
        )
        context.insert(block)
        addMetadata(block: block, role: .aiResponse, turnIndex: turnIndex, context: context)
        dirtyTracker.markDirty(block.id)
        logger.debug("Added AI response \(block.id.uuidString.prefix(8)) turn=\(turnIndex)")
        return block
    }

    /// Add a suggested edit to a conversation.
    @MainActor
    @discardableResult
    public static func addSuggestedEdit(
        proposal: EditProposal,
        parentResponseId: UUID,
        to conversation: Block,
        context: ModelContext,
        dirtyTracker: DirtyTracker
    ) -> Block {
        let ext = SuggestedEditExtension(proposal: proposal)
        let block = Block(
            content: proposal.summary,
            parent: conversation,
            sortOrder: Block.sortOrderForAppending(to: conversation.sortedChildren),
            extensionData: Block.encodeExtension(ext)
        )
        context.insert(block)
        addMetadata(block: block, role: .suggestedEdit, status: .pending, context: context)

        // Store parentResponseId as metadata for queryability
        let responseIdField = MetadataField(
            block: block,
            fieldName: "noto.ai.parentResponseId",
            fieldValue: parentResponseId.uuidString
        )
        context.insert(responseIdField)

        dirtyTracker.markDirty(block.id)
        logger.debug("Added suggested edit \(block.id.uuidString.prefix(8))")
        return block
    }

    // MARK: - Update

    /// Update the status of a suggested edit block.
    @MainActor
    public static func updateEditStatus(
        _ block: Block,
        status: EditStatus,
        context: ModelContext,
        dirtyTracker: DirtyTracker
    ) {
        guard var ext = block.decodeExtension(SuggestedEditExtension.self) else {
            logger.error("updateEditStatus: block \(block.id) has no SuggestedEditExtension")
            return
        }
        ext.status = status
        block.extensionData = Block.encodeExtension(ext)
        block.updatedAt = Date()

        // Update the status metadata field
        if let statusField = block.metadataFields.first(where: { $0.fieldName == AIChatMetadataKeys.status }) {
            statusField.fieldValue = status.rawValue
        }

        dirtyTracker.markDirty(block.id)
        logger.debug("Updated edit status to \(status.rawValue) for \(block.id.uuidString.prefix(8))")
    }

    // MARK: - Fetch

    /// Fetch all conversations under the AI Chat root, sorted by sortOrder.
    @MainActor
    public static func fetchConversations(context: ModelContext) -> [Block] {
        let root = AIChatRootService.ensureRoot(context: context)
        return root.sortedChildren.filter { !$0.isArchived }
    }

    /// Fetch all messages for a conversation, sorted by sortOrder.
    @MainActor
    public static func fetchMessages(for conversation: Block) -> [Block] {
        return conversation.sortedChildren.filter { !$0.isArchived }
    }

    // MARK: - Private

    @MainActor
    private static func addMetadata(
        block: Block,
        role: ChatBlockRole,
        turnIndex: Int? = nil,
        status: EditStatus? = nil,
        context: ModelContext
    ) {
        let roleField = MetadataField(
            block: block,
            fieldName: AIChatMetadataKeys.role,
            fieldValue: role.rawValue
        )
        context.insert(roleField)

        if let turnIndex {
            let turnField = MetadataField(
                block: block,
                fieldName: AIChatMetadataKeys.turnIndex,
                fieldValue: String(turnIndex),
                fieldType: .number
            )
            context.insert(turnField)
        }

        if let status {
            let statusField = MetadataField(
                block: block,
                fieldName: AIChatMetadataKeys.status,
                fieldValue: status.rawValue
            )
            context.insert(statusField)
        }
    }
}
