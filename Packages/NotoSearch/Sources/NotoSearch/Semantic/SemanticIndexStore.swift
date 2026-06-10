import Foundation
import SQLite3

/// SQLite persistence for semantic chunks + embedding vectors.
///
/// Lives in `semantic.sqlite` NEXT TO `search.sqlite`, deliberately separate:
/// the FTS recovery path destroys and rebuilds `search.sqlite` on corruption,
/// and that must never wipe minutes of embedding work. Vectors are stored as
/// little-endian fp32 BLOBs (1.5 KB at 384 dims — well inside SQLite's
/// faster-than-filesystem blob range).
public final class SemanticIndexStore {
    public let databaseURL: URL
    private var db: OpaquePointer?

    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public struct ChunkRecord: Sendable, Equatable {
        public let chunkID: UUID
        public let noteID: UUID
        public let relativePath: String
        public let noteTitle: String
        public let heading: String
        public let snippet: String
        public let lineStart: Int
        public let lineEnd: Int
        public let contentHash: String
        public let kind: SemanticChunkKind
        public let imagePath: String?
    }

    public init(indexDirectory: URL) throws {
        try FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        self.databaseURL = indexDirectory.appendingPathComponent("semantic.sqlite")

        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &pointer, flags, nil) == SQLITE_OK else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            throw SearchIndexStoreError.openFailed(message)
        }
        sqlite3_busy_timeout(pointer, 5_000)
        self.db = pointer
        try createSchema()
    }

    deinit {
        close()
    }

    public func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    public func destroy() throws {
        close()
        for url in [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
            URL(fileURLWithPath: databaseURL.path + "-journal"),
        ] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func createSchema() throws {
        try execute("""
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS semantic_notes (
            note_id TEXT PRIMARY KEY,
            relative_path TEXT NOT NULL UNIQUE,
            note_title TEXT NOT NULL,
            note_content_hash TEXT NOT NULL,
            model_version TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS semantic_chunks (
            chunk_id TEXT PRIMARY KEY,
            note_id TEXT NOT NULL REFERENCES semantic_notes(note_id) ON DELETE CASCADE,
            heading TEXT NOT NULL,
            snippet TEXT NOT NULL,
            line_start INTEGER NOT NULL,
            line_end INTEGER NOT NULL,
            content_hash TEXT NOT NULL,
            dims INTEGER NOT NULL,
            embedding BLOB NOT NULL,
            kind TEXT NOT NULL DEFAULT 'text',
            image_path TEXT,
            describer_version TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_semantic_chunks_note ON semantic_chunks(note_id);

        CREATE TABLE IF NOT EXISTS semantic_metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)
        try migrateSchema()
        try setMetadata("schema_version", value: "2")
    }

    // MARK: - Catalog

    /// (noteID, relativePath, noteContentHash, modelVersion) for every indexed note.
    public func noteCatalog() throws -> [(noteID: UUID, relativePath: String, noteContentHash: String, modelVersion: String)] {
        var rows: [(UUID, String, String, String)] = []
        try query("SELECT note_id, relative_path, note_content_hash, model_version FROM semantic_notes;") { stmt in
            guard let idText = textColumn(stmt, 0), let id = UUID(uuidString: idText),
                  let path = textColumn(stmt, 1),
                  let hash = textColumn(stmt, 2),
                  let model = textColumn(stmt, 3) else { return }
            rows.append((id, path, hash, model))
        }
        return rows
    }

    /// Existing vectors for a note keyed by chunk content hash, so unchanged
    /// chunks are reused instead of re-embedded.
    public func existingVectors(noteID: UUID) throws -> [String: [Float]] {
        var vectors: [String: [Float]] = [:]
        try query(
            "SELECT content_hash, dims, embedding FROM semantic_chunks WHERE note_id = ?;",
            [.text(noteID.uuidString)]
        ) { stmt in
            guard let hash = textColumn(stmt, 0) else { return }
            let dims = Int(sqlite3_column_int(stmt, 1))
            guard let vector = blobVector(stmt, 2, dims: dims) else { return }
            vectors[hash] = vector
        }
        return vectors
    }

    // MARK: - Mutations

    /// Replaces a note's chunks atomically and bumps the generation counter.
    public func replaceNote(
        noteID: UUID,
        relativePath: String,
        noteTitle: String,
        noteContentHash: String,
        modelVersion: String,
        describerVersion: String? = nil,
        chunks: [(chunk: SemanticChunk, vector: [Float])]
    ) throws {
        try transaction {
            try run("DELETE FROM semantic_chunks WHERE note_id = ?;", [.text(noteID.uuidString)])
            try run("DELETE FROM semantic_notes WHERE note_id = ?;", [.text(noteID.uuidString)])
            // A rename can change note_id (path-derived IDs) while keeping the
            // path; clear any stale row occupying this relative path.
            try run("DELETE FROM semantic_notes WHERE relative_path = ?;", [.text(relativePath)])
            try run(
                """
                INSERT INTO semantic_notes (note_id, relative_path, note_title, note_content_hash, model_version)
                VALUES (?, ?, ?, ?, ?);
                """,
                [
                    .text(noteID.uuidString),
                    .text(relativePath),
                    .text(noteTitle),
                    .text(noteContentHash),
                    .text(modelVersion),
                ]
            )
            for entry in chunks {
                try run(
                    """
                    INSERT OR REPLACE INTO semantic_chunks
                        (chunk_id, note_id, heading, snippet, line_start, line_end, content_hash, dims, embedding, kind, image_path, describer_version)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    [
                        .text(entry.chunk.id.uuidString),
                        .text(noteID.uuidString),
                        .text(entry.chunk.heading),
                        .text(String(entry.chunk.snippetText.prefix(240))),
                        .int(entry.chunk.lineStart),
                        .int(entry.chunk.lineEnd),
                        .text(entry.chunk.contentHash),
                        .int(entry.vector.count),
                        .blob(Self.encode(entry.vector)),
                        .text(entry.chunk.kind.rawValue),
                        entry.chunk.imagePath.map(SemanticSQLiteValue.text) ?? .null,
                        describerVersion.map(SemanticSQLiteValue.text) ?? .null,
                    ]
                )
            }
            try bumpGeneration()
        }
    }

    @discardableResult
    public func deleteNote(noteID: UUID) throws -> Bool {
        var exists = false
        try query("SELECT 1 FROM semantic_notes WHERE note_id = ? LIMIT 1;", [.text(noteID.uuidString)]) { _ in
            exists = true
        }
        guard exists else { return false }
        try transaction {
            try run("DELETE FROM semantic_chunks WHERE note_id = ?;", [.text(noteID.uuidString)])
            try run("DELETE FROM semantic_notes WHERE note_id = ?;", [.text(noteID.uuidString)])
            try bumpGeneration()
        }
        return true
    }

    // MARK: - Reads

    /// Loads every stored vector into one contiguous row-major matrix for the
    /// brute-force scan, with parallel chunk metadata.
    public func allEmbeddings() throws -> (dims: Int, matrix: [Float], chunks: [ChunkRecord]) {
        var dims = 0
        var matrix: [Float] = []
        var chunks: [ChunkRecord] = []

        try query("""
        SELECT c.chunk_id, c.note_id, n.relative_path, n.note_title, c.heading, c.snippet,
               c.line_start, c.line_end, c.content_hash, c.dims, c.embedding, c.kind, c.image_path
        FROM semantic_chunks c
        JOIN semantic_notes n ON n.note_id = c.note_id
        ORDER BY c.chunk_id;
        """) { stmt in
            guard let chunkIDText = textColumn(stmt, 0), let chunkID = UUID(uuidString: chunkIDText),
                  let noteIDText = textColumn(stmt, 1), let noteID = UUID(uuidString: noteIDText),
                  let relativePath = textColumn(stmt, 2),
                  let noteTitle = textColumn(stmt, 3),
                  let heading = textColumn(stmt, 4),
                  let snippet = textColumn(stmt, 5),
                  let contentHash = textColumn(stmt, 8) else { return }
            let rowDims = Int(sqlite3_column_int(stmt, 9))
            guard let vector = blobVector(stmt, 10, dims: rowDims) else { return }
            if dims == 0 { dims = rowDims }
            guard rowDims == dims else { return }

            let kind = textColumn(stmt, 11).flatMap(SemanticChunkKind.init(rawValue:)) ?? .text
            let imagePath = textColumn(stmt, 12)
            matrix.append(contentsOf: vector)
            chunks.append(ChunkRecord(
                chunkID: chunkID,
                noteID: noteID,
                relativePath: relativePath,
                noteTitle: noteTitle,
                heading: heading,
                snippet: snippet,
                lineStart: Int(sqlite3_column_int(stmt, 6)),
                lineEnd: Int(sqlite3_column_int(stmt, 7)),
                contentHash: contentHash,
                kind: kind,
                imagePath: imagePath
            ))
        }
        return (dims, matrix, chunks)
    }

    /// Stored image-chunk rows for a note keyed by content hash, so unchanged
    /// images are reused without re-describing or re-embedding. The
    /// `embeddedText` field is not persisted and comes back empty.
    public func existingImageChunks(noteID: UUID) throws -> [String: (chunk: SemanticChunk, vector: [Float])] {
        var rows: [String: (SemanticChunk, [Float])] = [:]
        try query(
            """
            SELECT chunk_id, heading, snippet, line_start, line_end, content_hash, dims, embedding, image_path
            FROM semantic_chunks
            WHERE note_id = ? AND kind = 'image';
            """,
            [.text(noteID.uuidString)]
        ) { stmt in
            guard let chunkIDText = textColumn(stmt, 0), let chunkID = UUID(uuidString: chunkIDText),
                  let heading = textColumn(stmt, 1),
                  let snippet = textColumn(stmt, 2),
                  let hash = textColumn(stmt, 5) else { return }
            let dims = Int(sqlite3_column_int(stmt, 6))
            guard let vector = blobVector(stmt, 7, dims: dims) else { return }
            let chunk = SemanticChunk(
                id: chunkID,
                noteID: noteID,
                heading: heading,
                lineStart: Int(sqlite3_column_int(stmt, 3)),
                lineEnd: Int(sqlite3_column_int(stmt, 4)),
                embeddedText: "",
                snippetText: snippet,
                contentHash: hash,
                kind: .image,
                imagePath: textColumn(stmt, 8)
            )
            rows[hash] = (chunk, vector)
        }
        return rows
    }

    private func migrateSchema() throws {
        var chunkColumns = Set<String>()
        try query("PRAGMA table_info(semantic_chunks);") { stmt in
            if let name = textColumn(stmt, 1) {
                chunkColumns.insert(name)
            }
        }
        if !chunkColumns.contains("kind") {
            try execute("ALTER TABLE semantic_chunks ADD COLUMN kind TEXT NOT NULL DEFAULT 'text';")
        }
        if !chunkColumns.contains("image_path") {
            try execute("ALTER TABLE semantic_chunks ADD COLUMN image_path TEXT;")
        }
        if !chunkColumns.contains("describer_version") {
            try execute("ALTER TABLE semantic_chunks ADD COLUMN describer_version TEXT;")
        }
    }

    public func stats() throws -> SemanticIndexStats {
        var modelVersion: String?
        try query("SELECT model_version FROM semantic_notes LIMIT 1;") { stmt in
            modelVersion = textColumn(stmt, 0)
        }
        return SemanticIndexStats(
            noteCount: try intValue("SELECT COUNT(*) FROM semantic_notes;"),
            chunkCount: try intValue("SELECT COUNT(*) FROM semantic_chunks;"),
            modelVersion: modelVersion
        )
    }

    /// Monotonic counter bumped on every mutation; lets searchers cache the
    /// in-memory matrix and reload only when the store actually changed.
    public func generation() throws -> Int {
        var value = 0
        try query("SELECT value FROM semantic_metadata WHERE key = 'generation';") { stmt in
            value = textColumn(stmt, 0).flatMap(Int.init) ?? 0
        }
        return value
    }

    // MARK: - Vector encoding

    static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func decode(_ data: Data, dims: Int) -> [Float]? {
        guard data.count == dims * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }

    // MARK: - SQLite plumbing

    private func bumpGeneration() throws {
        try run("""
        INSERT INTO semantic_metadata (key, value) VALUES ('generation', '1')
        ON CONFLICT(key) DO UPDATE SET value = CAST((CAST(value AS INTEGER) + 1) AS TEXT);
        """)
    }

    private func setMetadata(_ key: String, value: String) throws {
        try run(
            "INSERT OR REPLACE INTO semantic_metadata (key, value) VALUES (?, ?);",
            [.text(key), .text(value)]
        )
    }

    private func intValue(_ sql: String) throws -> Int {
        var value = 0
        try query(sql) { stmt in
            value = Int(sqlite3_column_int(stmt, 0))
        }
        return value
    }

    private func blobVector(_ stmt: OpaquePointer, _ index: Int32, dims: Int) -> [Float]? {
        guard let pointer = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        let data = Data(bytes: pointer, count: count)
        return Self.decode(data, dims: dims)
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard let db else { throw SearchIndexStoreError.closed }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SearchIndexStoreError.sqlite(message)
        }
    }

    private func run(_ sql: String, _ values: [SemanticSQLiteValue] = []) throws {
        try prepare(sql, values) { stmt in
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SearchIndexStoreError.sqlite(message)
            }
        }
    }

    private func query(_ sql: String, _ values: [SemanticSQLiteValue] = [], row: (OpaquePointer) throws -> Void) throws {
        try prepare(sql, values) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                try row(stmt)
            }
        }
    }

    private func prepare(_ sql: String, _ values: [SemanticSQLiteValue], body: (OpaquePointer) throws -> Void) throws {
        guard let db else { throw SearchIndexStoreError.closed }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SearchIndexStoreError.sqlite(message)
        }
        defer { sqlite3_finalize(stmt) }

        for (index, value) in values.enumerated() {
            let bindIndex = Int32(index + 1)
            switch value {
            case .text(let text):
                sqlite3_bind_text(stmt, bindIndex, text, -1, transient)
            case .int(let int):
                sqlite3_bind_int64(stmt, bindIndex, sqlite3_int64(int))
            case .blob(let data):
                _ = data.withUnsafeBytes { raw in
                    sqlite3_bind_blob(stmt, bindIndex, raw.baseAddress, Int32(raw.count), transient)
                }
            case .null:
                sqlite3_bind_null(stmt, bindIndex)
            }
        }
        try body(stmt)
    }

    private var message: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite database is closed"
    }
}

private enum SemanticSQLiteValue {
    case text(String)
    case int(Int)
    case blob(Data)
    case null
}

private func textColumn(_ stmt: OpaquePointer, _ index: Int32) -> String? {
    guard let pointer = sqlite3_column_text(stmt, index) else { return nil }
    return String(cString: pointer)
}
