//
//  DirtyTracker.swift
//  NotoDirtyTracker
//
//  In-memory dirty block tracking with idle timer and flush lifecycle.
//  Shared between keyword and semantic indexing pipelines.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.noto", category: "DirtyTracker")

@MainActor
public class DirtyTracker: ObservableObject {

    private let dirtyStore: DirtyStore

    /// Blocks with content changes -- in-memory only until flush.
    private var changedBlockIds: Set<UUID> = []

    /// Idle timer that triggers a flush after the idle delay.
    private var idleTimer: Task<Void, Never>?

    /// Duration (in seconds) before the idle timer fires.
    private let idleDelay: TimeInterval

    // MARK: - Init

    public init(dirtyStore: DirtyStore, idleDelay: TimeInterval = 5.0) {
        self.dirtyStore = dirtyStore
        self.idleDelay = idleDelay
    }

    // MARK: - Public API

    /// Whether there are any dirty blocks waiting to be flushed.
    public var hasDirtyBlocks: Bool {
        !changedBlockIds.isEmpty
    }

    /// Marks a block as dirty (content changed). Does NOT write to SQLite.
    /// Resets the idle timer on each call.
    public func markDirty(_ blockId: UUID) {
        changedBlockIds.insert(blockId)
        resetIdleTimer()
        logger.debug("markDirty: \(blockId.uuidString.prefix(8))... (total: \(self.changedBlockIds.count))")
    }

    /// Marks a block as deleted. Writes to dirty_blocks immediately.
    public func markDeleted(_ blockId: UUID) {
        changedBlockIds.remove(blockId)
        logger.debug("markDeleted: \(blockId.uuidString.prefix(8))...")
        Task {
            await dirtyStore.markDirty(blockId: blockId, operation: .delete)
        }
    }

    /// Persists all in-memory changed block IDs to the dirty_blocks table,
    /// then clears the in-memory set.
    public func flush() async {
        cancelIdleTimer()

        let batch = changedBlockIds
        changedBlockIds.removeAll()

        guard !batch.isEmpty else { return }

        logger.debug("Flushing \(batch.count) dirty blocks")
        await dirtyStore.markDirtyBatch(blockIds: Array(batch), operation: .upsert)
    }

    // MARK: - Idle Timer

    /// Cancels the current timer and starts a new one.
    public func resetIdleTimer() {
        cancelIdleTimer()
        idleTimer = Task { [weak self, idleDelay] in
            do {
                try await Task.sleep(nanoseconds: UInt64(idleDelay * 1_000_000_000))
                await self?.flush()
            } catch {
                // Task was cancelled -- nothing to do
            }
        }
    }

    /// Cancels the idle timer without flushing.
    public func cancelIdleTimer() {
        idleTimer?.cancel()
        idleTimer = nil
    }
}
