import Foundation
import Testing
@testable import NotoChat

// Verifies grep's date-filter mode: keyword + property filtering, and the filter-only note listing
// (e.g. "diaries in the last 5 days"). Noto v2 frontmatter uses `created:` + `updated:`.
@Suite struct DateFilterTests {

    /// A vault of notes with explicit frontmatter created/updated timestamps.
    private func datedVault() throws -> URL {
        func note(id: String, created: String, updated: String, title: String, body: String) -> String {
            "---\nid: \(id)\ncreated: \(created)\nupdated: \(updated)\n---\n# \(title)\n\(body)\n"
        }
        return try TempVault.make([
            "Daily Notes/2026-06-06.md": note(id: "11111111-1111-1111-1111-111111111111",
                created: "2026-06-06T08:00:00Z", updated: "2026-06-06T20:00:00Z",
                title: "Mon 6 Jun", body: "Felt productive. Shipped the diary feature."),
            "Daily Notes/2026-06-02.md": note(id: "22222222-2222-2222-2222-222222222222",
                created: "2026-06-02T08:00:00Z", updated: "2026-06-02T09:00:00Z",
                title: "Thu 2 Jun", body: "Slow day."),
            "Daily Notes/2026-05-01.md": note(id: "33333333-3333-3333-3333-333333333333",
                created: "2026-05-01T08:00:00Z", updated: "2026-05-01T09:00:00Z",
                title: "1 May", body: "Old entry about pricing."),
            "Projects/Plan.md": note(id: "44444444-4444-4444-4444-444444444444",
                created: "2026-06-05T08:00:00Z", updated: "2026-06-05T08:00:00Z",
                title: "Plan", body: "Roadmap and pricing notes."),
        ])
    }

    private func date(_ iso: String) -> Date { VaultTools.isoInternet.date(from: iso)! }

    @Test func listsNotesUpdatedAfterCutoffMostRecentFirst() throws {
        let root = try datedVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)

        // "last few days": updated on/after 2026-06-03.
        let notes = tools.listNotes(filter: DateFilter(updatedAfter: date("2026-06-03T00:00:00Z")))
        #expect(notes.map(\.path) == ["Daily Notes/2026-06-06.md", "Projects/Plan.md"])
        #expect(notes.first?.path == "Daily Notes/2026-06-06.md") // most-recently-updated first
    }

    @Test func listScopedToFolderWithDateFilter() throws {
        let root = try datedVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)

        // Diaries (Daily Notes) updated since 2026-06-02.
        let notes = tools.listNotes(path: "Daily Notes",
                                    filter: DateFilter(updatedAfter: date("2026-06-02T00:00:00Z")))
        #expect(notes.map(\.path) == ["Daily Notes/2026-06-06.md", "Daily Notes/2026-06-02.md"])
    }

    @Test func grepCombinesKeywordWithDateFilter() throws {
        let root = try datedVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)

        // "pricing" appears in the 1 May daily note and the recent Plan note;
        // restrict to recently-updated → only Plan.
        let hits = tools.grep(query: "pricing", filter: DateFilter(updatedAfter: date("2026-06-03T00:00:00Z")))
        #expect(hits.map(\.path) == ["Projects/Plan.md"])
    }

    @Test func runWithDateOnlyArgsListsNotes() throws {
        let root = try datedVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)

        // No query, just updated_after → grep returns a note list.
        let call = ToolCall(id: "g", function: .init(
            name: "grep", arguments: #"{"updated_after":"2026-06-03"}"#))
        let result = tools.run(call)
        #expect(result.output.contains("Daily Notes/2026-06-06.md"))
        #expect(result.output.contains("Projects/Plan.md"))
        #expect(!result.output.contains("2026-05-01.md"))
        #expect(result.surfacedPaths.contains("Daily Notes/2026-06-06.md")) // surfaced for citations
    }

    @Test func parsesDateOnlyAndFullISO() {
        #expect(VaultTools.parseDate("2026-06-07") != nil)
        #expect(VaultTools.parseDate("2026-06-07T12:00:00Z") != nil)
        #expect(VaultTools.parseDate("") == nil)
        #expect(VaultTools.parseDate(nil) == nil)
    }

    @Test func grepWithoutQueryOrFilterIsRejected() throws {
        let root = try datedVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)
        let call = ToolCall(id: "g", function: .init(name: "grep", arguments: "{}"))
        #expect(tools.run(call).output.contains("Error"))
    }
}
