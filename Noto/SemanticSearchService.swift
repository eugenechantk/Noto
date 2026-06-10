import Foundation
import NotoChat
import NotoEmbedding
import NotoSearch
import os.log

private let semanticServiceLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.noto",
    category: "SemanticSearchService"
)

/// Bridges the bundled Granite CoreML model into NotoSearch's `TextEmbedding`
/// protocol. The model (~100 MB of weights) loads lazily on first use and is
/// shared process-wide.
struct GraniteTextEmbedding: TextEmbedding {
    var modelVersion: String { GraniteEmbedder.modelVersion }
    var dimensions: Int { GraniteEmbedder.dimensions }

    func embed(_ texts: [String]) throws -> [[Float]] {
        try Self.sharedEmbedder().embed(texts)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var shared: GraniteEmbedder?

    static func sharedEmbedder() throws -> GraniteEmbedder {
        lock.lock()
        defer { lock.unlock() }
        if let shared { return shared }
        let embedder = try GraniteEmbedder.bundled()
        shared = embedder
        return embedder
    }
}

/// App-facing facade for the semantic side of search.
enum SemanticSearch {
    /// Wires the embedding model into the semantic index coordinator. Call once
    /// at startup; until this runs, all semantic operations are no-ops and the
    /// app behaves keyword-only.
    static func configureAtStartup() {
        Task.detached(priority: .utility) {
            await SemanticIndexCoordinator.shared.configure(
                embedding: GraniteTextEmbedding(),
                onChange: { vaultURL, result in
                    semanticServiceLogger.info(
                        "semantic index updated notes=\(result.refreshedNotes) chunks=\(result.embeddedChunks) deleted=\(result.deletedNotes)"
                    )
                    Task { @MainActor in
                        NotificationCenter.default.post(
                            name: .notoSearchIndexDidChange,
                            object: nil,
                            userInfo: ["vaultPath": vaultURL.standardizedFileURL.path]
                        )
                    }
                },
                onProgress: { _, _ in
                    // Feeds the Settings progress display while a sweep runs.
                    SearchIndexStatusModel.shared.noteSemanticProgress()
                }
            )
        }
    }

    /// Query-side entry: embed the query and scan the vault's semantic index.
    /// Returns `[]` whenever the semantic leg is unavailable (no model, no
    /// index yet, dimension mismatch mid-migration) — search degrades to
    /// keyword-only, never errors.
    static func hits(for query: String, vaultURL: URL, limit: Int = 50) -> [SemanticSearchHit] {
        do {
            guard let vector = try GraniteTextEmbedding().embed([query]).first else { return [] }
            return try sharedSearcher(for: vaultURL).search(queryVector: vector, limit: limit)
        } catch {
            semanticServiceLogger.debug("semantic query unavailable: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    // One searcher per vault keeps the in-memory vector matrix warm across
    // keystrokes; it self-invalidates via the store's generation counter.
    private static let searcherLock = NSLock()
    nonisolated(unsafe) private static var searchers: [String: SemanticSearcher] = [:]

    private static func sharedSearcher(for vaultURL: URL) -> SemanticSearcher {
        let key = vaultURL.standardizedFileURL.path
        searcherLock.lock()
        defer { searcherLock.unlock() }
        if let existing = searchers[key] { return existing }
        let searcher = SemanticSearcher(vaultURL: vaultURL)
        searchers[key] = searcher
        return searcher
    }
}

/// Bridges the chat agent's `search` tool onto the same hybrid pipeline the
/// search sheet uses (`HybridNoteSearch`): FTS keyword leg + semantic leg,
/// RRF-fused, with created/updated date filters applied to both legs.
struct HybridChatSearchProvider: ChatSearchProviding {
    let vaultURL: URL

    func search(_ request: ChatSearchRequest) throws -> [ChatSearchResult] {
        let results = try HybridNoteSearch.run(
            HybridNoteSearch.Request(
                query: request.query,
                dateFilter: SearchDateFilter(
                    createdAfter: request.filter.createdAfter,
                    createdBefore: request.filter.createdBefore,
                    updatedAfter: request.filter.updatedAfter,
                    updatedBefore: request.filter.updatedBefore
                ),
                limit: request.limit
            ),
            vaultURL: vaultURL,
            embedQuery: { query in
                // Model unavailable → keyword-only, never a tool failure.
                try? GraniteTextEmbedding().embed([query]).first
            }
        )

        let rootPath = vaultURL.standardizedFileURL.path
        return results.map { result in
            let filePath = result.fileURL.standardizedFileURL.path
            let relativePath = filePath.hasPrefix(rootPath + "/")
                ? String(filePath.dropFirst(rootPath.count + 1))
                : result.fileURL.lastPathComponent
            return ChatSearchResult(
                path: relativePath,
                title: result.title,
                snippet: result.snippet,
                lineStart: result.lineStart,
                kind: result.kind == .section ? "section" : "note",
                createdAt: result.createdAt,
                updatedAt: result.updatedAt
            )
        }
    }
}
