//
//  FTS5Database.swift
//  NotoFTS5
//
//  Actor wrapping the SQLite C API. Manages search.sqlite with
//  the block_fts FTS5 virtual table for full-text search.
//

import Foundation
import SQLite3
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "FTS5Database")

public actor FTS5Database {

    private var db: OpaquePointer?
    private let dbURL: URL

    // MARK: - Lifecycle

    /// Opens or creates search.sqlite in the given directory.
    public init(directory: URL) {
        self.dbURL = directory.appendingPathComponent("search.sqlite")

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
            logger.info("Opened search database at \(self.dbURL.path)")
        } else {
            logger.error("Failed to open search database: \(String(cString: sqlite3_errmsg(dbPointer)))")
            self.db = nil
        }
    }

    /// Creates the block_fts FTS5 virtual table if it doesn't exist.
    public func createTablesIfNeeded() {
        guard let db = db else { return }

        let sql = """
            CREATE VIRTUAL TABLE IF NOT EXISTS block_fts
            USING fts5(block_id UNINDEXED, content);
            """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) != SQLITE_DONE {
                logger.error("Failed to execute DDL: \(String(cString: sqlite3_errmsg(db)))")
            }
        } else {
            logger.error("Failed to prepare DDL: \(String(cString: sqlite3_errmsg(db)))")
        }
        sqlite3_finalize(stmt)

        logger.info("Tables created/verified")
    }

    /// Closes the database connection.
    public func close() {
        guard let db = db else { return }
        sqlite3_close(db)
        self.db = nil
        logger.info("Closed search database")
    }

    /// Deletes the .sqlite file (for full rebuild).
    public func destroy() {
        close()
        do {
            if FileManager.default.fileExists(atPath: dbURL.path) {
                try FileManager.default.removeItem(at: dbURL)
                logger.info("Destroyed search database at \(self.dbURL.path)")
            }
        } catch {
            logger.error("Failed to destroy database: \(error)")
        }
    }

    // MARK: - FTS5 Operations

    /// Inserts or replaces a block's content in the FTS5 index.
    public func upsertBlock(blockId: UUID, content: String) {
        guard let db = db else { return }

        // Delete existing entry first (FTS5 doesn't support UPDATE well with rowid)
        deleteBlock(blockId: blockId)

        let sql = "INSERT INTO block_fts (block_id, content) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("upsertBlock prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let idString = blockId.uuidString
        sqlite3_bind_text(stmt, 1, (idString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (content as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            logger.error("upsertBlock step failed: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    /// Deletes a block from the FTS5 index.
    public func deleteBlock(blockId: UUID) {
        guard let db = db else { return }
        let sql = "DELETE FROM block_fts WHERE block_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("deleteBlock prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let idString = blockId.uuidString
        sqlite3_bind_text(stmt, 1, (idString as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            logger.error("deleteBlock step failed: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    /// Searches the FTS5 index and returns matching block IDs with BM25 scores.
    public func search(query: String) -> [(blockId: UUID, bm25Score: Double)] {
        guard let db = db else { return [] }

        let sql = """
            SELECT block_id, bm25(block_fts) AS score
            FROM block_fts
            WHERE block_fts MATCH ?
            ORDER BY score;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("search prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (query as NSString).utf8String, -1, nil)

        var results: [(UUID, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idCStr = sqlite3_column_text(stmt, 0),
                  let uuid = UUID(uuidString: String(cString: idCStr)) else {
                continue
            }
            let score = sqlite3_column_double(stmt, 1)
            results.append((uuid, score))
        }
        return results
    }

    /// Inserts multiple blocks into FTS5 in a single transaction (used by rebuildAll).
    public func upsertBlockBatch(blocks: [(blockId: UUID, content: String)]) {
        guard let db = db, !blocks.isEmpty else { return }

        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

        let sql = "INSERT INTO block_fts (block_id, content) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("upsertBlockBatch prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }

        for block in blocks {
            sqlite3_reset(stmt)
            let idString = block.blockId.uuidString
            sqlite3_bind_text(stmt, 1, (idString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (block.content as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                logger.error("upsertBlockBatch step failed: \(String(cString: sqlite3_errmsg(db)))")
            }
        }

        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }

    /// Drops and recreates the block_fts virtual table (used by rebuildAll).
    public func recreateBlockFTS() {
        guard let db = db else { return }
        let drop = "DROP TABLE IF EXISTS block_fts;"
        let create = """
            CREATE VIRTUAL TABLE IF NOT EXISTS block_fts
            USING fts5(block_id UNINDEXED, content);
            """
        for sql in [drop, create] {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) != SQLITE_DONE {
                    logger.error("recreateBlockFTS failed: \(String(cString: sqlite3_errmsg(db)))")
                }
            } else {
                logger.error("recreateBlockFTS prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            }
            sqlite3_finalize(stmt)
        }
        logger.info("Recreated block_fts table")
    }
}
