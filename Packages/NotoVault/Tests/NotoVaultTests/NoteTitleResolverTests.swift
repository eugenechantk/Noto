import Foundation
import Testing
@testable import NotoVault

@Suite("NoteTitleResolver")
struct NoteTitleResolverTests {
    private let resolver = NoteTitleResolver()

    @Test
    func stripsFrontmatterAndHeadingMarker() {
        let markdown = """
        ---
        id: F28A576E-2004-4FBF-81C6-8F41DD03737C
        created: 2026-04-20T00:00:00Z
        updated: 2026-04-20T00:00:00Z
        ---

        # Today's testing
        Body
        """

        #expect(resolver.title(from: markdown) == "Today's testing")
    }

    @Test
    func usesPlainFirstLineAsTitle() {
        #expect(resolver.title(from: "Plain title\nBody") == "Plain title")
    }

    @Test
    func emptyTitleUsesFallback() {
        #expect(resolver.title(from: "# ", fallbackTitle: "Untitled") == "Untitled")
    }

    @Test
    func uuidFilenameFallbackIsUntitled() {
        let url = URL(fileURLWithPath: "/tmp/F28A576E-2004-4FBF-81C6-8F41DD03737C.md")

        #expect(resolver.fallbackTitle(for: url) == "Untitled")
    }

    @Test
    func humanFilenameFallbackUsesStem() {
        let url = URL(fileURLWithPath: "/tmp/Meeting Notes.md")

        #expect(resolver.fallbackTitle(for: url) == "Meeting Notes")
    }

    @Test
    func fileTitleResolutionUsesEarlyMarkdownOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoVaultTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let noteURL = root.appendingPathComponent("Large.md")
        let content = "# Fast Title\n\n" + String(repeating: "Large body\n", count: 20_000)
        try content.write(to: noteURL, atomically: true, encoding: .utf8)

        #expect(resolver.title(forFileAt: noteURL) == "Fast Title")
    }
}
