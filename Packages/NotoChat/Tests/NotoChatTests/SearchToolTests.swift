import Foundation
import Testing
@testable import NotoChat

/// Test case index
/// 1. testSearchAdvertisedOnlyWithProvider — tool list gains `search` iff a provider is injected (SC12)
/// 2. testDispatchParsesQueryDatesAndLimit — args map onto ChatSearchRequest (ISO dates, limit clamp) (SC12)
/// 3. testMissingQueryReturnsError — self-correctable error text, no provider call (SC12)
/// 4. testProviderFailureReturnsErrorText — tool errors degrade to text, never throw (SC12)
/// 5. testOutputFormatAndSurfacedPaths — ranked output, dedup'd surfaced paths, hits capped at 8 (SC12)
/// 6. testNoResultsMessageMentionsFilters — empty result guidance includes the active filter (SC12)
/// 7. testFolderArgumentReachesProvider — `folder` arg lands on ChatSearchRequest.folder; blank folder → nil (feature: search-folder-filter SC4)
/// 8. testFolderAppearsInOutputAndNoResultsMessage — formatted header and empty-result guidance name the folder (SC4)
struct SearchToolTests {
    private final class RecordingProvider: ChatSearchProviding, @unchecked Sendable {
        var lastRequest: ChatSearchRequest?
        var results: [ChatSearchResult] = []
        var error: Error?

        func search(_ request: ChatSearchRequest) throws -> [ChatSearchResult] {
            lastRequest = request
            if let error { throw error }
            return results
        }
    }

    private func makeTools(provider: RecordingProvider?) throws -> VaultTools {
        let root = try makeTempVault()
        return VaultTools(root: root, searchProvider: provider)
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchToolVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func searchCall(_ argumentsJSON: String) -> ToolCall {
        ToolCall(id: "call-1", function: .init(name: "search", arguments: argumentsJSON))
    }

    private func result(path: String, line: Int? = nil) -> ChatSearchResult {
        ChatSearchResult(
            path: path, title: "Title of \(path)", snippet: "snippet for \(path)",
            lineStart: line, kind: line == nil ? "note" : "section",
            createdAt: nil, updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    @Test func testSearchAdvertisedOnlyWithProvider() throws {
        let without = try makeTools(provider: nil)
        #expect(!without.toolDefinitions.contains { $0.function.name == "search" })
        #expect(without.toolDefinitions.count == 3)

        let with = try makeTools(provider: RecordingProvider())
        let names = with.toolDefinitions.map(\.function.name)
        #expect(names.first == "search")
        #expect(names.contains("grep"))
        #expect(names.count == 4)
    }

    @Test func testDispatchParsesQueryDatesAndLimit() throws {
        let provider = RecordingProvider()
        let tools = try makeTools(provider: provider)

        _ = tools.run(searchCall(
            #"{"query": "projects", "updated_after": "2026-06-05", "created_before": "2026-06-09", "limit": 99}"#
        ))

        let request = try #require(provider.lastRequest)
        #expect(request.query == "projects")
        #expect(request.limit == 30)  // clamped from 99
        #expect(request.filter.updatedAfter == VaultTools.isoDateOnly.date(from: "2026-06-05"))
        #expect(request.filter.createdBefore == VaultTools.isoDateOnly.date(from: "2026-06-09"))
        #expect(request.filter.createdAfter == nil)
        #expect(request.filter.updatedBefore == nil)
    }

    @Test func testMissingQueryReturnsError() throws {
        let provider = RecordingProvider()
        let tools = try makeTools(provider: provider)
        let outcome = tools.run(searchCall(#"{"updated_after": "2026-06-05"}"#))
        #expect(outcome.output.contains("Error"))
        #expect(provider.lastRequest == nil)
    }

    @Test func testProviderFailureReturnsErrorText() throws {
        let provider = RecordingProvider()
        provider.error = NSError(domain: "test", code: 1)
        let tools = try makeTools(provider: provider)
        let outcome = tools.run(searchCall(#"{"query": "anything"}"#))
        #expect(outcome.output.contains("Error"))
        #expect(outcome.output.contains("grep"))   // suggests the fallback tool
        #expect(outcome.surfacedPaths.isEmpty)
    }

    @Test func testOutputFormatAndSurfacedPaths() throws {
        let provider = RecordingProvider()
        provider.results = [
            result(path: "Projects/Alpha.md", line: 12),
            result(path: "Projects/Alpha.md"),          // duplicate path, note-level
            result(path: "Daily Notes/2026-06-09.md", line: 3),
        ] + (0..<9).map { result(path: "Bulk/Note\($0).md", line: 1) }
        let tools = try makeTools(provider: provider)

        let outcome = tools.run(searchCall(#"{"query": "projects"}"#))

        #expect(outcome.output.contains("1. Projects/Alpha.md:12 [section]"))
        #expect(outcome.output.contains("snippet for Projects/Alpha.md"))
        #expect(outcome.surfacedPaths.first == "Projects/Alpha.md")
        #expect(outcome.surfacedPaths.count == 11)   // 12 results, 1 duplicate path
        #expect(outcome.hits.count == 8)             // trace rows capped
        #expect(outcome.summary.contains("12 results"))
    }

    @Test func testNoResultsMessageMentionsFilters() throws {
        let provider = RecordingProvider()
        let tools = try makeTools(provider: provider)
        let outcome = tools.run(searchCall(#"{"query": "nothing", "updated_after": "2026-06-05"}"#))
        #expect(outcome.output.contains("No results"))
        #expect(outcome.output.contains("updated_after 2026-06-05"))
    }

    @Test func testFolderArgumentReachesProvider() throws {
        let provider = RecordingProvider()
        let tools = try makeTools(provider: provider)

        _ = tools.run(searchCall(#"{"query": "captures", "folder": "Captures"}"#))
        #expect(try #require(provider.lastRequest).folder == "Captures")

        _ = tools.run(searchCall(#"{"query": "captures", "folder": "   "}"#))
        #expect(try #require(provider.lastRequest).folder == nil)

        _ = tools.run(searchCall(#"{"query": "captures"}"#))
        #expect(try #require(provider.lastRequest).folder == nil)
    }

    @Test func testFolderAppearsInOutputAndNoResultsMessage() throws {
        let provider = RecordingProvider()
        let tools = try makeTools(provider: provider)

        let empty = tools.run(searchCall(#"{"query": "nothing", "folder": "Captures", "updated_after": "2026-06-05"}"#))
        #expect(empty.output.contains("No results"))
        #expect(empty.output.contains("folder Captures"))
        #expect(empty.output.contains("updated_after 2026-06-05"))

        provider.results = [result(path: "Captures/Hit.md", line: 4)]
        let hit = tools.run(searchCall(#"{"query": "something", "folder": "Captures"}"#))
        #expect(hit.output.contains("(folder Captures)"))
        #expect(hit.output.contains("Captures/Hit.md:4"))
    }
}
