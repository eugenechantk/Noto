//
//  AIChatRootService.swift
//  NotoAIChat
//

import Foundation
import SwiftData
import os.log
import NotoModels

private let logger = Logger(subsystem: "com.noto", category: "AIChatRootService")

public struct AIChatRootService {

    /// Ensure the "AI Chat" root block exists. Creates it on first launch.
    @MainActor
    public static func ensureRoot(context: ModelContext) -> Block {
        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate<Block> { block in
                block.parent == nil && block.content == "AI Chat" && !block.isArchived
            }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let root = Block(
            content: "AI Chat",
            sortOrder: Double.leastNormalMagnitude + 1,
            isDeletable: false,
            isContentEditableByUser: false,
            isReorderable: false,
            isMovable: false
        )
        context.insert(root)
        logger.info("Created AI Chat root block")
        return root
    }
}
