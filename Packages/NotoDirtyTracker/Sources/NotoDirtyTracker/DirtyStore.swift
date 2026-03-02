//
//  DirtyStore.swift
//  NotoDirtyTracker
//
//  Actor wrapping the SQLite C API. Manages dirty.sqlite with tables:
//  dirty_blocks, index_metadata.
//

import Foundation
import SQLite3
import os.log

private let logger = Logger(subsystem: "com.noto", category: "DirtyStore")

/// Persistent store for dirty block tracking and index metadata.
/// Owns its own `dirty.sqlite` file, shared between keyword and semantic pipelines.
public actor DirtyStore {

    private var db: OpaquePointer?
    private let dbURL: URL

    // MARK: - Lifecycle

    /// Opens or creates dirty.sqlite in the given directory.
    public init(directory: URL) {
        self.dbURL = directory.appendingPathComponent("dirty.sqlite")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create directory \(directory.path): \(error)")
        }

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        var dbPointer: OpaquePointer?
        let rc = sqlite3_open_v2(dbURL.path, &dbPointer, flags, nil)
        if rc == SQLITE_OK {
            self.db = dbPointer
            logger.info("Opened dirty store at \(self.dbURL.path)")
        } else {
            logger.error("Failed to open dirty store: \(String(cString: sqlite3_errmsg(dbPointer)))")
            self.db = nil
        }
    }

    /// Creates all required tables if they don't exist.
    public func createTablesIfNeeded() {
        guard let db = db else { return }

        let statements = [
            """
            CREATE TABLE IF NOT EXISTS dirty_blocks (
                block_id TEXT PRIMARY KEY,
                operation TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS index_metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """,
        ]

        for sql in statements {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) != SQLITE_DONE {
                    logger.error("Failed to execute DDL: \(String(cString: sqlite3_errmsg(db)))")
                }
            } else {
                logger.error("Failed to prepare DDL: \(String(cString: sqlite3_errmsg(db)))")
            }
            sqlite3_finalize(stmt)
        }

        logger.info("Dirty store tables created/verified")
    }

    /// Closes the database connection.
    public func close() {
        guard let db = db else { return }
        sqlite3_close(db)
        self.db = nil
        logger.info("Closed dirty store")
    }

    // MARK: - Dirty Tracking

    /// Marks a single block as dirty with the given operation.
    public func markDirty(blockId: UUID, operation: DirtyOperation) {
        guard let db = db else { return }
        let sql = "INSERT OR REPLACE INTO dirty_blocks (block_id, operation) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("markDirty prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let idString = blockId.uuidString
        sqlite3_bind_text(stmt, 1, (idString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (operation.rawValue as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            logger.error("markDirty step failed: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    /// Marks multiple blocks as dirty in a single transaction.
    public func markDirtyBatch(blockIds: [UUID], operation: DirtyOperation) {
        guard let db = db, !blockIds.isEmpty else { return }

        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

        let sql = "INSERT OR REPLACE INTO dirty_blocks (block_id, operation) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("markDirtyBatch prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }

        for blockId in blockIds {
            sqlite3_reset(stmt)
            let idString = blockId.uuidString
            sqlite3_bind_text(stmt, 1, (idString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (operation.rawValue as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                logger.error("markDirtyBatch step failed: \(String(cString: sqlite3_errmsg(db)))")
            }
        }

        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }

    /// Fetches a batch of dirty block records.
    public func fetchDirtyBatch(limit: Int) -> [(blockId: UUID, operation: DirtyOperation)] {
        guard let db = db else { return [] }
        let sql = "SELECT block_id, operation FROM dirty_blocks LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("fetchDirtyBatch prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [(UUID, DirtyOperation)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idCStr = sqlite3_column_text(stmt, 0),
                  let opCStr = sqlite3_column_text(stmt, 1),
                  let uuid = UUID(uuidString: String(cString: idCStr)),
                  let op = DirtyOperation(rawValue: String(cString: opCStr)) else {
                continue
            }
            results.append((uuid, op))
        }
        return results
    }

    /// Removes the given block IDs from the dirty_blocks table.
    public func removeDirty(blockIds: [UUID]) {
        guard let db = db, !blockIds.isEmpty else { return }

        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

        let sql = "DELETE FROM dirty_blocks WHERE block_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("removeDirty prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }

        for blockId in blockIds {
            sqlite3_reset(stmt)
            let idString = blockId.uuidString
            sqlite3_bind_text(stmt, 1, (idString as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                logger.error("removeDirty step failed: \(String(cString: sqlite3_errmsg(db)))")
            }
        }

        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }

    /// Returns the total number of entries in the dirty_blocks table.
    public func dirtyCount() -> Int {
        guard let db = db else { return 0 }
        let sql = "SELECT COUNT(*) FROM dirty_blocks;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    /// Deletes all entries from the dirty_blocks table.
    public func clearDirtyBlocks() {
        guard let db = db else { return }
        let sql = "DELETE FROM dirty_blocks;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("clearDirtyBlocks prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) != SQLITE_DONE {
            logger.error("clearDirtyBlocks step failed: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    // MARK: - Metadata

    /// Returns the value for a metadata key, or nil if not found.
    public func getMetadata(key: String) -> String? {
        guard let db = db else { return nil }
        let sql = "SELECT value FROM index_metadata WHERE key = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            guard let valCStr = sqlite3_column_text(stmt, 0) else { return nil }
            return String(cString: valCStr)
        }
        return nil
    }

    /// Sets a metadata key-value pair (insert or replace).
    public func setMetadata(key: String, value: String) {
        guard let db = db else { return }
        let sql = "INSERT OR REPLACE INTO index_metadata (key, value) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("setMetadata prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            logger.error("setMetadata step failed: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
}
