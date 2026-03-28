//
//  VectorKeyStore.swift
//  NotoHNSW
//
//  Actor managing the vector_key_map SQLite table. Maps block UUIDs to UInt64 HNSW keys.
//  Extracted from FTS5Database to decouple vector storage from full-text search.
//

#if canImport(USearch)
import Foundation
import SQLite3
import os.log

private let logger = Logger(subsystem: "com.noto", category: "VectorKeyStore")

public actor VectorKeyStore {

    private var db: OpaquePointer?
    private let dbURL: URL

    // MARK: - Lifecycle

    /// Opens or creates vectors.sqlite in the given directory.
    public init(directory: URL) {
        self.dbURL = directory.appendingPathComponent("vectors.sqlite")

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
            logger.info("Opened vector key database at \(self.dbURL.path)")
        } else {
            logger.error("Failed to open vector key database: \(String(cString: sqlite3_errmsg(dbPointer)))")
            self.db = nil
        }
    }

    /// Creates the vector_key_map table if it doesn't exist.
    public func createTablesIfNeeded() {
        guard let db = db else { return }

        let sql = """
            CREATE TABLE IF NOT EXISTS vector_key_map (
                block_id TEXT PRIMARY KEY,
                vector_key INTEGER NOT NULL UNIQUE
            );
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

        logger.info("vector_key_map table created/verified")
    }

    // MARK: - Key Mapping

    /// Returns the vector key for a block ID, or nil if not found.
    public func getVectorKey(blockId: UUID) -> UInt64? {
        guard let db = db else { return nil }
        let sql = "SELECT vector_key FROM vector_key_map WHERE block_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        let idString = blockId.uuidString
        sqlite3_bind_text(stmt, 1, (idString as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return UInt64(sqlite3_column_int64(stmt, 0))
        }
        return nil
    }

    /// Sets the vector key for a block ID.
    public func setVectorKey(blockId: UUID, key: UInt64) {
        guard let db = db else { return }
        let sql = "INSERT OR REPLACE INTO vector_key_map (block_id, vector_key) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("setVectorKey prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let idString = blockId.uuidString
        sqlite3_bind_text(stmt, 1, (idString as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 2, Int64(bitPattern: key))

        if sqlite3_step(stmt) != SQLITE_DONE {
            logger.error("setVectorKey step failed: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    /// Removes the vector key mapping for a block ID.
    public func removeVectorKey(blockId: UUID) {
        guard let db = db else { return }
        let sql = "DELETE FROM vector_key_map WHERE block_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("removeVectorKey prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let idString = blockId.uuidString
        sqlite3_bind_text(stmt, 1, (idString as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            logger.error("removeVectorKey step failed: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    /// Returns the block ID for a vector key, or nil if not found.
    public func getBlockId(vectorKey: UInt64) -> UUID? {
        guard let db = db else { return nil }
        let sql = "SELECT block_id FROM vector_key_map WHERE vector_key = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(bitPattern: vectorKey))

        if sqlite3_step(stmt) == SQLITE_ROW {
            guard let idCStr = sqlite3_column_text(stmt, 0),
                  let uuid = UUID(uuidString: String(cString: idCStr)) else {
                return nil
            }
            return uuid
        }
        return nil
    }

    /// Closes the database connection.
    public func close() {
        guard let db = db else { return }
        sqlite3_close(db)
        self.db = nil
        logger.info("Closed vector key database")
    }
}
#endif
