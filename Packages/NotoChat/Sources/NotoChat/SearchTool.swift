import Foundation

// MARK: - Search provider abstraction

/// A hybrid (keyword + semantic) note search request from the chat agent.
public struct ChatSearchRequest: Sendable, Equatable {
    public let query: String
    public let filter: DateFilter
    /// Restricts results to notes inside this vault folder (vault-relative,
    /// any depth). Nil = whole vault.
    public let folder: String?
    public let limit: Int

    public init(query: String, filter: DateFilter = .init(), folder: String? = nil, limit: Int = 12) {
        self.query = query
        self.filter = filter
        self.folder = folder
        self.limit = limit
    }
}

public struct ChatSearchResult: Sendable, Equatable {
    public let path: String        // vault-relative
    public let title: String
    public let snippet: String
    public let lineStart: Int?     // set for section-level hits
    public let kind: String        // "note" | "section"
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        path: String,
        title: String,
        snippet: String,
        lineStart: Int?,
        kind: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.path = path
        self.title = title
        self.snippet = snippet
        self.lineStart = lineStart
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Injected by the app layer: runs the SAME hybrid pipeline as the in-app
/// search sheet (FTS keyword leg + on-device semantic leg, RRF-fused, with
/// created/updated date filters applied to both legs). NotoChat itself stays
/// decoupled from the search index and the embedding model.
public protocol ChatSearchProviding: Sendable {
    func search(_ request: ChatSearchRequest) throws -> [ChatSearchResult]
}

// MARK: - Tool surface

extension VaultTools {
    static let searchDefinition = ToolDefinition(function: .init(
        name: "search",
        description: "Ranked hybrid search over the vault — combines keyword matching with semantic "
            + "(meaning-based) search, so it finds relevant notes even when their wording differs from "
            + "the query (including across languages). Returns the best snippets and documents, most "
            + "relevant first. Supports date filters on the note's created and last-updated timestamps; "
            + "pass ISO dates (YYYY-MM-DD) and compute cutoffs like 'last 5 days' from today's date. "
            + "Also supports a folder filter to search only inside one vault folder (e.g. the user asks "
            + "about 'my Captures' or 'the Projects folder') — use the list tool if you need to discover "
            + "exact folder names first. Prefer this over grep for finding notes about a topic; use grep "
            + "only for exact strings/substrings or pure date-filtered listings.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("What to search for — a topic, phrase, or question. Required.")
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
                    "description": .string("Only notes last updated on/after this ISO date (YYYY-MM-DD).")
                ]),
                "updated_before": .object([
                    "type": .string("string"),
                    "description": .string("Only notes last updated on/before this ISO date (YYYY-MM-DD).")
                ]),
                "folder": .object([
                    "type": .string("string"),
                    "description": .string("Only notes inside this vault folder, at any depth — a vault-relative folder path like \"Captures\" or \"Projects/Alpha\". Omit to search the whole vault.")
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum results to return (default 12, max 30).")
                ])
            ]),
            "required": .array([.string("query")])
        ])
    ))

    /// Executes a parsed `search` tool call against the injected provider.
    func runSearch(_ args: [String: Any]) -> ToolRunResult {
        guard let provider = searchProvider else {
            return .init(output: "Error: search is not available in this session — use grep instead.",
                         readPath: nil, summary: "search: unavailable")
        }
        guard let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            return .init(output: "Error: search requires a non-empty \"query\".",
                         readPath: nil, summary: "search: bad args")
        }
        let filter = Self.parseDateFilter(args)
        let folder = (args["folder"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFolder = (folder?.isEmpty ?? true) ? nil : folder
        let limit = min(max(Self.intValue(args["limit"]) ?? 12, 1), 30)

        let results: [ChatSearchResult]
        do {
            results = try provider.search(ChatSearchRequest(query: query, filter: filter, folder: normalizedFolder, limit: limit))
        } catch {
            return .init(output: "Error: search failed (\(String(describing: error))). Try grep instead.",
                         readPath: nil, summary: "search: failed")
        }

        let files = results.map(\.path).reduce(into: [String]()) { seen, path in
            if !seen.contains(path) { seen.append(path) }
        }
        let noteCount = files.count
        return .init(
            output: Self.format(searchResults: results, query: query, filter: filter, folder: normalizedFolder),
            readPath: nil,
            summary: "\(results.count) result\(results.count == 1 ? "" : "s") in \(noteCount) note\(noteCount == 1 ? "" : "s")",
            surfacedPaths: files,
            hits: results.prefix(8).map { GrepHit(path: $0.path, line: $0.lineStart ?? 1, snippet: $0.snippet) }
        )
    }

    static func format(searchResults: [ChatSearchResult], query: String, filter: DateFilter, folder: String? = nil) -> String {
        var parts: [String] = []
        if let folder { parts.append("folder \(folder)") }
        if filter.isActive {
            if let d = filter.createdAfter { parts.append("created_after \(shortDate.string(from: d))") }
            if let d = filter.createdBefore { parts.append("created_before \(shortDate.string(from: d))") }
            if let d = filter.updatedAfter { parts.append("updated_after \(shortDate.string(from: d))") }
            if let d = filter.updatedBefore { parts.append("updated_before \(shortDate.string(from: d))") }
        }
        let filterNote = parts.isEmpty ? "" : " (" + parts.joined(separator: ", ") + ")"
        guard !searchResults.isEmpty else {
            return "No results for \"\(query)\"\(filterNote). Try broader wording, removing the folder/date filters, or grep for exact strings."
        }
        let lines = searchResults.enumerated().map { index, result -> String in
            let location = result.lineStart.map { "\(result.path):\($0)" } ?? result.path
            let updated = result.updatedAt.map { " — updated \(shortDate.string(from: $0))" } ?? ""
            return "\(index + 1). \(location) [\(result.kind)] \(result.title)\(updated)\n   \(result.snippet)"
        }
        return "\(searchResults.count) result(s) for \"\(query)\"\(filterNote), most relevant first:\n"
            + lines.joined(separator: "\n")
    }
}
