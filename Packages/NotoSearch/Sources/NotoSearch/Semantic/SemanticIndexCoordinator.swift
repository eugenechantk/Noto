import Foundation
import os.log

private let semanticCoordinatorLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.noto.NotoSearch",
    category: "SemanticIndexCoordinator"
)

/// Serializes semantic index refreshes per vault: single-flight, debounced,
/// cancellable. Mirrors `SearchIndexCoordinator`'s role for the FTS index.
///
/// Until `configure(embedding:onChange:)` runs, every call is a no-op — the
/// app works keyword-only when no embedding model is available.
public actor SemanticIndexCoordinator {
    public static let shared = SemanticIndexCoordinator()

    public struct Progress: Sendable, Equatable {
        public let processed: Int
        public let total: Int
        public var isFinished: Bool { processed >= total }
    }

    private var embedding: (any TextEmbedding)?
    private var onChange: (@Sendable (URL, SemanticRefreshResult) -> Void)?
    private var onProgress: (@Sendable (URL, Progress) -> Void)?
    private let debounceDelay: Duration

    private var runningTasks: [String: Task<SemanticRefreshResult, Error>] = [:]
    private var scheduledTasks: [String: Task<Void, Never>] = [:]

    public init(debounceDelay: Duration = .milliseconds(1_500)) {
        self.debounceDelay = debounceDelay
    }

    public func configure(
        embedding: any TextEmbedding,
        onChange: (@Sendable (URL, SemanticRefreshResult) -> Void)? = nil,
        onProgress: (@Sendable (URL, Progress) -> Void)? = nil
    ) {
        self.embedding = embedding
        self.onChange = onChange
        self.onProgress = onProgress
    }

    public var isConfigured: Bool { embedding != nil }

    /// Debounced refresh: bursts of FTS updates collapse into one semantic
    /// sweep after the vault settles.
    public func scheduleRefresh(vaultURL: URL) {
        guard embedding != nil else { return }
        let key = vaultKey(for: vaultURL)
        scheduledTasks[key]?.cancel()
        let delay = debounceDelay
        scheduledTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            _ = try? await self.refresh(vaultURL: vaultURL)
            await self.clearScheduledTask(for: key)
        }
    }

    /// Single-flight refresh; concurrent callers await the in-flight run.
    @discardableResult
    public func refresh(vaultURL: URL) async throws -> SemanticRefreshResult {
        try await runSweep(vaultURL: vaultURL, rebuild: false)
    }

    /// Destroy + re-embed everything. Cancels in-flight work first.
    @discardableResult
    public func rebuild(vaultURL: URL) async throws -> SemanticRefreshResult {
        let key = vaultKey(for: vaultURL)
        runningTasks[key]?.cancel()
        runningTasks[key] = nil
        scheduledTasks[key]?.cancel()
        scheduledTasks[key] = nil
        return try await runSweep(vaultURL: vaultURL, rebuild: true)
    }

    public func stats(vaultURL: URL) -> SemanticIndexStats? {
        let directory = MarkdownSearchIndexer.defaultIndexDirectory(for: vaultURL)
        return try? SemanticIndexStore(indexDirectory: directory).stats()
    }

    private func runSweep(vaultURL: URL, rebuild: Bool) async throws -> SemanticRefreshResult {
        guard let embedding else {
            let directory = MarkdownSearchIndexer.defaultIndexDirectory(for: vaultURL)
            let stats = (try? SemanticIndexStore(indexDirectory: directory).stats())
                ?? SemanticIndexStats(noteCount: 0, chunkCount: 0, modelVersion: nil)
            return SemanticRefreshResult(
                scannedNotes: 0, refreshedNotes: 0, embeddedChunks: 0,
                reusedChunks: 0, deletedNotes: 0, stats: stats
            )
        }

        let key = vaultKey(for: vaultURL)
        if !rebuild, let task = runningTasks[key] {
            return try await task.value
        }

        let onProgress = onProgress
        let task = Task.detached(priority: .utility) {
            let indexer = SemanticIndexer(vaultURL: vaultURL, embedding: embedding)
            let work: @Sendable (_ shouldContinue: @escaping @Sendable () -> Bool) throws -> SemanticRefreshResult = { shouldContinue in
                if rebuild {
                    return try indexer.rebuild(shouldContinue: shouldContinue) { processed, total in
                        onProgress?(vaultURL, Progress(processed: processed, total: total))
                    }
                }
                return try indexer.refreshFromSearchIndex(shouldContinue: shouldContinue) { processed, total in
                    onProgress?(vaultURL, Progress(processed: processed, total: total))
                }
            }
            return try work { !Task.isCancelled }
        }
        runningTasks[key] = task

        do {
            let result = try await task.value
            runningTasks[key] = nil
            if result.didChangeIndex {
                semanticCoordinatorLogger.info(
                    "semantic refresh refreshed=\(result.refreshedNotes) embedded=\(result.embeddedChunks) deleted=\(result.deletedNotes)"
                )
                onChange?(vaultURL, result)
            }
            return result
        } catch {
            runningTasks[key] = nil
            throw error
        }
    }

    private func clearScheduledTask(for key: String) {
        scheduledTasks[key] = nil
    }

    private func vaultKey(for vaultURL: URL) -> String {
        vaultURL.standardizedFileURL.path
    }
}
