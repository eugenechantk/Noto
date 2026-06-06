import Foundation
import Testing
@testable import NotoChat

// Verifies SC7: grep + read work against the real vault.
// Gated on the NOTO_VAULT env var so it's a no-op in CI / for other machines.
// Run with:  NOTO_VAULT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Noto" swift test --filter RealVault
@Suite struct RealVaultTests {

    private var vaultURL: URL? {
        guard let path = ProcessInfo.processInfo.environment["NOTO_VAULT"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @Test func grepAndReadAgainstRealVault() throws {
        guard let root = vaultURL else {
            print("[RealVaultTests] NOTO_VAULT not set — skipping.")
            return
        }
        let tools = VaultTools(root: root)

        // Overview
        let listing = tools.list()
        print("[RealVaultTests] root listing:\n\(listing.split(separator: "\n").prefix(15).joined(separator: "\n"))")

        // grep a common word — should hit many notes.
        let hits = tools.grep(query: "the", maxResults: 10)
        print("[RealVaultTests] grep \"the\" → \(hits.count) hits (capped at 10). First few:")
        for hit in hits.prefix(5) { print("  \(hit.path):\(hit.line): \(hit.snippet.prefix(80))") }
        #expect(!hits.isEmpty)

        // read the first matching file.
        let firstPath = try #require(hits.first?.path)
        let read = tools.read(path: firstPath)
        print("[RealVaultTests] read \(firstPath) → ok=\(read.ok), \(read.text.count) chars")
        #expect(read.ok)
        #expect(!read.text.isEmpty)
    }

    @Test func timesDateFilterOverRealVault() throws {
        guard let root = vaultURL else {
            print("[RealVaultTests] NOTO_VAULT not set — skipping.")
            return
        }
        let tools = VaultTools(root: root)
        let cutoff = VaultTools.isoInternet.date(from: "2026-06-01T00:00:00Z")!

        // Filter-only listing (header reads only) across the whole vault.
        var start = Date()
        let notes = tools.listNotes(filter: DateFilter(updatedAfter: cutoff))
        let listMs = Date().timeIntervalSince(start) * 1000
        print(String(format: "[RealVaultTests] listNotes(updated since 2026-06-01) → %d notes in %.0f ms", notes.count, listMs))

        // Keyword grep WITH a date filter (header pre-filter skips full reads of old notes).
        start = Date()
        let hits = tools.grep(query: "the", filter: DateFilter(updatedAfter: cutoff), maxResults: 1000)
        let grepMs = Date().timeIntervalSince(start) * 1000
        print(String(format: "[RealVaultTests] grep \"the\" + date filter → %d hits in %.0f ms", hits.count, grepMs))
    }

    @Test func grepDistinctiveTermAndReadKnownNote() throws {
        guard let root = vaultURL else {
            print("[RealVaultTests] NOTO_VAULT not set — skipping.")
            return
        }
        let tools = VaultTools(root: root)

        // A more distinctive search term.
        let hits = tools.grep(query: "pricing", maxResults: 20)
        print("[RealVaultTests] grep \"pricing\" → \(hits.count) hits across the vault.")
        for hit in hits.prefix(8) { print("  \(hit.path):\(hit.line): \(hit.snippet.prefix(80))") }
    }
}
