import Foundation
import NotoChat
import NotoSearch
import Observation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "SearchModel")

/// Drives the Search tab: debounced hybrid (keyword ∪ semantic) search against
/// this app's local index, then a streamed LLM summary over the top hits.
/// A new query cancels both the in-flight search and the in-flight stream.
@Observable
@MainActor
final class SearchModel {
    enum SummaryOrigin: Equatable {
        case remoteAI
        case offlineHighlights
    }

    enum SummaryState: Equatable {
        case idle
        case needsKey
        case streaming
        case done
        case failed(String)
    }

    let vaultURL: URL
    var query: String = "" {
        didSet { queryChanged() }
    }
    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    private(set) var lastSearchedQuery = ""
    private(set) var summary = ""
    private(set) var summaryState: SummaryState = .idle
    private(set) var summaryOrigin: SummaryOrigin = .remoteAI
    private(set) var hasAIKey = false
    /// How many notes fed the current summary (for the provenance line).
    private(set) var summarySourceCount = 0

    /// Why the summary fell back to offline highlights, in a few words.
    /// Shown next to the provenance line — a silent downgrade is why this reads
    /// as "the AI summary doesn't work" rather than "the request failed".
    private(set) var summaryFallbackReason: String?

    private var searchTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private let debounce: Duration = .milliseconds(220)
    /// Query + note set the current summary was built from, so a re-run that
    /// lands on the same answer can leave the stream alone.
    private var summarizedQuery: String?
    private var summarizedNoteIDs: [UUID] = []

    init(vaultURL: URL) {
        self.vaultURL = vaultURL
    }

    func retrySummary() {
        summarizedQuery = lastSearchedQuery
        summarizedNoteIDs = results.map(\.noteID)
        startSummary(for: lastSearchedQuery, results: results)
    }

    /// Re-run after an external change (index updated, key saved).
    func refresh() {
        queryChanged(immediate: true)
    }

    private func queryChanged(immediate: Bool = false) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only a genuinely different query invalidates the summary. `refresh()`
        // re-runs the *same* query whenever the index changes, and while a vault
        // is still downloading/indexing that fires repeatedly — cancelling the
        // multi-second LLM stream each time meant the summary never landed and
        // the user only ever saw the offline highlights.
        if trimmed != summarizedQuery {
            summaryTask?.cancel()
            summary = ""
            summaryState = .idle
            summaryFallbackReason = nil
            summarizedQuery = nil
            summarizedNoteIDs = []
        }
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            lastSearchedQuery = ""
            return
        }
        isSearching = true
        let vaultURL = vaultURL
        let debounce = debounce
        searchTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }
            let hits = await Task.detached(priority: .userInitiated) {
                Self.runSearch(query: trimmed, vaultURL: vaultURL)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.results = hits
            self.isSearching = false
            self.lastSearchedQuery = trimmed
            self.startSummaryIfNeeded(for: trimmed, results: hits)
        }
    }

    /// Leaves a streaming or finished summary alone when the re-run produced the
    /// same query and the same notes — there is nothing new to summarize, and
    /// restarting would throw away work that takes seconds to redo.
    private func startSummaryIfNeeded(for query: String, results: [SearchResult]) {
        let noteIDs = results.map(\.noteID)
        guard Self.shouldStartSummary(
            summarizedQuery: summarizedQuery,
            summarizedNoteIDs: summarizedNoteIDs,
            state: summaryState,
            query: query,
            noteIDs: noteIDs
        ) else { return }
        summarizedQuery = query
        summarizedNoteIDs = noteIDs
        startSummary(for: query, results: results)
    }

    /// A summary is worth (re)starting unless one is already streaming or done
    /// for this exact query and note set. `refresh()` re-runs the same query on
    /// every index change; on a vault that is still filling, that fires
    /// repeatedly and used to cancel the in-flight stream every time.
    nonisolated static func shouldStartSummary(
        summarizedQuery: String?,
        summarizedNoteIDs: [UUID],
        state: SummaryState,
        query: String,
        noteIDs: [UUID]
    ) -> Bool {
        let inFlightOrDone = state == .streaming || state == .done
        let sameAnswer = summarizedQuery == query && summarizedNoteIDs == noteIDs
        return !(inFlightOrDone && sameAnswer)
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

    nonisolated private static func runSearch(query: String, vaultURL: URL) -> [SearchResult] {
        do {
            let fused = try HybridNoteSearch.run(
                makeRequest(query: query),
                vaultURL: vaultURL,
                embedQuery: { text in try? GraniteTextEmbedding().embed([text]).first }
            )
            return dedupedByNote(fused)
        } catch {
            logger.error("search failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func startSummary(for query: String, results: [SearchResult]) {
        summaryTask?.cancel()
        summary = ""
        summaryOrigin = .remoteAI
        guard !results.isEmpty else {
            summaryState = .idle
            return
        }
        let apiKey = OpenRouterKeyStore.resolvedKey()
        hasAIKey = apiKey?.isEmpty == false
        let configuredBaseURL = OpenRouterBaseURLStore.resolved()
        summaryState = .streaming
        let vaultURL = vaultURL
        summaryTask = Task { [weak self] in
            let sources = await Task.detached(priority: .userInitiated) {
                SummaryPromptBuilder.sources(from: results, vaultURL: vaultURL) { url in
                    CoordinatedFileManager.readString(from: url)
                }
            }.value
            guard !Task.isCancelled, let self else { return }
            guard let request = SummaryPromptBuilder.request(query: query, sources: sources) else {
                self.summaryState = .idle
                return
            }
            self.summarySourceCount = sources.count
            let offlineSummary = ExtractiveSearchSummary.text(
                query: query,
                sources: sources.map { .init(title: $0.title, body: $0.body) }
            )

            guard let apiKey, !apiKey.isEmpty else {
                self.applyOfflineSummary(offlineSummary, missingKey: true, reason: "no API key")
                return
            }

            var lastError: Error?
            for baseURL in Self.summaryBaseURLs(configured: configuredBaseURL) {
                self.summary = ""
                let client = OpenRouterClient(configuration: .init(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    referer: "https://noto.app",
                    title: "Noto 2"
                ))
                do {
                    for try await event in client.stream(request) {
                        guard !Task.isCancelled else { return }
                        if case .textDelta(let delta) = event {
                            self.summary += delta
                        }
                    }
                    guard !self.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw LLMError.emptyResponse
                    }
                    guard !Task.isCancelled else { return }
                    self.summaryOrigin = .remoteAI
                    self.summaryState = .done
                    return
                } catch is CancellationError {
                    return
                } catch {
                    lastError = error
                    logger.error(
                        "summary route failed host=\(baseURL.host ?? "unknown", privacy: .public) error=\(Self.describe(error), privacy: .public)"
                    )
                }
            }

            guard !Task.isCancelled else { return }
            if !offlineSummary.isEmpty {
                self.applyOfflineSummary(
                    offlineSummary,
                    missingKey: false,
                    reason: lastError.map(Self.shortReason) ?? "request failed"
                )
            } else {
                self.summaryState = .failed(lastError.map(Self.describe) ?? "Summary unavailable")
            }
        }
    }

    /// A stale proxy override should not strand the feature after the direct
    /// OpenRouter route becomes reachable again. Conversely, the override stays
    /// first so it still solves a genuinely blocked direct route.
    nonisolated static func summaryBaseURLs(configured: URL) -> [URL] {
        configured == OpenRouterBaseURLStore.defaultBaseURL
            ? [configured]
            : [configured, OpenRouterBaseURLStore.defaultBaseURL]
    }

    private func applyOfflineSummary(_ offlineSummary: String, missingKey: Bool, reason: String) {
        guard !offlineSummary.isEmpty else {
            summaryState = missingKey ? .needsKey : .failed("Summary unavailable")
            return
        }
        summary = offlineSummary
        summaryOrigin = .offlineHighlights
        summaryFallbackReason = reason
        summaryState = .done
    }

    /// A few words the user can act on, not a stack trace. The offline summary
    /// looks identical whether the key is wrong, the account is out of credit,
    /// or the phone briefly lost signal — those need different responses.
    nonisolated static func shortReason(for error: Error) -> String {
        if let llm = error as? LLMError {
            switch llm {
            case .missingAPIKey: return "no API key"
            case .emptyResponse: return "empty response"
            case .decoding: return "unreadable response"
            case .http(let status, _):
                switch status {
                case 401, 403: return "key rejected"
                case 402: return "out of credits"
                case 429: return "rate limited"
                case 500...599: return "provider error \(status)"
                default: return "HTTP \(status)"
                }
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost: return "no network"
            case .timedOut: return "timed out"
            case .cancelled: return "interrupted"
            default: return "network error"
            }
        }
        return "request failed"
    }

    private static func describe(_ error: Error) -> String {
        let text = "\(error)"
        return text.count > 240 ? String(text.prefix(240)) + "…" : text
    }
}
