import Foundation
import NotoVault

// MARK: - Results

public struct GrepHit: Sendable, Equatable {
    public let path: String   // vault-relative
    public let line: Int      // 1-based
    public let snippet: String
}

/// A note matched by metadata (no keyword), with its dates — used by `grep`'s filter-only mode.
public struct NoteEntry: Sendable, Equatable {
    public let path: String
    public let title: String
    public let created: Date
    public let updated: Date
}

/// Date-range constraints on a note's `created` / `updated` frontmatter timestamps (FS fallback).
public struct DateFilter: Sendable, Equatable {
    public var createdAfter: Date?
    public var createdBefore: Date?
    public var updatedAfter: Date?
    public var updatedBefore: Date?

    public init(createdAfter: Date? = nil, createdBefore: Date? = nil,
                updatedAfter: Date? = nil, updatedBefore: Date? = nil) {
        self.createdAfter = createdAfter
        self.createdBefore = createdBefore
        self.updatedAfter = updatedAfter
        self.updatedBefore = updatedBefore
    }

    public var isActive: Bool {
        createdAfter != nil || createdBefore != nil || updatedAfter != nil || updatedBefore != nil
    }

    public func matches(created: Date, updated: Date) -> Bool {
        if let a = createdAfter, created < a { return false }
        if let b = createdBefore, created > b { return false }
        if let a = updatedAfter, updated < a { return false }
        if let b = updatedBefore, updated > b { return false }
        return true
    }
}

public struct ReadResult: Sendable, Equatable {
    public let path: String?      // vault-relative, nil on failure
    public let text: String       // content (or error message), fed to the model
    public let ok: Bool
}

/// Outcome of dispatching one tool call.
public struct ToolRunResult: Sendable, Equatable {
    public var output: String          // text returned to the model
    public var readPath: String?       // set when a `read` succeeded
    public var summary: String         // short human-facing summary (for the UI)
    /// Vault-relative paths this tool exposed to the model (grep hit files, the read file). The
    /// agent uses this to ground citations: only files actually surfaced can be cited.
    public var surfacedPaths: [String] = []
    /// Per-match (note, snippet) for grep — drives the expanded tool-trace "note › snippet" rows.
    public var hits: [GrepHit] = []
}

// MARK: - VaultTools

/// Local filesystem tools the model can call: `grep`, `read`, `list`, scoped to a vault root.
/// Reads go through `NotoVault.VaultFileSystem` (NSFileCoordinator — correct for iCloud); grep
/// uses a fast direct scan for throughput.
public struct VaultTools: Sendable {
    public let root: URL
    private let fs: any VaultFileSystem
    let searchProvider: (any ChatSearchProviding)?

    public init(
        root: URL,
        fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem(),
        searchProvider: (any ChatSearchProviding)? = nil
    ) {
        self.root = root.standardizedFileURL
        self.fs = fileSystem
        self.searchProvider = searchProvider
    }

    // MARK: Tool schemas advertised to the model

    /// Legacy fixed set (no hybrid search) — prefer the instance property.
    public static let toolDefinitions: [ToolDefinition] = [grepDefinition, readDefinition, listDefinition]

    /// Tools advertised to the model for this session. `search` appears only
    /// when the app injected a hybrid search provider.
    public var toolDefinitions: [ToolDefinition] {
        searchProvider == nil
            ? [Self.grepDefinition, Self.readDefinition, Self.listDefinition]
            : [Self.searchDefinition, Self.grepDefinition, Self.readDefinition, Self.listDefinition]
    }

    static let grepDefinition = ToolDefinition(function: .init(
        name: "grep",
        description: "EXACT substring matching over the vault's markdown notes — use only when the "
            + "user's words must appear literally (names, identifiers, quoted phrases), or omit "
            + "`query` to LIST notes matching only the date filters when NO topic is given. For any "
            + "topical question — including time-scoped ones like 'what did I write about X "
            + "recently' — prefer the `search` tool, which also takes the same date filters. Date "
            + "filters compare the note's created and updated timestamps; pass ISO dates "
            + "(YYYY-MM-DD).",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Text to search for (case-insensitive substring). Omit to list by date only.")
                ]),
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Optional vault-relative folder to limit to (e.g. \"Daily Notes\").")
                ]),
                "created_after": .object([
                    "type": .string("string"),
                    "description": .string("Only notes created on/after this ISO date (YYYY-MM-DD).")
                ]),
                "created_before": .object([
                    "type": .string("string"),
                    "description": .string("Only notes created on/before this ISO date (YYYY-MM-DD).")
                ]),
                "updated_after": .object([
                    "type": .string("string"),
                    "description": .string("Only notes updated on/after this ISO date (YYYY-MM-DD).")
                ]),
                "updated_before": .object([
                    "type": .string("string"),
                    "description": .string("Only notes updated on/before this ISO date (YYYY-MM-DD).")
                ])
            ]),
            "required": .array([])
        ])
    ))

    static let readDefinition = ToolDefinition(function: .init(
        name: "read",
        description: "Read a markdown note from the vault by its vault-relative path. Optionally "
            + "restrict to a 1-based inclusive line range. Use this to pull in the notes you cite.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Vault-relative path to the note, e.g. \"Projects/Alpha/Spec.md\".")
                ]),
                "start_line": .object([
                    "type": .string("integer"),
                    "description": .string("Optional 1-based first line to return.")
                ]),
                "end_line": .object([
                    "type": .string("integer"),
                    "description": .string("Optional 1-based last line to return (inclusive).")
                ])
            ]),
            "required": .array([.string("path")])
        ])
    ))

    static let listDefinition = ToolDefinition(function: .init(
        name: "list",
        description: "List the immediate contents of a vault folder (directories first, then notes). "
            + "Omit path to list the vault root.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Optional vault-relative folder. Omit for the vault root.")
                ])
            ]),
            "required": .array([])
        ])
    ))

    // MARK: Dispatch

    /// Execute a tool call by name, parsing its JSON arguments. Always returns a result (errors are
    /// returned as text so the model can self-correct).
    public func run(_ call: ToolCall) -> ToolRunResult {
        let args = Self.parseArguments(call.function.arguments)
        switch call.function.name {
        case "search":
            return runSearch(args)
        case "grep":
            let query = (args["query"] as? String) ?? ""
            let path = args["path"] as? String
            let filter = Self.parseDateFilter(args)
            if query.isEmpty {
                guard filter.isActive || (path?.isEmpty == false) else {
                    return .init(output: "Error: grep needs a \"query\" or at least one date filter (or a path).",
                                 readPath: nil, summary: "grep: bad args")
                }
                let notes = listNotes(path: path, filter: filter)
                return .init(output: Self.format(notes: notes), readPath: nil,
                             summary: "\(notes.count) note\(notes.count == 1 ? "" : "s")",
                             surfacedPaths: notes.map(\.path))
            }
            let hits = grep(query: query, path: path, filter: filter)
            let files = Array(Set(hits.map(\.path))).sorted()
            let noteCount = files.count
            return .init(output: Self.format(hits: hits, query: query), readPath: nil,
                         summary: "\(hits.count) match\(hits.count == 1 ? "" : "es") in \(noteCount) note\(noteCount == 1 ? "" : "s")",
                         surfacedPaths: files,
                         hits: Array(hits.prefix(8)))
        case "read":
            guard let path = args["path"] as? String, !path.isEmpty else {
                return .init(output: "Error: read requires a \"path\".", readPath: nil, summary: "read: bad args")
            }
            let start = Self.intValue(args["start_line"])
            let end = Self.intValue(args["end_line"])
            let result = read(path: path, startLine: start, endLine: end)
            let surfaced = (result.ok ? result.path : nil).map { [$0] } ?? []
            return .init(output: result.text, readPath: result.ok ? result.path : nil,
                         summary: result.ok ? "read \(result.path ?? path)" : "read failed",
                         surfacedPaths: surfaced)
        case "list":
            let path = args["path"] as? String
            let text = list(path: path)
            return .init(output: text, readPath: nil, summary: "listed \(path ?? "/")")
        default:
            return .init(output: "Error: unknown tool \"\(call.function.name)\".", readPath: nil, summary: "unknown tool")
        }
    }

    // MARK: grep

    public func grep(query: String, path: String? = nil, filter: DateFilter = .init(),
                     maxResults: Int = 50, perFileCap: Int = 8) -> [GrepHit] {
        let scope: URL
        if let path, !path.isEmpty {
            guard let resolved = resolve(path) else { return [] }
            scope = resolved
        } else {
            scope = root
        }
        let needle = query.lowercased()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: scope,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var hits: [GrepHit] = []
        for case let fileURL as URL in enumerator {
            if hits.count >= maxResults { break }
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            // Date pre-filter from the header only — skip the full-body read for out-of-range files.
            if filter.isActive {
                guard let header = readHeader(fileURL) else { continue }
                let d = noteDates(header, url: fileURL)
                guard filter.matches(created: d.created, updated: d.updated) else { continue }
            }
            guard let content = readForScan(fileURL) else { continue }
            let rel = relativePath(fileURL)
            var perFile = 0
            var lineNo = 0
            for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
                lineNo += 1
                if line.lowercased().contains(needle) {
                    hits.append(GrepHit(path: rel, line: lineNo, snippet: Self.snippet(String(line))))
                    perFile += 1
                    if perFile >= perFileCap || hits.count >= maxResults { break }
                }
            }
        }
        return hits.sorted { $0.path == $1.path ? $0.line < $1.line : $0.path < $1.path }
    }

    // MARK: list notes by metadata (grep's filter-only mode)

    /// List notes matching the date filter (no keyword), most-recently-modified first.
    public func listNotes(path: String? = nil, filter: DateFilter = .init(), maxResults: Int = 50) -> [NoteEntry] {
        let scope: URL
        if let path, !path.isEmpty {
            guard let resolved = resolve(path) else { return [] }
            scope = resolved
        } else {
            scope = root
        }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: scope,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var entries: [NoteEntry] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            // Header-only read — listing never needs full note bodies.
            guard let header = readHeader(fileURL) else { continue }
            let meta = noteMeta(content: header, url: fileURL)
            if filter.isActive, !filter.matches(created: meta.created, updated: meta.updated) { continue }
            entries.append(NoteEntry(path: relativePath(fileURL), title: meta.title,
                                     created: meta.created, updated: meta.updated))
        }
        entries.sort { $0.updated > $1.updated }
        return Array(entries.prefix(maxResults))
    }

    /// Created/updated dates from frontmatter (filesystem fallback). Works on a header prefix —
    /// the frontmatter is at the very top, so we never need the whole file just for dates.
    func noteDates(_ text: String, url: URL) -> (created: Date, updated: Date) {
        let fmDates = Self.frontmatterDates(text)
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return (fmDates.created ?? values?.creationDate ?? .distantPast,
                fmDates.updated ?? values?.contentModificationDate ?? .distantPast)
    }

    /// Dates + title from a header prefix (or full content).
    func noteMeta(content: String, url: URL) -> (created: Date, updated: Date, title: String) {
        let d = noteDates(content, url: url)
        return (d.created, d.updated, Self.noteTitle(content: content, url: url))
    }

    /// Read only the first `maxBytes` of a file (frontmatter + first heading live at the top), so
    /// metadata filtering doesn't have to read entire note bodies. Uncoordinated (read-only scan).
    func readHeader(_ url: URL, maxBytes: Int = 4096) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: read

    public func read(path: String, startLine: Int? = nil, endLine: Int? = nil, maxChars: Int = 40_000) -> ReadResult {
        guard let url = resolve(path) else {
            return ReadResult(path: nil, text: "Error: \"\(path)\" is outside the vault or invalid.", ok: false)
        }
        let rel = relativePath(url)
        guard fs.fileExists(at: url) else {
            return ReadResult(path: nil, text: "Error: no file at \"\(rel)\".", ok: false)
        }
        // Attempt the read first (a coordinated read materializes an iCloud file on demand). Only
        // fall back to the "not downloaded yet" message if the read genuinely fails.
        guard let content = fs.readString(from: url) ?? readForScan(url) else {
            if !fs.isDownloaded(at: url) {
                fs.startDownloading(at: url)
                return ReadResult(path: nil, text: "Note \"\(rel)\" is in iCloud and not downloaded yet; download was requested — try again shortly.", ok: false)
            }
            return ReadResult(path: nil, text: "Error: could not read \"\(rel)\".", ok: false)
        }

        let lines = content.components(separatedBy: "\n")
        let total = lines.count
        if startLine != nil || endLine != nil {
            let start = max(1, startLine ?? 1)
            let end = min(total, endLine ?? total)
            guard start <= end else {
                return ReadResult(path: rel, text: "// \(rel): empty range", ok: true)
            }
            let slice = lines[(start - 1)..<end].joined(separator: "\n")
            return ReadResult(path: rel, text: "// \(rel) (lines \(start)-\(end) of \(total))\n\(slice)", ok: true)
        }

        if content.count > maxChars {
            let truncated = String(content.prefix(maxChars))
            return ReadResult(path: rel,
                              text: "// \(rel) (truncated to first \(maxChars) chars of \(content.count); \(total) lines — request a line range for more)\n\(truncated)",
                              ok: true)
        }
        return ReadResult(path: rel, text: "// \(rel) (\(total) lines)\n\(content)", ok: true)
    }

    // MARK: list

    public func list(path: String? = nil) -> String {
        let dir: URL
        if let path, !path.isEmpty {
            guard let resolved = resolve(path) else { return "Error: \"\(path)\" is outside the vault or invalid." }
            dir = resolved
        } else {
            dir = root
        }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return "Error: could not list \"\(relativePath(dir))\"."
        }
        var dirs: [String] = []
        var notes: [String] = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                dirs.append(url.lastPathComponent + "/")
            } else if url.pathExtension.lowercased() == "md" {
                notes.append(url.lastPathComponent)
            }
        }
        dirs.sort(); notes.sort()
        let header = "// " + (path?.isEmpty == false ? path! : "/") + " — \(dirs.count) folders, \(notes.count) notes"
        let body = (dirs + notes).joined(separator: "\n")
        return body.isEmpty ? header + "\n(empty)" : header + "\n" + body
    }

    // MARK: Helpers

    /// Resolve a vault-relative path under root, rejecting escapes.
    func resolve(_ relative: String) -> URL? {
        var rel = relative.trimmingCharacters(in: .whitespaces)
        while rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty { return root }
        let url = root.appendingPathComponent(rel).standardizedFileURL
        let rootPath = root.path
        guard url.path == rootPath || url.path.hasPrefix(rootPath + "/") else { return nil }
        return url
    }

    func relativePath(_ url: URL) -> String {
        let std = url.standardizedFileURL.path
        let rootPath = root.path
        if std == rootPath { return "" }
        if std.hasPrefix(rootPath + "/") { return String(std.dropFirst(rootPath.count + 1)) }
        return url.lastPathComponent
    }

    /// Fast, uncoordinated read for scanning (grep) and as a read() fallback.
    private func readForScan(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    static func snippet(_ line: String, max: Int = 200) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > max ? String(trimmed.prefix(max)) + "…" : trimmed
    }

    static func format(hits: [GrepHit], query: String) -> String {
        guard !hits.isEmpty else { return "No matches for \"\(query)\"." }
        let lines = hits.map { "\($0.path):\($0.line): \($0.snippet)" }
        return "\(hits.count) match(es) for \"\(query)\":\n" + lines.joined(separator: "\n")
    }

    // Parse the model's JSON arguments string into a dictionary; tolerant of empties.
    static func parseArguments(_ json: String) -> [String: Any] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
    }

    // MARK: Dates

    static let isoInternet: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    static let isoDateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f
    }()
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Parse `created:` / `updated:` from a note's frontmatter (if present). Noto v2 writes `updated:`.
    static func frontmatterDates(_ content: String) -> (created: Date?, updated: Date?) {
        guard content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") else { return (nil, nil) }
        let lines = content.components(separatedBy: "\n")
        guard let open = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return (nil, nil) }
        let after = lines.dropFirst(open + 1)
        guard let close = after.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return (nil, nil) }
        var created: Date?
        var updated: Date?
        for line in lines[(open + 1)..<close] {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if key == "created" { created = isoInternet.date(from: value) }
            else if key == "updated" { updated = isoInternet.date(from: value) }
        }
        return (created, updated)
    }

    /// Title = first non-empty body line (heading markers stripped), else the filename.
    static func noteTitle(content: String, url: URL) -> String {
        var lines = content.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines = Array(lines[(close + 1)...])
        }
        for line in lines {
            var t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            while t.hasPrefix("#") { t.removeFirst() }
            t = t.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Parse an ISO date filter value (full datetime or `YYYY-MM-DD`).
    static func parseDate(_ any: Any?) -> Date? {
        guard let s = (any as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return isoInternet.date(from: s) ?? isoDateOnly.date(from: s)
    }

    static func parseDateFilter(_ args: [String: Any]) -> DateFilter {
        DateFilter(
            createdAfter: parseDate(args["created_after"]),
            createdBefore: parseDate(args["created_before"]),
            updatedAfter: parseDate(args["updated_after"]),
            updatedBefore: parseDate(args["updated_before"])
        )
    }

    static func format(notes: [NoteEntry]) -> String {
        guard !notes.isEmpty else { return "No notes match those filters." }
        let lines = notes.map {
            "\($0.path) — updated \(shortDate.string(from: $0.updated)), created \(shortDate.string(from: $0.created)) — \($0.title)"
        }
        return "\(notes.count) note(s), most recent first:\n" + lines.joined(separator: "\n")
    }
}
