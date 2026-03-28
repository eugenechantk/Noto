//
//  FTS5Indexer.swift
//  NotoFTS5
//
//  Flushes dirty blocks to the FTS5 index and provides full rebuild.
//

import Foundation
import SwiftData
import NotoModels
import NotoCore
import NotoDirtyTracker
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "FTS5Indexer")

public struct FTS5Indexer {
    public let fts5Database: FTS5Database
    public let dirtyStore: DirtyStore
    public let modelContext: ModelContext

    public init(fts5Database: FTS5Database, dirtyStore: DirtyStore, modelContext: ModelContext) {
        self.fts5Database = fts5Database
        self.dirtyStore = dirtyStore
        self.modelContext = modelContext
    }

    /// Processes all dirty blocks in batches and updates the FTS5 index.
    ///
    /// For each dirty entry:
    /// - `upsert`: fetches Block from SwiftData, strips markdown, writes to FTS5
    /// - `delete`: removes the block from FTS5
    public func flushAll() async {
        var totalProcessed = 0

        while true {
            let batch = await dirtyStore.fetchDirtyBatch(limit: 50)
            if batch.isEmpty { break }

            await processBatch(batch)
            let processedIds = batch.map { $0.blockId }
            await dirtyStore.removeDirty(blockIds: processedIds)
            totalProcessed += processedIds.count
        }

        // Update reconciliation timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())
        await dirtyStore.setMetadata(key: "lastFullReconciliationAt", value: timestamp)

        if totalProcessed > 0 {
            logger.info("flushAll processed \(totalProcessed) dirty blocks")
        }
    }

    /// Processes a single batch of dirty entries into the FTS5 index.
    /// Used by SearchService to coordinate FTS5 and embedding indexing from the same batch.
    public func processBatch(_ batch: [(blockId: UUID, operation: DirtyOperation)]) async {
        for entry in batch {
            switch entry.operation {
            case .upsert:
                let blockId = entry.blockId
                let descriptor = FetchDescriptor<Block>(
                    predicate: #Predicate<Block> { $0.id == blockId }
                )
                do {
                    let blocks = try modelContext.fetch(descriptor)
                    if let block = blocks.first {
                        let plainText = PlainTextExtractor.plainText(from: block.content)
                        await fts5Database.upsertBlock(blockId: block.id, content: plainText)
                    } else {
                        await fts5Database.deleteBlock(blockId: blockId)
                    }
                } catch {
                    logger.error("processBatch fetch block \(blockId) failed: \(error)")
                }
            case .delete:
                await fts5Database.deleteBlock(blockId: entry.blockId)
            }
        }
    }

    /// Drops the FTS5 table and rebuilds the entire index from SwiftData.
    public func rebuildAll() async {
        logger.info("Starting full FTS5 index rebuild")

        // 1. Drop and recreate block_fts
        await fts5Database.recreateBlockFTS()

        // 2. Fetch all non-archived blocks from SwiftData
        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate<Block> { $0.isArchived == false }
        )

        let allBlocks: [Block]
        do {
            allBlocks = try modelContext.fetch(descriptor)
        } catch {
            logger.error("rebuildAll fetch blocks failed: \(error)")
            return
        }

        // 3. Index in batches of 100
        let batchSize = 100
        for batchStart in stride(from: 0, to: allBlocks.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, allBlocks.count)
            let batch = allBlocks[batchStart..<batchEnd]

            let entries = batch.map { block in
                (blockId: block.id, content: PlainTextExtractor.plainText(from: block.content))
            }
            await fts5Database.upsertBlockBatch(blocks: entries)
        }

        // 4. Clear dirty_blocks
        await dirtyStore.clearDirtyBlocks()

        // 5. Update timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())
        await dirtyStore.setMetadata(key: "lastFullReconciliationAt", value: timestamp)

        logger.info("Full FTS5 index rebuild complete: \(allBlocks.count) blocks indexed")
    }
}
