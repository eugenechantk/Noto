//
//  AIChatBlockStoreTests.swift
//  NotoAIChatTests
//

import Foundation
import SwiftData
import Testing
import NotoModels
import NotoCore
import NotoDirtyTracker
@testable import NotoAIChat

// MARK: - Test DirtyTracker Helper

/// Creates a DirtyTracker with an in-memory DirtyStore for testing.
@MainActor
private func createTestDirtyTracker() async -> DirtyTracker {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = DirtyStore(directory: tmpDir)
    await store.createTablesIfNeeded()
    return DirtyTracker(dirtyStore: store, idleDelay: 60)
}

// MARK: - AIChatRootService Tests

@Suite("AIChatRootService")
struct AIChatRootServiceTests {

    @Test @MainActor func ensureRootCreatesBlock() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = AIChatRootService.ensureRoot(context: context)
        #expect(root.content == "AI Chat")
        #expect(root.parent == nil)
        #expect(root.isDeletable == false)
        #expect(root.isContentEditableByUser == false)
        #expect(root.isReorderable == false)
        #expect(root.isMovable == false)
    }

    @Test @MainActor func ensureRootReturnsExisting() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let first = AIChatRootService.ensureRoot(context: context)
        try context.save()
        let second = AIChatRootService.ensureRoot(context: context)
        #expect(first.id == second.id)
    }
}

// MARK: - AIChatBlockStore Tests

@Suite("AIChatBlockStore")
struct AIChatBlockStoreTests {

    @Test @MainActor func createConversation() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let noteId = UUID()
        let conv = AIChatBlockStore.createConversation(
            noteContext: noteId,
            context: context,
            dirtyTracker: tracker
        )

        #expect(conv.content == "Conversation")
        #expect(conv.parent?.content == "AI Chat")
        #expect(conv.isContentEditableByUser == false)

        let ext = conv.decodeExtension(ConversationExtension.self)
        #expect(ext != nil)
        #expect(ext?.role == .conversation)
        #expect(ext?.noteContextBlockId == noteId)

        let roleField = conv.metadataFields.first { $0.fieldName == AIChatMetadataKeys.role }
        #expect(roleField?.fieldValue == "conversation")

        #expect(tracker.hasDirtyBlocks == true)
    }

    @Test @MainActor func addUserMessage() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let conv = AIChatBlockStore.createConversation(context: context, dirtyTracker: tracker)
        let msg = AIChatBlockStore.addUserMessage(
            content: "What am I thinking today?",
            to: conv,
            context: context,
            dirtyTracker: tracker
        )

        #expect(msg.content == "What am I thinking today?")
        #expect(msg.parent?.id == conv.id)

        let ext = msg.decodeExtension(UserMessageExtension.self)
        #expect(ext != nil)
        #expect(ext?.role == .userMessage)
        #expect(ext?.turnIndex == 0)

        let turnField = msg.metadataFields.first { $0.fieldName == AIChatMetadataKeys.turnIndex }
        #expect(turnField?.fieldValue == "0")
    }

    @Test @MainActor func addAIResponseWithReferences() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let conv = AIChatBlockStore.createConversation(context: context, dirtyTracker: tracker)
        _ = AIChatBlockStore.addUserMessage(content: "test", to: conv, context: context, dirtyTracker: tracker)

        let refs = [
            BlockReference(blockId: UUID(), content: "Note about cats", relevanceScore: 0.95),
            BlockReference(blockId: UUID(), content: "Note about dogs", relevanceScore: 0.80),
        ]
        let tools = [ToolCallRecord(toolName: "search_notes", input: "cats", output: "found 2")]

        let response = AIChatBlockStore.addAIResponse(
            text: "You were thinking about pets.",
            references: refs,
            toolCalls: tools,
            to: conv,
            context: context,
            dirtyTracker: tracker
        )

        #expect(response.content == "You were thinking about pets.")
        #expect(response.parent?.id == conv.id)

        let ext = response.decodeExtension(AIResponseExtension.self)
        #expect(ext != nil)
        #expect(ext?.role == .aiResponse)
        #expect(ext?.turnIndex == 1)
        #expect(ext?.references.count == 2)
        #expect(ext?.references[0].relevanceScore == 0.95)
        #expect(ext?.toolCalls.count == 1)
        #expect(ext?.toolCalls[0].toolName == "search_notes")
    }

    @Test @MainActor func addSuggestedEdit() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let conv = AIChatBlockStore.createConversation(context: context, dirtyTracker: tracker)
        let responseId = UUID()
        let proposal = EditProposal(
            operations: [
                .addBlock(AddBlockOp(parentId: UUID(), content: "new item")),
            ],
            summary: "Add a new item"
        )

        let edit = AIChatBlockStore.addSuggestedEdit(
            proposal: proposal,
            parentResponseId: responseId,
            to: conv,
            context: context,
            dirtyTracker: tracker
        )

        #expect(edit.content == "Add a new item")
        #expect(edit.parent?.id == conv.id)

        let ext = edit.decodeExtension(SuggestedEditExtension.self)
        #expect(ext != nil)
        #expect(ext?.role == .suggestedEdit)
        #expect(ext?.status == .pending)
        #expect(ext?.proposal.operations.count == 1)

        let statusField = edit.metadataFields.first { $0.fieldName == AIChatMetadataKeys.status }
        #expect(statusField?.fieldValue == "pending")

        let responseIdField = edit.metadataFields.first { $0.fieldName == "noto.ai.parentResponseId" }
        #expect(responseIdField?.fieldValue == responseId.uuidString)
    }

    @Test @MainActor func updateEditStatus() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let conv = AIChatBlockStore.createConversation(context: context, dirtyTracker: tracker)
        let proposal = EditProposal(operations: [], summary: "test")
        let edit = AIChatBlockStore.addSuggestedEdit(
            proposal: proposal,
            parentResponseId: UUID(),
            to: conv,
            context: context,
            dirtyTracker: tracker
        )

        AIChatBlockStore.updateEditStatus(edit, status: .accepted, context: context, dirtyTracker: tracker)

        let ext = edit.decodeExtension(SuggestedEditExtension.self)
        #expect(ext?.status == .accepted)

        let statusField = edit.metadataFields.first { $0.fieldName == AIChatMetadataKeys.status }
        #expect(statusField?.fieldValue == "accepted")
    }

    @Test @MainActor func updateEditStatusToDismissed() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let conv = AIChatBlockStore.createConversation(context: context, dirtyTracker: tracker)
        let proposal = EditProposal(operations: [], summary: "test")
        let edit = AIChatBlockStore.addSuggestedEdit(
            proposal: proposal,
            parentResponseId: UUID(),
            to: conv,
            context: context,
            dirtyTracker: tracker
        )

        AIChatBlockStore.updateEditStatus(edit, status: .dismissed, context: context, dirtyTracker: tracker)

        let ext = edit.decodeExtension(SuggestedEditExtension.self)
        #expect(ext?.status == .dismissed)
    }

    @Test @MainActor func fetchConversations() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let conv1 = AIChatBlockStore.createConversation(context: context, dirtyTracker: tracker)
        let conv2 = AIChatBlockStore.createConversation(context: context, dirtyTracker: tracker)
        try context.save()

        let conversations = AIChatBlockStore.fetchConversations(context: context)
        #expect(conversations.count == 2)
        #expect(conversations[0].id == conv1.id)
        #expect(conversations[1].id == conv2.id)
    }

    @Test @MainActor func fetchMessagesSortedBySortOrder() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let conv = AIChatBlockStore.createConversation(context: context, dirtyTracker: tracker)
        let msg1 = AIChatBlockStore.addUserMessage(content: "first", to: conv, context: context, dirtyTracker: tracker)
        let msg2 = AIChatBlockStore.addAIResponse(text: "response", to: conv, context: context, dirtyTracker: tracker)
        let msg3 = AIChatBlockStore.addUserMessage(content: "second", to: conv, context: context, dirtyTracker: tracker)

        let messages = AIChatBlockStore.fetchMessages(for: conv)
        #expect(messages.count == 3)
        #expect(messages[0].id == msg1.id)
        #expect(messages[1].id == msg2.id)
        #expect(messages[2].id == msg3.id)
        #expect(messages[0].sortOrder < messages[1].sortOrder)
        #expect(messages[1].sortOrder < messages[2].sortOrder)
    }

    @Test @MainActor func dirtyTrackerMarkedForAllMutations() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        #expect(tracker.hasDirtyBlocks == false)

        _ = AIChatBlockStore.createConversation(context: context, dirtyTracker: tracker)
        #expect(tracker.hasDirtyBlocks == true)
    }

    @Test @MainActor func conversationTreeStructure() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let conv = AIChatBlockStore.createConversation(context: context, dirtyTracker: tracker)
        let userMsg = AIChatBlockStore.addUserMessage(content: "hello", to: conv, context: context, dirtyTracker: tracker)
        let aiResp = AIChatBlockStore.addAIResponse(text: "hi there", to: conv, context: context, dirtyTracker: tracker)

        // Verify tree: root -> conv -> [userMsg, aiResp]
        let root = conv.parent!
        #expect(root.content == "AI Chat")
        #expect(root.parent == nil)
        #expect(conv.parent?.id == root.id)
        #expect(userMsg.parent?.id == conv.id)
        #expect(aiResp.parent?.id == conv.id)

        // Verify depths
        #expect(root.depth == 0)
        #expect(conv.depth == 1)
        #expect(userMsg.depth == 2)
        #expect(aiResp.depth == 2)
    }
}
