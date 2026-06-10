import Foundation
import NotoSearch
import SwiftUI

/// Live status of both search indexes for the Settings screen.
///
/// The keyword (FTS) index finishes within seconds of launch, so its note
/// count doubles as the vault total; the semantic index trails it while
/// embedding, and "semantic notes / keyword notes" is the honest progress
/// fraction. Counts poll while the screen is visible and refresh on index
/// change notifications; the semantic sweep also pings progress directly.
@MainActor
final class SearchIndexStatusModel: ObservableObject {
    static let shared = SearchIndexStatusModel()

    @Published private(set) var keywordNotes: Int?
    @Published private(set) var keywordSections: Int?
    @Published private(set) var semanticNotes: Int?
    @Published private(set) var semanticChunks: Int?
    @Published private(set) var semanticLastProgressAt: Date?
    /// Markdown files actually in the vault — the denominator for both rows.
    @Published private(set) var vaultNotes: Int?

    private var vaultURL: URL?
    private var pollTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    /// True while the semantic index is visibly behind the keyword index or a
    /// sweep reported progress in the last few seconds.
    var isSemanticIndexing: Bool {
        if let lastProgress = semanticLastProgressAt, Date().timeIntervalSince(lastProgress) < 10 {
            return true
        }
        guard let semanticNotes, let keywordNotes, keywordNotes > 0 else { return false }
        return semanticNotes < keywordNotes
    }

    var semanticFraction: Double? {
        guard let semanticNotes, let total = vaultNotes ?? keywordNotes, total > 0 else { return nil }
        return min(1, Double(semanticNotes) / Double(total))
    }

    var isKeywordPartial: Bool {
        guard let keywordNotes, let vaultNotes, vaultNotes > 0 else { return false }
        return keywordNotes < vaultNotes
    }

    var isSemanticPartial: Bool {
        guard let semanticNotes, let total = vaultNotes ?? keywordNotes, total > 0 else { return false }
        return semanticNotes < total
    }

    /// Shows the resume button: an index is behind the vault and no sweep has
    /// reported progress very recently.
    var isAnyIndexPartial: Bool {
        isKeywordPartial || isSemanticPartial
    }

    var keywordSummary: String {
        guard let keywordNotes, let keywordSections else { return "indexing…" }
        if let vaultNotes {
            return "\(keywordNotes) / \(vaultNotes) notes · \(keywordSections) sections"
        }
        return "\(keywordNotes) notes · \(keywordSections) sections"
    }

    var semanticSummary: String {
        guard let semanticNotes, let semanticChunks else { return "waiting…" }
        if let total = vaultNotes ?? keywordNotes {
            return "\(semanticNotes) / \(total) notes · \(semanticChunks) chunks"
        }
        return "\(semanticNotes) notes · \(semanticChunks) chunks"
    }

    /// Called from the semantic sweep's progress callback (any thread).
    nonisolated func noteSemanticProgress() {
        Task { @MainActor in
            self.semanticLastProgressAt = Date()
        }
    }

    /// Begin polling for a vault. Safe to call repeatedly (Settings onAppear).
    func start(vaultURL: URL) {
        self.vaultURL = vaultURL
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: .notoSearchIndexDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshCounts() }
            }
        }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshCounts()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Stop the visible-screen polling (Settings onDisappear). Notification
    /// observation stays active so counts are fresh on the next appearance.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refreshCounts() {
        guard let vaultURL else { return }
        Task.detached(priority: .utility) {
            let indexDirectory = MarkdownSearchIndexer.defaultIndexDirectory(for: vaultURL)
            let keyword = try? SearchIndexStore(indexDirectory: indexDirectory).stats()
            let semantic = try? SemanticIndexStore(indexDirectory: indexDirectory).stats()
            let vaultCount = Self.countVaultNotes(vaultURL: vaultURL)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let keyword {
                    self.keywordNotes = keyword.noteCount
                    self.keywordSections = keyword.sectionCount
                }
                if let semantic {
                    self.semanticNotes = semantic.noteCount
                    self.semanticChunks = semantic.chunkCount
                }
                if let vaultCount {
                    self.vaultNotes = vaultCount
                }
            }
        }
    }

    /// Counts the vault's markdown files with the same visibility rules the
    /// indexer uses (skip hidden files and dot-directories).
    nonisolated private static func countVaultNotes(vaultURL: URL) -> Int? {
        guard let enumerator = FileManager.default.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var count = 0
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if url.lastPathComponent.hasPrefix(".") {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension.lowercased() == "md", !url.lastPathComponent.hasPrefix(".") {
                count += 1
            }
        }
        return count
    }
}
