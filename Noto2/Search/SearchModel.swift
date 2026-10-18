import Foundation
import NotoSearch
import NotoVault
import Observation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "SearchModel")

/// Drives local, debounced hybrid search. The model publishes note results only;
/// query changes cancel pending work and never request a generated answer.
@Observable
@MainActor
final class SearchModel {
    let vaultURL: URL
    var query: String = "" {
        didSet { queryChanged() }
    }
    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    private(set) var lastSearchedQuery = ""
    private(set) var recentNotes: [LibraryNote] = []
    private(set) var isLoadingRecent = false
    private(set) var recentLoadError: String?
    private var searchTask: Task<Void, Never>?
    private let debounce: Duration = .milliseconds(220)
    private let search: @Sendable (String, URL) -> [SearchResult]

    init(vaultURL: URL, search: @escaping @Sendable (String, URL) -> [SearchResult] = SearchModel.runSearch) {
        self.vaultURL = vaultURL
        self.search = search
    }

    func refreshRecentNotes() async {
        isLoadingRecent = true
        let root = vaultURL
        let loaded = await Task.detached(priority: .userInitiated) {
            Result { try LibraryCatalog(vaultRootURL: root).load() }
        }.value
        guard !Task.isCancelled else { return }
        isLoadingRecent = false
        switch loaded {
        case .success(let snapshot):
            // The Library's Recent section omits pins. Search includes every page.
            recentNotes = Array(snapshot.notes.prefix(7))
            recentLoadError = nil
        case .failure:
            recentLoadError = "Recently edited notes could not be loaded."
        }
    }

    /// Re-run after the local index changes.
    func refresh() {
        queryChanged(immediate: true)
    }

    private func queryChanged(immediate: Bool = false) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            lastSearchedQuery = ""
            return
        }
        isSearching = true
        let vaultURL = vaultURL
        let debounce = debounce
        let search = search
        searchTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }
            let hits = await Task.detached(priority: .userInitiated) {
                search(trimmed, vaultURL)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.results = hits
            self.isSearching = false
            self.lastSearchedQuery = trimmed
        }
    }

    /// Granite's cosine floor is high (unrelated ≈ 0.70, related ≈ 0.80+, measured
    /// 2026-08-23), so semantic hits must clear 0.76 *and* sit within 0.12 of the
    /// best hit; otherwise every note in a small vault surfaces as a "meaning" match.
    static let semanticMinScore: Float = 0.76
    static let semanticRelativeGap: Float = 0.12
    /// Gibberish peaks ≈0.04–0.05 above the corpus median, real queries ≥0.11
    /// (measured 2026-08-24), so 0.07 keeps the no-results state reachable.
    static let semanticPeakMargin: Float = 0.07

    nonisolated static func makeRequest(query: String) -> HybridNoteSearch.Request {
        HybridNoteSearch.Request(
            query: query,
            scope: .titleAndContent,
            limit: 60,
            semanticMinScore: semanticMinScore,
            semanticRelativeGap: semanticRelativeGap,
            semanticPeakMargin: semanticPeakMargin
        )
    }

    /// One row per note: the fused list can carry a note twice (note + section
    /// hit). Noto 2 shows one row per note — preferring a row whose snippet says
    /// more than the title — in the note's first-appearance order.
    nonisolated static func dedupedByNote(_ results: [SearchResult]) -> [SearchResult] {
        var order: [UUID] = []
        var chosen: [UUID: SearchResult] = [:]
        for result in results {
            if let current = chosen[result.noteID] {
                let currentIsBare = current.snippet.isEmpty || current.snippet == current.title
                let candidateIsBare = result.snippet.isEmpty || result.snippet == result.title
                if currentIsBare && !candidateIsBare { chosen[result.noteID] = result }
            } else {
                order.append(result.noteID)
                chosen[result.noteID] = result
            }
        }
        return order.compactMap { chosen[$0] }
    }

    nonisolated static func runSearch(query: String, vaultURL: URL) -> [SearchResult] {
        do {
            let fused = try HybridNoteSearch.run(
                makeRequest(query: query),
                vaultURL: vaultURL,
                embedQuery: { text in try? GraniteTextEmbedding().embed([text]).first }
            )
            // Dedupe first: changing presentation titles must not affect selection.
            return SearchResultDisplayTitles.resolving(dedupedByNote(fused)) { url in
                guard let content = CoordinatedFileManager.readString(from: url) else { return nil }
                return VaultMarkdown.displayTitle(for: url, content: content)
            }
        } catch {
            logger.error("search failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

}
