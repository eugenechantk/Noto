import Foundation
import Testing
@testable import NotoVault

@Suite("SidebarTreeLoader")
struct SidebarTreeLoaderTests {
    @Test
    func loadRowsProducesExpandedDepthFirstRows() throws {
        let root = try makeVault { root in
            try makeFolder(root.appendingPathComponent("Projects")) { projects in
                try writeNote(projects.appendingPathComponent("Alpha.md"))
                try makeFolder(projects.appendingPathComponent("Drafts")) { drafts in
                    try writeNote(drafts.appendingPathComponent("Nested.md"))
                }
            }
            try writeNote(root.appendingPathComponent("Root.md"))
        }

        let rows = try SidebarTreeLoader().loadRows(rootURL: root)

        #expect(rows.map(\.name) == ["Projects", "Drafts", "Nested", "Alpha", "Root"])
        #expect(rows.map(\.depth) == [0, 1, 2, 1, 0])
        #expect(rows.compactMap { row -> Bool? in
            guard case .folder(let isExpanded) = row.kind else { return nil }
            return isExpanded
        } == [true, true])
    }

    @Test
    func collapsedFoldersHideDescendantRows() throws {
        let root = try makeVault { root in
            try makeFolder(root.appendingPathComponent("Projects")) { projects in
                try writeNote(projects.appendingPathComponent("Alpha.md"))
            }
            try writeNote(root.appendingPathComponent("Root.md"))
        }

        let rows = try SidebarTreeLoader().loadRows(rootURL: root, expandedFolderURLs: [])

        #expect(rows.map(\.name) == ["Projects", "Root"])
        #expect(rows.map(\.depth) == [0, 0])
        guard case .folder(let isExpanded) = rows[0].kind else {
            Issue.record("Expected a folder row")
            return
        }
        #expect(isExpanded == false)
    }

    @Test
    func noteRowsUseMarkdownTitleInsteadOfFilename() throws {
        let root = try makeVault { root in
            let noteURL = root.appendingPathComponent("F28A576E-2004-4FBF-81C6-8F41DD03737C.md")
            let markdown = """
            ---
            id: F28A576E-2004-4FBF-81C6-8F41DD03737C
            created: 2026-04-20T00:00:00Z
            updated: 2026-04-20T00:00:00Z
            ---

            # Today's testing
            """
            try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
        }

        let rows = try SidebarTreeLoader().loadRows(rootURL: root)

        #expect(rows.map(\.name) == ["Today's testing"])
        #expect(rows.first?.noteID?.uuidString == "F28A576E-2004-4FBF-81C6-8F41DD03737C")
    }

    @Test
    func uuidFilenameWithoutTitleDisplaysUntitled() throws {
        let root = try makeVault { root in
            let noteURL = root.appendingPathComponent("F28A576E-2004-4FBF-81C6-8F41DD03737C.md")
            try "# ".write(to: noteURL, atomically: true, encoding: .utf8)
        }

        let rows = try SidebarTreeLoader().loadRows(rootURL: root)

        #expect(rows.map(\.name) == ["Untitled"])
    }

    @Test
    func filterKeepsAncestorFoldersForDescendantMatches() throws {
        let root = try makeVault { root in
            try makeFolder(root.appendingPathComponent("Projects")) { projects in
                try makeFolder(projects.appendingPathComponent("Drafts")) { drafts in
                    try writeNote(drafts.appendingPathComponent("Launch Plan.md"))
                }
                try writeNote(projects.appendingPathComponent("Alpha.md"))
            }
            try makeFolder(root.appendingPathComponent("Archive")) { archive in
                try writeNote(archive.appendingPathComponent("Old.md"))
            }
        }

        let loader = SidebarTreeLoader()
        let rows = try loader.loadRows(rootURL: root)
        let filtered = loader.filterRows(rows, matching: "launch")

        #expect(filtered.map(\.name) == ["Projects", "Drafts", "Launch Plan"])
        #expect(filtered.map(\.depth) == [0, 1, 2])
    }

    @Test
    func searchRowsIgnoresCollapsedFolderExpansionState() throws {
        let root = try makeVault { root in
            try makeFolder(root.appendingPathComponent("Projects")) { projects in
                try makeFolder(projects.appendingPathComponent("Drafts")) { drafts in
                    try writeNote(drafts.appendingPathComponent("Launch Plan.md"))
                }
            }
            try writeNote(root.appendingPathComponent("Root.md"))
        }

        let loader = SidebarTreeLoader()
        let visibleRows = try loader.loadRows(rootURL: root, expandedFolderURLs: [])
        let searchRows = try loader.searchRows(rootURL: root, matching: "launch")

        #expect(visibleRows.map(\.name) == ["Projects", "Root"])
        #expect(searchRows.map(\.name) == ["Projects", "Drafts", "Launch Plan"])
        #expect(searchRows.map(\.depth) == [0, 1, 2])

        guard case .folder(let isExpanded) = visibleRows[0].kind else {
            Issue.record("Expected a folder row")
            return
        }
        #expect(isExpanded == false)
    }

    private func makeVault(_ build: (URL) throws -> Void) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoVaultTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try build(root)
        return root
    }

    private func makeFolder(_ url: URL, build: (URL) throws -> Void = { _ in }) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try build(url)
    }

    private func writeNote(_ url: URL) throws {
        try "# \(url.deletingPathExtension().lastPathComponent)\n".write(to: url, atomically: true, encoding: .utf8)
    }
}
