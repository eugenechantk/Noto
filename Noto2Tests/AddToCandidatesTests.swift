import Foundation
import NotoSearch
import NotoVault
import Testing
@testable import Noto2

/// Test case index — what the Add to and New note sheets offer (C7, C8).
/// 1. recentIsNewestFirstAndSkipsTheInbox — Recent = most recently edited notes, never inbox/
/// 2. matchingFiltersByTitleWithPrefixesFirst — typing narrows to title matches, prefix matches on top
/// 3. similarKeepsStrongMatchesOncePerNote — meaning matches above the floor, one row per note, best first
/// 4. similarDropsWeakAndInboxHits — a weak tail and inbox captures never show as Similar
/// 5. similarOnlyOffersNotesThatStillExist — a stale index row with no note behind it is skipped
/// 6. folderPathReadsAsBreadcrumbs — "Projects › Noto" under the title, "" for the vault root
/// 7. foldersStartAtTheRootAndSkipTheInbox — New note can file at the root, never into inbox/
/// 8. folderSearchMatchesNameOrPath — "noto" finds Projects › Noto
/// 9. duplicateSearchHitsFillMissingBodyWithoutChangingOrder — a later content hit fills a title-only preview
/// 10. duplicateSearchHitsKeepTheFirstUsefulBody — lower-ranked chunks cannot replace the first useful preview
/// 11. folderCountsIncludeOnlyDirectNotes — root, nested, and empty folders use real direct note counts
/// 12. folderIdentityIgnoresDirectoryHints — folder counts and direct children tolerate either URL form
struct AddToCandidatesTests {
    private let vault = URL(fileURLWithPath: "/tmp/Vault", isDirectory: true)

    private func note(_ path: String, minutesAgo: Double) -> SidebarTreeNode {
        let url = vault.appendingPathComponent(path)
        return SidebarTreeNode(
            kind: .note,
            depth: path.split(separator: "/").count - 1,
            name: url.deletingPathExtension().lastPathComponent,
            url: url,
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60)
        )
    }

    private func folder(_ path: String) -> SidebarTreeNode {
        let url = vault.appendingPathComponent(path, isDirectory: true)
        return SidebarTreeNode(
            kind: .folder(isExpanded: false),
            depth: path.split(separator: "/").count - 1,
            name: url.lastPathComponent,
            url: url,
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private var rows: [SidebarTreeNode] {
        [
            folder("Ideas"), note("Ideas/Short drama.md", minutesAgo: 30),
            folder("Projects"), folder("Projects/Noto"), note("Projects/Noto/Noto 2 roadmap.md", minutesAgo: 5),
            note("Health.md", minutesAgo: 60 * 24),
            folder("inbox"), note("inbox/2026-10-13-d36e1fee.md", minutesAgo: 1),
        ]
    }

    @Test func recentIsNewestFirstAndSkipsTheInbox() {
        let recent = AddToCandidates.recent(from: rows, vaultURL: vault)
        #expect(recent.map(\.title) == ["Noto 2 roadmap", "Short drama", "Health"])
    }

    @Test func matchingFiltersByTitleWithPrefixesFirst() {
        let all = AddToCandidates.recent(from: rows + [note("Deep sleep.md", minutesAgo: 2)], vaultURL: vault)
        // Recency order is Deep sleep, Noto 2 roadmap, Short drama, Health; "s" matches two,
        // and the title that starts with "s" goes first.
        #expect(AddToCandidates.matching(all, query: "s").map(\.title) == ["Short drama", "Deep sleep"])
        #expect(AddToCandidates.matching(all, query: "drama").map(\.title) == ["Short drama"])
        #expect(AddToCandidates.matching(all, query: "  ").count == all.count)
    }

    @Test func similarKeepsStrongMatchesOncePerNote() {
        let all = AddToCandidates.recent(from: rows, vaultURL: vault)
        let hits: [AddToCandidates.SimilarHit] = [
            .init(relativePath: "Ideas/Short drama.md", score: 0.86),
            .init(relativePath: "Ideas/Short drama.md", score: 0.84),   // second chunk, same note
            .init(relativePath: "Health.md", score: 0.80),
        ]
        #expect(AddToCandidates.similar(from: hits, candidates: all).map(\.title) == ["Short drama", "Health"])
    }

    @Test func similarDropsWeakAndInboxHits() {
        let all = AddToCandidates.recent(from: rows, vaultURL: vault)
        let hits: [AddToCandidates.SimilarHit] = [
            .init(relativePath: "inbox/2026-10-13-d36e1fee.md", score: 0.95),
            .init(relativePath: "Ideas/Short drama.md", score: 0.90),
            .init(relativePath: "Health.md", score: 0.74),                    // below the 0.76 floor
            .init(relativePath: "Projects/Noto/Noto 2 roadmap.md", score: 0.77), // > 0.12 below the best
        ]
        #expect(AddToCandidates.similar(from: hits, candidates: all).map(\.title) == ["Short drama"])
    }

    @Test func similarOnlyOffersNotesThatStillExist() {
        let all = AddToCandidates.recent(from: rows, vaultURL: vault)
        let hits: [AddToCandidates.SimilarHit] = [
            .init(relativePath: "Gone.md", score: 0.99),
            .init(relativePath: "inbox/2026-10-13-d36e1fee.md", score: 0.99),
            .init(relativePath: "Ideas/Short drama.md", score: 0.80),
        ]
        #expect(AddToCandidates.similar(from: hits, candidates: all).map(\.title) == ["Short drama"])
    }

    @Test func folderPathReadsAsBreadcrumbs() {
        let all = AddToCandidates.recent(from: rows, vaultURL: vault)
        let byTitle = Dictionary(uniqueKeysWithValues: all.map { ($0.title, $0.folderPath) })
        #expect(byTitle["Noto 2 roadmap"] == "Projects › Noto")
        #expect(byTitle["Short drama"] == "Ideas")
        #expect(byTitle["Health"] == "")
    }

    @Test func foldersStartAtTheRootAndSkipTheInbox() {
        let folders = NewNoteFolder.options(from: rows, vaultURL: vault)
        #expect(folders.first?.isRoot == true)
        #expect(folders.map(\.path) == ["", "Ideas", "Projects", "Projects › Noto"])
        #expect(!folders.contains { $0.name.lowercased() == "inbox" })
    }

    @Test func folderSearchMatchesNameOrPath() {
        let folders = NewNoteFolder.options(from: rows, vaultURL: vault)
        #expect(NewNoteFolder.matching(folders, query: "noto").map(\.path) == ["Projects › Noto"])
        #expect(NewNoteFolder.matching(folders, query: "").count == folders.count)
    }

    @Test func duplicateSearchHitsFillMissingBodyWithoutChangingOrder() {
        let candidates = AddToCandidates.recent(from: rows, vaultURL: vault)
        let hits = [
            searchHit("Ideas/Short drama.md", snippet: "Short drama"),
            searchHit("Projects/Noto/Noto 2 roadmap.md", snippet: "Noto 2 roadmap\nA body match in another note"),
            searchHit("Ideas/Short drama.md", snippet: "The useful body match", kind: .section),
        ]
        let matches = AddToCandidates.searchResults(hits, candidates: candidates, vaultURL: vault, query: "body")
        #expect(matches.map(\.relativePath) == ["Ideas/Short drama.md", "Projects/Noto/Noto 2 roadmap.md"])
        #expect(matches.map(\.snippet) == ["The useful body match", "A body match in another note"])
    }

    @Test func duplicateSearchHitsKeepTheFirstUsefulBody() {
        let candidates = AddToCandidates.recent(from: rows, vaultURL: vault)
        let hits = [
            searchHit("Ideas/Short drama.md", snippet: "Short drama\nThe first body match"),
            searchHit("Ideas/Short drama.md", snippet: "A lower-ranked body match", kind: .section),
            searchHit("Ideas/Short drama.md", snippet: "Short drama"),
        ]
        let matches = AddToCandidates.searchResults(hits, candidates: candidates, vaultURL: vault, query: "body")
        #expect(matches.count == 1)
        #expect(matches.first?.snippet == "The first body match")
    }

    @Test func folderCountsIncludeOnlyDirectNotes() {
        let tree = rows + [
            note("Projects/Brief.md", minutesAgo: 4),
            folder("Ideas/Research"), note("Ideas/Research/Source.md", minutesAgo: 3),
            folder("Empty"),
        ]
        let folders = NewNoteFolder.options(from: tree, vaultURL: vault)
        let counts = Dictionary(uniqueKeysWithValues: folders.map { ($0.path, $0.noteCount) })
        #expect(counts == ["": 1, "Ideas": 1, "Ideas › Research": 1, "Projects": 1, "Projects › Noto": 1, "Empty": 0])
    }

    @Test func folderIdentityIgnoresDirectoryHints() {
        for directoryHint in [false, true] {
            let root = URL(fileURLWithPath: "/tmp/FolderIdentity", isDirectory: directoryHint)
            let folderRows = ["Projects", "Projects/Noto", "Projects/Noto/Research", "Empty"].map { path in
                SidebarTreeNode(kind: .folder(isExpanded: false), depth: path.split(separator: "/").count - 1,
                                name: path.split(separator: "/").last.map(String.init)!,
                                url: root.appendingPathComponent(path, isDirectory: directoryHint), modifiedAt: .distantPast)
            }
            let noteRows = ["Root.md", "Projects/Brief.md", "Projects/Noto/Roadmap.md"].map { path in
                SidebarTreeNode(kind: .note, depth: path.split(separator: "/").count - 1, name: path,
                                url: root.appendingPathComponent(path), modifiedAt: .now)
            }
            let folders = NewNoteFolder.options(from: folderRows + noteRows, vaultURL: root)
            let counts = Dictionary(uniqueKeysWithValues: folders.map { ($0.path, $0.noteCount) })
            #expect(counts == ["": 1, "Projects": 1, "Projects › Noto": 1, "Projects › Noto › Research": 0, "Empty": 0],
                    "Directory hint: \(directoryHint)")
            #expect(NewNoteFolder.children(of: folders[0], in: folders).map(\.name) == ["Projects", "Empty"],
                    "Root directory hint: \(directoryHint)")
            #expect(NewNoteFolder.children(of: folders[1], in: folders).map(\.name) == ["Noto"],
                    "Nested directory hint: \(directoryHint)")
        }
    }

    private func searchHit(_ path: String, snippet: String, kind: SearchResultKind = .note) -> SearchResult {
        let url = vault.appendingPathComponent(path)
        return SearchResult(id: UUID(), kind: kind, noteID: UUID(), fileURL: url,
                            title: url.deletingPathExtension().lastPathComponent,
                            breadcrumb: "", snippet: snippet, lineStart: kind == .section ? 3 : nil,
                            score: 1, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}
