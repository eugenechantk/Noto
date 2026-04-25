import Foundation
import NotoSearch

let liveVaultURL = URL(fileURLWithPath: "/Users/eugenechan/Library/Mobile Documents/com~apple~CloudDocs/Noto", isDirectory: true)

func makeTempDirectory(_ name: String = "NotoSearchTests") throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func writeMarkdown(_ markdown: String, to relativePath: String, in vaultURL: URL) throws -> URL {
    let url = vaultURL.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try markdown.write(to: url, atomically: true, encoding: .utf8)
    return url
}

func removeDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

func makeFixtureVault() throws -> URL {
    let vault = try makeTempDirectory("NotoSearchFixtureVault")
    _ = try writeMarkdown(
        """
        ---
        id: 11111111-1111-4111-8111-111111111111
        created: 2026-01-01T00:00:00Z
        modified: 2026-01-01T00:00:00Z
        ---
        # Launch Notes

        ## Acquisition

        TikTok hooks and App Store keyword tests drove launch traffic.

        ## Monetization

        Pricing experiments improved annual conversion and reduced churn.
        """,
        to: "Projects/Launch Notes.md",
        in: vault
    )
    _ = try writeMarkdown(
        """
        # Body Only Match

        This paragraph contains the unique phrase orchard velocity without using it in the title.
        """,
        to: "Body Only.md",
        in: vault
    )
    _ = try writeMarkdown(
        """
        ---
        id: 22222222-2222-4222-8222-222222222222
        type: source
        ---
        # Reader Capture

        <!-- readwise:content:start -->
        The founder described retention loops, app store ranking, and pricing tests in detail.
        <!-- readwise:content:end -->
        """,
        to: "Captures/Reader Capture.md",
        in: vault
    )
    _ = try writeMarkdown("# Hidden\n\nsecret search text", to: ".noto/Hidden.md", in: vault)
    return vault
}
