//
//  IndexReconciler.swift
//  NotoFTS5
//
//  Launch-time safety net that catches blocks missed by dirty tracking
//  (e.g., app force-killed before flush).
//

import Foundation
import SwiftData
import NotoModels
import NotoCore
import NotoDirtyTracker
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "IndexReconciler")

public struct IndexReconciler {
    public let fts5Database: FTS5Database
    public let dirtyStore: DirtyStore
    public let modelContext: ModelContext

    public init(fts5Database: FTS5Database, dirtyStore: DirtyStore, modelContext: ModelContext) {
        self.fts5Database = fts5Database
        self.dirtyStore = dirtyStore
        self.modelContext = modelContext
    }

    /// Checks the reconciliation state and repairs the index if needed.
    ///
    /// - First launch (no timestamp): triggers a full rebuild
    /// - Otherwise: finds blocks updated since last reconciliation and marks them dirty
    public func reconcileIfNeeded() async {
        let timestampString = await dirtyStore.getMetadata(key: "lastFullReconciliationAt")

        // First launch — no timestamp means we've never indexed
        guard let timestampString = timestampString else {
            logger.info("First launch detected — triggering full rebuild")
            let indexer = FTS5Indexer(fts5Database: fts5Database, dirtyStore: dirtyStore, modelContext: modelContext)
            await indexer.rebuildAll()
            return
        }

        // Parse the stored timestamp
        guard let lastReconciliation = ISO8601DateFormatter().date(from: timestampString) else {
            logger.error("Invalid lastFullReconciliationAt timestamp: \(timestampString) — triggering rebuild")
            let indexer = FTS5Indexer(fts5Database: fts5Database, dirtyStore: dirtyStore, modelContext: modelContext)
            await indexer.rebuildAll()
            return
        }

        // Check if there are pending dirty blocks (from a previous incomplete flush)
        let pendingDirty = await dirtyStore.dirtyCount()

        // Find blocks updated since last reconciliation
        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate<Block> { $0.updatedAt > lastReconciliation }
        )

        let missedBlocks: [Block]
        do {
            missedBlocks = try modelContext.fetch(descriptor)
        } catch {
            logger.error("reconcileIfNeeded fetch missed blocks failed: \(error)")
            return
        }

        if missedBlocks.isEmpty && pendingDirty == 0 {
            // Everything is up to date — just update the timestamp
            let timestamp = ISO8601DateFormatter().string(from: Date())
            await dirtyStore.setMetadata(key: "lastFullReconciliationAt", value: timestamp)
            logger.info("Reconciliation check: index is up to date")
            return
        }

        // Mark missed blocks as dirty
        if !missedBlocks.isEmpty {
            let missedIds = missedBlocks.map { $0.id }
            await dirtyStore.markDirtyBatch(blockIds: missedIds, operation: .upsert)
            logger.info("Reconciliation found \(missedBlocks.count) missed blocks")
        }

        // Flush all dirty blocks (both previously pending and newly discovered)
        let indexer = FTS5Indexer(fts5Database: fts5Database, dirtyStore: dirtyStore, modelContext: modelContext)
        await indexer.flushAll()

        logger.info("Reconciliation complete")
    }
}
