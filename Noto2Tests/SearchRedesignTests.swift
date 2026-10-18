import Foundation
import NotoSearch
import NotoVault
import Synchronization
import SwiftUI
import Testing
@testable import Noto2

@MainActor
struct SearchRedesignTests {
    @Test func controlledPresentationRequiresAnExplicitDebugArgument() {
        #if DEBUG
        #expect(SearchVerificationState.requested(arguments: ["--search-preview-state=recent-loading"]) == .recentLoading)
        #expect(SearchVerificationState.requested(arguments: ["--search-preview-state=recent-error"]) == .recentError)
        #expect(SearchVerificationState.requested(arguments: ["--search-preview-state=partial-index"]) == .partialIndex)
        #else
        #expect(SearchVerificationState.requested(arguments: ["--search-preview-state=recent-error"]) == nil)
        #endif
        #expect(SearchVerificationState.requested(arguments: []) == nil)
        #expect(SearchVerificationState.requested(arguments: ["--search-preview-state=unknown"]) == nil)
        #expect(SearchVerificationState.recentLoading.hidesRecentRows)
        #expect(!SearchVerificationState.partialIndex.hidesRecentRows)
    }

    @Test func recentlyEditedUsesSevenNewestPagesIncludingPinsAndRefreshesAfterEdits() async throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("SearchRecent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        func write(_ path: String, age: TimeInterval, pinned: Bool = false) throws -> URL {
            let url = vault.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let title = url.deletingPathExtension().lastPathComponent
            try "---\nid: \(UUID().uuidString)\npinned: \(pinned)\n---\n# \(title)\n\nWriting here."
                .write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: clock.addingTimeInterval(-age)], ofItemAtPath: url.path)
            return url
        }
        for number in 0..<9 { _ = try write("Projects/Note \(number).md", age: Double(number * 60), pinned: number == 0) }
        _ = try write("inbox/Fresh capture.md", age: -60)
        _ = try write(".hidden/Secret.md", age: -120)

        let model = SearchModel(vaultURL: vault)
        await model.refreshRecentNotes()
        #expect(model.recentNotes.map(\.note.title) == (0..<7).map { "Note \($0)" })
        #expect(model.recentNotes.first?.isPinned == true)
        #expect(model.recentNotes.first?.folderPath == "Projects")
        #expect(model.recentLoadError == nil)
        #expect(!model.isLoadingRecent)

        _ = try write("Projects/Note 8.md", age: -180)
        await model.refreshRecentNotes()
        #expect(model.recentNotes.first?.note.title == "Note 8")
        #expect(model.recentNotes.count == 7)
    }

    @Test func navigationKeepsFindOnlyForTheRequestedOpen() throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("SearchRoute-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let url = vault.appendingPathComponent("Media.md")
        try "# Media\n\nThe media mirror.".write(to: url, atomically: true, encoding: .utf8)
        let controller = VaultController(vaultURL: vault, autoloadRoot: false)
        let destination = try #require(BrowseDestination.note(at: url, in: controller))
        #expect(SearchNavigation(destination: destination, query: "  media mirror \n").initialFindQuery == "media mirror")
        #expect(SearchNavigation(destination: destination).initialFindQuery == nil)
        #expect(SearchNavigation(destination: destination, query: " \n").initialFindQuery == nil)
    }

    @Test func displayIdentityMatchesLibraryWithoutChangingTheHit() throws {
        let root = URL(fileURLWithPath: "/fixture")
        let url = root.appendingPathComponent("Media mirror plan.md")
        let markdown = "---\nid: 47227910-3871-4E1F-A683-6A6ED7F74F4A\n---\nMedia mirror plan\n\n## Why\nThe media mirror is useful."
        let hit = SearchResult(id: UUID(), kind: .note, noteID: UUID(), fileURL: url, title: "Why",
                               breadcrumb: "Vault", snippet: "The media mirror is useful.", lineStart: 7, score: 0.9, updatedAt: nil)
        let mapped = SearchResultDisplayTitles.resolving([hit]) { VaultMarkdown.displayTitle(for: $0, content: markdown) }
        #expect(mapped.first?.title == "Media mirror plan")
        #expect(mapped.first?.id == hit.id)
        #expect(mapped.first?.lineStart == hit.lineStart)
        #expect(VaultMarkdown.displayTitle(for: url, content: "# Heading\n\n## Later") == "Heading")
        #expect(VaultMarkdown.displayTitle(for: url, content: "") == "Media mirror plan")
    }
    @Test func latestQueryWinsAndRefreshPreservesTheQuery() async throws {
        let calls = SearchCalls()
        let model = SearchModel(vaultURL: URL(fileURLWithPath: "/fixture")) { query, root in
            calls.queries.withLock { $0.append(query) }
            return [SearchResult(id: UUID(), kind: .note, noteID: UUID(), fileURL: root.appendingPathComponent("Note.md"),
                                 title: query, breadcrumb: "", snippet: "matching text", lineStart: 2, score: 1, updatedAt: nil)]
        }
        model.query = "old query"
        model.query = "  current query  "
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while model.isSearching && clock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isSearching)
        #expect(model.lastSearchedQuery == "current query")
        #expect(model.results.map(\.title) == ["current query"])
        #expect(calls.queries.withLock { $0 } == ["current query"])
        model.refresh()
        let refreshDeadline = clock.now.advanced(by: .seconds(2))
        while model.isSearching && clock.now < refreshDeadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isSearching)
        #expect(model.query == "  current query  ")
        #expect(model.lastSearchedQuery == "current query")
        #expect(calls.queries.withLock { $0 } == ["current query", "current query"])
    }

    @Test func clearingQueryCancelsPendingSearch() async throws {
        let calls = SearchCalls()
        let model = SearchModel(vaultURL: URL(fileURLWithPath: "/fixture")) { query, _ in
            calls.queries.withLock { $0.append(query) }
            return []
        }
        model.query = "pending"
        #expect(model.isSearching)
        model.query = " \n"
        #expect(!model.isSearching)
        #expect(model.lastSearchedQuery.isEmpty)
        #expect(model.results.isEmpty)
        // A quiet interval beyond the debounce catches a cancelled query being
        // republished later; the production scheduler remains unchanged.
        try await Task.sleep(for: .milliseconds(350))
        #expect(calls.queries.withLock { $0 }.isEmpty)
        #expect(model.lastSearchedQuery.isEmpty)
        #expect(!model.isSearching)
    }

    private final class SearchCalls: Sendable {
        let queries = Mutex<[String]>([])
    }

}
