//
//  AIEditApplier.swift
//  NotoAIChat
//
//  Transactional applier for AI-suggested edit proposals.
//  Validates ALL operations before executing ANY (all-or-nothing semantics).
//

import Foundation
import SwiftData
import os.log
import NotoModels
import NotoCore
import NotoDirtyTracker

private let logger = Logger(subsystem: "com.noto", category: "AIEditApplier")

// MARK: - Error

public enum EditApplyError: Error, Equatable {
    case blockNotFound(UUID)
    case blockNotEditable(UUID)
    case staleBlock(blockId: UUID, blockUpdatedAt: Date, proposalCreatedAt: Date)
    case invalidParentChild(parentId: UUID, afterBlockId: UUID?)
}

// MARK: - Result Types

public enum AppliedOp: Sendable {
    case added(UUID)
    case updated(blockId: UUID, oldContent: String)
}

public struct ApplyResult: Sendable {
    public let appliedOps: [AppliedOp]
    public let appliedAt: Date

    public init(appliedOps: [AppliedOp], appliedAt: Date) {
        self.appliedOps = appliedOps
        self.appliedAt = appliedAt
    }
}

// MARK: - AIEditApplier

public struct AIEditApplier {

    /// Apply an edit proposal transactionally.
    /// Phase 1: Validate all operations. Phase 2: Execute all operations.
    /// If any validation fails, no operations are executed.
    @MainActor
    public static func apply(
        proposal: EditProposal,
        proposalCreatedAt: Date,
        context: ModelContext,
        dirtyTracker: DirtyTracker
    ) throws -> ApplyResult {
        // Phase 1 — Validate ALL operations
        var validatedOps: [ValidatedOp] = []

        for operation in proposal.operations {
            switch operation {
            case .addBlock(let op):
                let parent = try fetchBlock(op.parentId, context: context)
                var afterSibling: Block?
                if let afterId = op.afterBlockId {
                    guard let sibling = try? fetchBlock(afterId, context: context),
                          sibling.parent?.id == parent.id else {
                        throw EditApplyError.invalidParentChild(parentId: op.parentId, afterBlockId: afterId)
                    }
                    afterSibling = sibling
                }
                validatedOps.append(.add(parent: parent, afterSibling: afterSibling, content: op.content))

            case .updateBlock(let op):
                let block = try fetchBlock(op.blockId, context: context)
                guard block.isContentEditableByUser else {
                    throw EditApplyError.blockNotEditable(op.blockId)
                }
                if block.updatedAt > proposalCreatedAt {
                    throw EditApplyError.staleBlock(
                        blockId: op.blockId,
                        blockUpdatedAt: block.updatedAt,
                        proposalCreatedAt: proposalCreatedAt
                    )
                }
                validatedOps.append(.update(block: block, newContent: op.newContent))
            }
        }

        // Phase 2 — Execute ALL operations
        var appliedOps: [AppliedOp] = []

        for validated in validatedOps {
            switch validated {
            case .add(let parent, let afterSibling, let content):
                let newBlock = BlockBuilder.addBlock(
                    content: content,
                    parent: parent,
                    afterSibling: afterSibling,
                    context: context
                )
                dirtyTracker.markDirty(newBlock.id)
                appliedOps.append(.added(newBlock.id))
                logger.debug("[apply] added block \(newBlock.id) under \(parent.id)")

            case .update(let block, let newContent):
                let oldContent = block.content
                try BlockBuilder.updateBlock(block, newContent: newContent)
                dirtyTracker.markDirty(block.id)
                appliedOps.append(.updated(blockId: block.id, oldContent: oldContent))
                logger.debug("[apply] updated block \(block.id)")
            }
        }

        let result = ApplyResult(appliedOps: appliedOps, appliedAt: Date())
        logger.debug("[apply] applied \(appliedOps.count) operations")
        return result
    }

    // MARK: - Private

    private enum ValidatedOp {
        case add(parent: Block, afterSibling: Block?, content: String)
        case update(block: Block, newContent: String)
    }

    @MainActor
    private static func fetchBlock(_ id: UUID, context: ModelContext) throws -> Block {
        let descriptor = FetchDescriptor<Block>(predicate: #Predicate { $0.id == id })
        guard let block = try context.fetch(descriptor).first else {
            throw EditApplyError.blockNotFound(id)
        }
        return block
    }
}
