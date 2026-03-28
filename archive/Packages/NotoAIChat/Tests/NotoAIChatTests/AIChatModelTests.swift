//
//  AIChatModelTests.swift
//  NotoAIChatTests
//

import Foundation
import SwiftData
import Testing
import NotoModels
@testable import NotoAIChat

// MARK: - ChatBlockRole

@Suite("ChatBlockRole")
struct ChatBlockRoleTests {
    @Test func rawValues() {
        #expect(ChatBlockRole.conversation.rawValue == "conversation")
        #expect(ChatBlockRole.userMessage.rawValue == "userMessage")
        #expect(ChatBlockRole.aiResponse.rawValue == "aiResponse")
        #expect(ChatBlockRole.suggestedEdit.rawValue == "suggestedEdit")
    }

    @Test func roundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for role in [ChatBlockRole.conversation, .userMessage, .aiResponse, .suggestedEdit] {
            let data = try encoder.encode(role)
            let decoded = try decoder.decode(ChatBlockRole.self, from: data)
            #expect(decoded == role)
        }
    }
}

// MARK: - ConversationExtension

@Suite("ConversationExtension")
struct ConversationExtensionTests {
    @Test func roundTrip() throws {
        let noteId = UUID()
        let ext = ConversationExtension(createdAt: Date(timeIntervalSince1970: 1000), noteContextBlockId: noteId)
        let data = try JSONEncoder().encode(ext)
        let decoded = try JSONDecoder().decode(ConversationExtension.self, from: data)
        #expect(decoded.role == .conversation)
        #expect(decoded.noteContextBlockId == noteId)
        #expect(decoded.createdAt == ext.createdAt)
    }

    @Test func nilNoteContext() throws {
        let ext = ConversationExtension()
        let data = try JSONEncoder().encode(ext)
        let decoded = try JSONDecoder().decode(ConversationExtension.self, from: data)
        #expect(decoded.noteContextBlockId == nil)
    }
}

// MARK: - UserMessageExtension

@Suite("UserMessageExtension")
struct UserMessageExtensionTests {
    @Test func roundTrip() throws {
        let ext = UserMessageExtension(turnIndex: 3)
        let data = try JSONEncoder().encode(ext)
        let decoded = try JSONDecoder().decode(UserMessageExtension.self, from: data)
        #expect(decoded.role == .userMessage)
        #expect(decoded.turnIndex == 3)
    }
}

// MARK: - AIResponseExtension

@Suite("AIResponseExtension")
struct AIResponseExtensionTests {
    @Test func roundTripWithReferencesAndToolCalls() throws {
        let ref = BlockReference(blockId: UUID(), content: "some note content", relevanceScore: 0.95)
        let tool = ToolCallRecord(toolName: "search_notes", input: "{\"query\":\"test\"}", output: "[{\"id\":\"abc\"}]")
        let ext = AIResponseExtension(turnIndex: 1, references: [ref], toolCalls: [tool])
        let data = try JSONEncoder().encode(ext)
        let decoded = try JSONDecoder().decode(AIResponseExtension.self, from: data)
        #expect(decoded.role == .aiResponse)
        #expect(decoded.turnIndex == 1)
        #expect(decoded.references.count == 1)
        #expect(decoded.references[0].blockId == ref.blockId)
        #expect(decoded.references[0].relevanceScore == 0.95)
        #expect(decoded.toolCalls.count == 1)
        #expect(decoded.toolCalls[0].toolName == "search_notes")
    }

    @Test func emptyReferencesAndToolCalls() throws {
        let ext = AIResponseExtension(turnIndex: 0)
        let data = try JSONEncoder().encode(ext)
        let decoded = try JSONDecoder().decode(AIResponseExtension.self, from: data)
        #expect(decoded.references.isEmpty)
        #expect(decoded.toolCalls.isEmpty)
    }
}

// MARK: - SuggestedEditExtension

@Suite("SuggestedEditExtension")
struct SuggestedEditExtensionTests {
    @Test func roundTrip() throws {
        let addOp = EditOperation.addBlock(AddBlockOp(parentId: UUID(), afterBlockId: UUID(), content: "new bullet"))
        let updateOp = EditOperation.updateBlock(UpdateBlockOp(blockId: UUID(), newContent: "updated text"))
        let proposal = EditProposal(operations: [addOp, updateOp], summary: "Add and update blocks")
        let ext = SuggestedEditExtension(proposal: proposal, status: .pending)
        let data = try JSONEncoder().encode(ext)
        let decoded = try JSONDecoder().decode(SuggestedEditExtension.self, from: data)
        #expect(decoded.role == .suggestedEdit)
        #expect(decoded.status == .pending)
        #expect(decoded.proposal.operations.count == 2)
        #expect(decoded.proposal.summary == "Add and update blocks")
    }
}

// MARK: - EditOperation

@Suite("EditOperation")
struct EditOperationTests {
    @Test func addBlockRoundTrip() throws {
        let parentId = UUID()
        let afterId = UUID()
        let op = EditOperation.addBlock(AddBlockOp(parentId: parentId, afterBlockId: afterId, content: "hello"))
        let data = try JSONEncoder().encode(op)
        let decoded = try JSONDecoder().decode(EditOperation.self, from: data)
        if case .addBlock(let add) = decoded {
            #expect(add.parentId == parentId)
            #expect(add.afterBlockId == afterId)
            #expect(add.content == "hello")
        } else {
            Issue.record("Expected addBlock case")
        }
    }

    @Test func updateBlockRoundTrip() throws {
        let blockId = UUID()
        let op = EditOperation.updateBlock(UpdateBlockOp(blockId: blockId, newContent: "revised"))
        let data = try JSONEncoder().encode(op)
        let decoded = try JSONDecoder().decode(EditOperation.self, from: data)
        if case .updateBlock(let update) = decoded {
            #expect(update.blockId == blockId)
            #expect(update.newContent == "revised")
        } else {
            Issue.record("Expected updateBlock case")
        }
    }

    @Test func addBlockWithNilAfterBlockId() throws {
        let op = EditOperation.addBlock(AddBlockOp(parentId: UUID(), content: "appended"))
        let data = try JSONEncoder().encode(op)
        let decoded = try JSONDecoder().decode(EditOperation.self, from: data)
        if case .addBlock(let add) = decoded {
            #expect(add.afterBlockId == nil)
        } else {
            Issue.record("Expected addBlock case")
        }
    }
}

// MARK: - EditStatus

@Suite("EditStatus")
struct EditStatusTests {
    @Test func rawValues() {
        #expect(EditStatus.pending.rawValue == "pending")
        #expect(EditStatus.accepted.rawValue == "accepted")
        #expect(EditStatus.dismissed.rawValue == "dismissed")
    }

    @Test func roundTrip() throws {
        for status in [EditStatus.pending, .accepted, .dismissed] {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(EditStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}

// MARK: - BlockReference

@Suite("BlockReference")
struct BlockReferenceTests {
    @Test func roundTrip() throws {
        let ref = BlockReference(blockId: UUID(), content: "test content", relevanceScore: 0.85)
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(BlockReference.self, from: data)
        #expect(decoded.blockId == ref.blockId)
        #expect(decoded.content == "test content")
        #expect(decoded.relevanceScore == 0.85)
    }

    @Test func nilRelevanceScore() throws {
        let ref = BlockReference(blockId: UUID(), content: "test")
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(BlockReference.self, from: data)
        #expect(decoded.relevanceScore == nil)
    }
}

// MARK: - ToolCallRecord

@Suite("ToolCallRecord")
struct ToolCallRecordTests {
    @Test func roundTrip() throws {
        let record = ToolCallRecord(toolName: "search_notes", input: "{\"query\":\"hello\"}", output: "[]")
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ToolCallRecord.self, from: data)
        #expect(decoded.toolName == "search_notes")
        #expect(decoded.input == "{\"query\":\"hello\"}")
        #expect(decoded.output == "[]")
    }
}

// MARK: - Block Extension Helpers

@Suite("Block+ExtensionCoding")
struct BlockExtensionCodingTests {
    @Test func encodeAndDecode() throws {
        let ext = UserMessageExtension(turnIndex: 5)
        let data = Block.encodeExtension(ext)
        #expect(data != nil)

        let block = Block(content: "test message", extensionData: data)
        let decoded = block.decodeExtension(UserMessageExtension.self)
        #expect(decoded != nil)
        #expect(decoded?.role == .userMessage)
        #expect(decoded?.turnIndex == 5)
    }

    @Test func decodeNilExtensionData() {
        let block = Block(content: "no extension")
        let decoded = block.decodeExtension(UserMessageExtension.self)
        #expect(decoded == nil)
    }

    @Test func decodeWrongType() {
        let ext = UserMessageExtension(turnIndex: 1)
        let data = Block.encodeExtension(ext)
        let block = Block(content: "user msg", extensionData: data)
        // Decoding as ConversationExtension should fail gracefully
        // (role mismatch won't cause a crash, but createdAt field is missing)
        let decoded = block.decodeExtension(ConversationExtension.self)
        // This will be nil because ConversationExtension has a createdAt field not present in UserMessageExtension
        #expect(decoded == nil)
    }
}

// MARK: - MetadataKeys

@Suite("AIChatMetadataKeys")
struct MetadataKeysTests {
    @Test func keyValues() {
        #expect(AIChatMetadataKeys.role == "noto.ai.role")
        #expect(AIChatMetadataKeys.status == "noto.ai.status")
        #expect(AIChatMetadataKeys.turnIndex == "noto.ai.turnIndex")
    }
}
