import Foundation
import SQLite3

public final class SearchIndexStore {
    public let databaseURL: URL
    private var db: OpaquePointer?

    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(indexDirectory: URL) throws {
        try FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        self.databaseURL = indexDirectory.appendingPathComponent("search.sqlite")

        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &pointer, flags, nil) == SQLITE_OK else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            throw SearchIndexStoreError.openFailed(message)
        }
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
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            try FileManager.default.removeItem(at: databaseURL)
        }
    }

    public func createSchema() throws {
        try execute("""
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS notes (
            note_id TEXT PRIMARY KEY,
            relative_path TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            folder_path TEXT NOT NULL,
            file_modified_at TEXT NOT NULL,
            content_hash TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sections (
            section_id TEXT PRIMARY KEY,
            note_id TEXT NOT NULL REFERENCES notes(note_id) ON DELETE CASCADE,
            heading TEXT NOT NULL,
            level INTEGER,
            line_start INTEGER NOT NULL,
            line_end INTEGER NOT NULL,
            section_index INTEGER NOT NULL,
            content_hash TEXT NOT NULL
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS note_fts USING fts5(
            title,
            folder_path,
            content,
            note_id UNINDEXED,
            tokenize='porter unicode61'
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS section_fts USING fts5(
            heading,
            content,
            note_id UNINDEXED,
            section_id UNINDEXED,
            line_start UNINDEXED,
            tokenize='porter unicode61'
        );

        CREATE TABLE IF NOT EXISTS index_metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)
        try setMetadata("schema_version", value: "1")
    }

    public func rebuild(documents: [(document: SearchDocument, fileModifiedAt: Date)]) throws -> SearchIndexStats {
        try transaction {
            try execute("DELETE FROM note_fts;")
            try execute("DELETE FROM section_fts;")
            try execute("DELETE FROM sections;")
            try execute("DELETE FROM notes;")
            for entry in documents {
                try upsert(entry.document, fileModifiedAt: entry.fileModifiedAt, withinTransaction: true)
            }
        }
        return try stats()
    }

    public func upsert(_ document: SearchDocument, fileModifiedAt: Date) throws {
        try transaction {
            try upsert(document, fileModifiedAt: fileModifiedAt, withinTransaction: true)
        }
    }

    public func deleteMissing(existingRelativePaths: Set<String>) throws -> Int {
        let rows = try noteCatalog()
        var deleted = 0
        try transaction {
            for row in rows where !existingRelativePaths.contains(row.relativePath) {
                try deleteNote(noteID: row.noteID, withinTransaction: true)
                deleted += 1
            }
        }
        return deleted
    }

    public func noteCatalog() throws -> [(noteID: UUID, relativePath: String, contentHash: String)] {
        var rows: [(UUID, String, String)] = []
        try query("SELECT note_id, relative_path, content_hash FROM notes;") { stmt in
            guard let idText = textColumn(stmt, 0), let id = UUID(uuidString: idText),
                  let path = textColumn(stmt, 1),
                  let hash = textColumn(stmt, 2) else {
                return
            }
            rows.append((id, path, hash))
        }
        return rows
    }

    public func stats() throws -> SearchIndexStats {
        SearchIndexStats(
            noteCount: try intValue("SELECT COUNT(*) FROM notes;"),
            sectionCount: try intValue("SELECT COUNT(*) FROM sections;")
        )
    }

    public func search(query: String, scope: SearchScope = .titleAndContent, vaultURL: URL, limit: Int = 50) throws -> [SearchResult] {
        let ftsQuery = switch scope {
        case .title:
            MarkdownSearchEngine.titleOnlyFTSQuery(for: query)
        case .titleAndContent:
            MarkdownSearchEngine.ftsQuery(for: query)
        }
        guard !ftsQuery.isEmpty else { return [] }

        var results: [(result: SearchResult, rank: Double)] = []
        let terms = MarkdownSearchEngine.boostTerms(for: query)
        let candidateLimit = max(limit * 4, limit)
        try searchNotes(ftsQuery: ftsQuery, rawQuery: query, terms: terms, vaultURL: vaultURL, limit: candidateLimit, results: &results)
        if scope == .titleAndContent {
            try searchSections(ftsQuery: ftsQuery, rawQuery: query, terms: terms, vaultURL: vaultURL, limit: candidateLimit, results: &results)
        }

        return results
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.result.title.localizedCaseInsensitiveCompare(rhs.result.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.result)
    }

    private func upsert(_ document: SearchDocument, fileModifiedAt: Date, withinTransaction: Bool) throws {
        try deleteNote(noteID: document.id, withinTransaction: withinTransaction)

        try run(
            """
            INSERT INTO notes (note_id, relative_path, title, folder_path, file_modified_at, content_hash)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            [
                .text(document.id.uuidString),
                .text(document.relativePath),
                .text(document.title),
                .text(document.folderPath),
                .text(SearchUtilities.iso8601.string(from: fileModifiedAt)),
                .text(document.contentHash),
            ]
        )

        try run(
            "INSERT INTO note_fts (title, folder_path, content, note_id) VALUES (?, ?, ?, ?);",
            [.text(document.title), .text(document.folderPath), .text(document.plainText), .text(document.id.uuidString)]
        )

        for section in document.sections {
            try run(
                """
                INSERT INTO sections (section_id, note_id, heading, level, line_start, line_end, section_index, content_hash)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
                [
                    .text(section.id.uuidString),
                    .text(section.noteID.uuidString),
                    .text(section.heading),
                    section.level.map(SQLiteValue.int) ?? .null,
                    .int(section.lineStart),
                    .int(section.lineEnd),
                    .int(section.sectionIndex),
                    .text(section.contentHash),
                ]
            )
            try run(
                "INSERT INTO section_fts (heading, content, note_id, section_id, line_start) VALUES (?, ?, ?, ?, ?);",
                [
                    .text(section.heading),
                    .text(section.plainText),
                    .text(section.noteID.uuidString),
                    .text(section.id.uuidString),
                    .int(section.lineStart),
                ]
            )
        }
    }

    private func deleteNote(noteID: UUID, withinTransaction: Bool) throws {
        let id = noteID.uuidString
        try run("DELETE FROM note_fts WHERE note_id = ?;", [.text(id)])
        try run("DELETE FROM section_fts WHERE note_id = ?;", [.text(id)])
        try run("DELETE FROM sections WHERE note_id = ?;", [.text(id)])
        try run("DELETE FROM notes WHERE note_id = ?;", [.text(id)])
    }

    private func searchNotes(
        ftsQuery: String,
        rawQuery: String,
        terms: [String],
        vaultURL: URL,
        limit: Int,
        results: inout [(result: SearchResult, rank: Double)]
    ) throws {
        try query(
            """
            SELECT n.note_id, n.relative_path, n.title, n.folder_path, n.file_modified_at,
                   bm25(note_fts, 5.0, 1.5, 1.0) AS rank,
                   snippet(note_fts, 2, '', '', '...', 24) AS snippet
            FROM note_fts
            JOIN notes n ON n.note_id = note_fts.note_id
            WHERE note_fts MATCH ?
            ORDER BY rank
            LIMIT ?;
            """,
            [.text(ftsQuery), .int(limit)]
        ) { stmt in
            guard let noteIDText = textColumn(stmt, 0), let noteID = UUID(uuidString: noteIDText),
                  let relativePath = textColumn(stmt, 1),
                  let title = textColumn(stmt, 2),
                  let folderPath = textColumn(stmt, 3),
                  let modifiedAtText = textColumn(stmt, 4) else {
                return
            }
            let rank = sqlite3_column_double(stmt, 5)
            let snippet = textColumn(stmt, 6) ?? ""
            let modifiedAt = SearchUtilities.iso8601.date(from: modifiedAtText)
            let adjustedRank = rank
                + noteBoost(title: title, folderPath: folderPath, query: rawQuery, terms: terms)
                + recencyBoost(updatedAt: modifiedAt)
            let fileURL = vaultURL.appendingPathComponent(relativePath)
            results.append((
                SearchResult(
                    id: noteID,
                    kind: .note,
                    noteID: noteID,
                    fileURL: fileURL,
                    title: title,
                    breadcrumb: folderPath,
                    snippet: snippet.isEmpty ? title : snippet,
                    lineStart: nil,
                    score: -adjustedRank,
                    updatedAt: modifiedAt
                ),
                adjustedRank
            ))
        }
    }

    private func searchSections(
        ftsQuery: String,
        rawQuery: String,
        terms: [String],
        vaultURL: URL,
        limit: Int,
        results: inout [(result: SearchResult, rank: Double)]
    ) throws {
        try query(
            """
            SELECT s.section_id, s.note_id, s.heading, s.level, s.line_start, n.relative_path, n.title, n.folder_path, n.file_modified_at,
                   bm25(section_fts, 5.0, 1.0) AS rank,
                   snippet(section_fts, 1, '', '', '...', 24) AS snippet
            FROM section_fts
            JOIN sections s ON s.section_id = section_fts.section_id
            JOIN notes n ON n.note_id = s.note_id
            WHERE section_fts MATCH ?
            ORDER BY rank
            LIMIT ?;
            """,
            [.text(ftsQuery), .int(limit)]
        ) { stmt in
            guard let sectionIDText = textColumn(stmt, 0), let sectionID = UUID(uuidString: sectionIDText),
                  let noteIDText = textColumn(stmt, 1), let noteID = UUID(uuidString: noteIDText),
                  let heading = textColumn(stmt, 2),
                  let relativePath = textColumn(stmt, 5),
                  let noteTitle = textColumn(stmt, 6),
                  let folderPath = textColumn(stmt, 7),
                  let modifiedAtText = textColumn(stmt, 8) else {
                return
            }
            let level: Int? = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 3))
            let lineStart = Int(sqlite3_column_int(stmt, 4))
            let rank = sqlite3_column_double(stmt, 9)
            let snippet = textColumn(stmt, 10) ?? ""
            let modifiedAt = SearchUtilities.iso8601.date(from: modifiedAtText)
            let adjustedRank = rank
                + sectionBoost(heading: heading, noteTitle: noteTitle, folderPath: folderPath, query: rawQuery, terms: terms)
                + recencyBoost(updatedAt: modifiedAt)
            let fileURL = vaultURL.appendingPathComponent(relativePath)
            let breadcrumb = sectionBreadcrumb(relativePath: relativePath, heading: heading, level: level)
            results.append((
                SearchResult(
                    id: sectionID,
                    kind: .section,
                    noteID: noteID,
                    fileURL: fileURL,
                    title: noteTitle,
                    breadcrumb: breadcrumb,
                    snippet: snippet.isEmpty ? heading : snippet,
                    lineStart: lineStart,
                    score: -adjustedRank,
                    updatedAt: modifiedAt
                ),
                adjustedRank
            ))
        }
    }

    private func sectionBreadcrumb(relativePath: String, heading: String, level: Int?) -> String {
        guard let level, level > 0 else { return relativePath }
        let headingPrefix = String(repeating: "#", count: min(level, 6))
        return "\(relativePath)/\(headingPrefix) \(heading)"
    }

    private func noteBoost(title: String, folderPath: String, query: String, terms: [String]) -> Double {
        let normalizedTitle = title.lowercased()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var boost = 0.0
        if normalizedTitle == normalizedQuery {
            boost -= 10
        }
        if !terms.isEmpty, terms.allSatisfy({ normalizedTitle.contains($0) }) {
            boost -= 5
        }
        if !terms.isEmpty, terms.contains(where: { folderPath.lowercased().contains($0) }) {
            boost -= 1
        }
        return boost
    }

    private func sectionBoost(heading: String, noteTitle: String, folderPath: String, query: String, terms: [String]) -> Double {
        let normalizedHeading = heading.lowercased()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var boost = 0.0
        if normalizedHeading == normalizedQuery {
            boost -= 7
        }
        if !terms.isEmpty, terms.allSatisfy({ normalizedHeading.contains($0) }) {
            boost -= 4
        }
        if !terms.isEmpty, terms.contains(where: { folderPath.lowercased().contains($0) }) {
            boost -= 1
        }
        if !terms.isEmpty, noteTitle.lowercased().contains(terms[0]) {
            boost -= 0.5
        }
        return boost
    }

    private func recencyBoost(updatedAt: Date?, now: Date = Date()) -> Double {
        guard let updatedAt else { return 0 }
        let age = max(0, now.timeIntervalSince(updatedAt))
        let ageInDays = age / 86_400
        return -1.5 * exp(-ageInDays / 30)
    }

    private func setMetadata(_ key: String, value: String) throws {
        try run(
            "INSERT OR REPLACE INTO index_metadata (key, value) VALUES (?, ?);",
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

    private func run(_ sql: String, _ values: [SQLiteValue] = []) throws {
        try prepare(sql, values) { stmt in
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SearchIndexStoreError.sqlite(message)
            }
        }
    }

    private func query(_ sql: String, _ values: [SQLiteValue] = [], row: (OpaquePointer) throws -> Void) throws {
        try prepare(sql, values) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                try row(stmt)
            }
        }
    }

    private func prepare(_ sql: String, _ values: [SQLiteValue], body: (OpaquePointer) throws -> Void) throws {
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
                sqlite3_bind_int(stmt, bindIndex, Int32(int))
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

public enum SearchIndexStoreError: Error, CustomStringConvertible {
    case openFailed(String)
    case sqlite(String)
    case closed

    public var description: String {
        switch self {
        case .openFailed(let message):
            "Could not open search index: \(message)"
        case .sqlite(let message):
            "SQLite error: \(message)"
        case .closed:
            "SQLite database is closed"
        }
    }
}

private enum SQLiteValue {
    case text(String)
    case int(Int)
    case null
}

private func textColumn(_ stmt: OpaquePointer, _ index: Int32) -> String? {
    guard let pointer = sqlite3_column_text(stmt, index) else { return nil }
    return String(cString: pointer)
}
