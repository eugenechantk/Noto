//
//  AIEditApplierTests.swift
//  NotoAIChatTests
//

import Foundation
import SwiftData
import Testing
import NotoModels
import NotoCore
import NotoDirtyTracker
@testable import NotoAIChat

@MainActor
private func createTestDirtyTracker() async -> DirtyTracker {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = DirtyStore(directory: tmpDir)
    await store.createTablesIfNeeded()
    return DirtyTracker(dirtyStore: store, idleDelay: 60)
}

@Suite("AIEditApplier")
struct AIEditApplierTests {

    @Test @MainActor func addBlockCreatesChild() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let parent = Block(content: "Parent", parent: nil, sortOrder: 1.0)
        context.insert(parent)
        try context.save()

        let proposal = EditProposal(
            operations: [.addBlock(AddBlockOp(parentId: parent.id, content: "New child"))],
            summary: "Add a child"
        )

        let result = try AIEditApplier.apply(
            proposal: proposal,
            proposalCreatedAt: Date(),
            context: context,
            dirtyTracker: tracker
        )

        #expect(result.appliedOps.count == 1)
        let children = parent.sortedChildren
        #expect(children.count == 1)
        #expect(children.first?.content == "New child")
    }

    @Test @MainActor func updateBlockChangesContent() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let block = Block(content: "Old content", parent: nil, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        let proposal = EditProposal(
            operations: [.updateBlock(UpdateBlockOp(blockId: block.id, newContent: "New content"))],
            summary: "Update block"
        )

        let result = try AIEditApplier.apply(
            proposal: proposal,
            proposalCreatedAt: Date(),
            context: context,
            dirtyTracker: tracker
        )

        #expect(result.appliedOps.count == 1)
        #expect(block.content == "New content")
    }

    @Test @MainActor func comboAddAndUpdate() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let parent = Block(content: "Parent", parent: nil, sortOrder: 1.0)
        let existing = Block(content: "Existing", parent: parent, sortOrder: 1.0)
        context.insert(parent)
        context.insert(existing)
        try context.save()

        let proposal = EditProposal(
            operations: [
                .addBlock(AddBlockOp(parentId: parent.id, content: "Added")),
                .updateBlock(UpdateBlockOp(blockId: existing.id, newContent: "Updated")),
            ],
            summary: "Add and update"
        )

        let result = try AIEditApplier.apply(
            proposal: proposal,
            proposalCreatedAt: Date(),
            context: context,
            dirtyTracker: tracker
        )

        #expect(result.appliedOps.count == 2)
        #expect(existing.content == "Updated")
        #expect(parent.sortedChildren.count == 2)
    }

    @Test @MainActor func staleBlockThrows() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let block = Block(content: "Content", parent: nil, sortOrder: 1.0)
        context.insert(block)
        try context.save()

        // Proposal was created before block was modified
        let proposalTime = Date(timeIntervalSinceNow: -60)
        block.updatedAt = Date() // block was modified after proposal

        let proposal = EditProposal(
            operations: [.updateBlock(UpdateBlockOp(blockId: block.id, newContent: "New"))],
            summary: "Stale"
        )

        #expect(throws: EditApplyError.self) {
            try AIEditApplier.apply(
                proposal: proposal,
                proposalCreatedAt: proposalTime,
                context: context,
                dirtyTracker: tracker
            )
        }
    }

    @Test @MainActor func notEditableThrows() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let block = Block(
            content: "Protected",
            parent: nil,
            sortOrder: 1.0,
            isContentEditableByUser: false
        )
        context.insert(block)
        try context.save()

        let proposal = EditProposal(
            operations: [.updateBlock(UpdateBlockOp(blockId: block.id, newContent: "Nope"))],
            summary: "Not editable"
        )

        #expect(throws: EditApplyError.self) {
            try AIEditApplier.apply(
                proposal: proposal,
                proposalCreatedAt: Date(),
                context: context,
                dirtyTracker: tracker
            )
        }
    }

    @Test @MainActor func blockNotFoundThrows() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let fakeId = UUID()
        let proposal = EditProposal(
            operations: [.updateBlock(UpdateBlockOp(blockId: fakeId, newContent: "Gone"))],
            summary: "Missing"
        )

        #expect(throws: EditApplyError.blockNotFound(fakeId)) {
            try AIEditApplier.apply(
                proposal: proposal,
                proposalCreatedAt: Date(),
                context: context,
                dirtyTracker: tracker
            )
        }
    }

    @Test @MainActor func allOrNothingSemantics() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let parent = Block(content: "Parent", parent: nil, sortOrder: 1.0)
        context.insert(parent)
        try context.save()

        let fakeId = UUID()
        let proposal = EditProposal(
            operations: [
                .addBlock(AddBlockOp(parentId: parent.id, content: "Should not exist")),
                .updateBlock(UpdateBlockOp(blockId: fakeId, newContent: "Missing")),
            ],
            summary: "Partial fail"
        )

        #expect(throws: EditApplyError.self) {
            try AIEditApplier.apply(
                proposal: proposal,
                proposalCreatedAt: Date(),
                context: context,
                dirtyTracker: tracker
            )
        }

        // First op should NOT have been applied
        #expect(parent.sortedChildren.isEmpty)
    }

    @Test @MainActor func acceptFlowUpdatesStatus() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let conversation = AIChatBlockStore.createConversation(
            context: context, dirtyTracker: tracker
        )

        let proposal = EditProposal(
            operations: [],
            summary: "Empty edit"
        )

        let editBlock = AIChatBlockStore.addSuggestedEdit(
            proposal: proposal,
            parentResponseId: UUID(),
            to: conversation,
            context: context,
            dirtyTracker: tracker
        )
        try context.save()

        AIChatBlockStore.updateEditStatus(
            editBlock, status: .accepted, context: context, dirtyTracker: tracker
        )

        let ext = editBlock.decodeExtension(SuggestedEditExtension.self)
        #expect(ext?.status == .accepted)
    }

    @Test @MainActor func dismissFlowUpdatesStatus() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let tracker = await createTestDirtyTracker()

        let conversation = AIChatBlockStore.createConversation(
            context: context, dirtyTracker: tracker
        )

        let proposal = EditProposal(
            operations: [],
            summary: "Empty edit"
        )

        let editBlock = AIChatBlockStore.addSuggestedEdit(
            proposal: proposal,
            parentResponseId: UUID(),
            to: conversation,
            context: context,
            dirtyTracker: tracker
        )
        try context.save()

        AIChatBlockStore.updateEditStatus(
            editBlock, status: .dismissed, context: context, dirtyTracker: tracker
        )

        let ext = editBlock.decodeExtension(SuggestedEditExtension.self)
        #expect(ext?.status == .dismissed)
    }
}
