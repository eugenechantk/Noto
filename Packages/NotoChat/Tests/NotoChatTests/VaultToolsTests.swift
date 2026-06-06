import Foundation
import Testing
@testable import NotoChat

// Verifies SC1 (grep), SC2 (read), SC3 (list), and path-escape safety.
@Suite struct VaultToolsTests {

    private func sampleVault() throws -> URL {
        try TempVault.make([
            "Projects/Alpha/Spec.md": "# Alpha Spec\nThe pricing model is usage-based.\nAlpha ships in Q2.\n",
            "Projects/Beta.md": "# Beta\nBeta is on hold.\n",
            "Captures/Idea.md": "# Idea\nA usage-based pricing idea worth exploring.\n",
            "Daily Notes/2026-06-07.md": "# Today\nReviewed PRICING with the team.\n",
        ])
    }

    @Test func grepFindsMatchesCaseInsensitiveWithLineNumbers() throws {
        let root = try sampleVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)

        let hits = tools.grep(query: "pricing")
        #expect(hits.count == 3) // Spec.md, Idea.md, Daily note (case-insensitive PRICING)
        let spec = hits.first { $0.path == "Projects/Alpha/Spec.md" }
        #expect(spec?.line == 2)
        #expect(spec?.snippet == "The pricing model is usage-based.")
        // Case-insensitive: the uppercase PRICING in the daily note is found.
        #expect(hits.contains { $0.path == "Daily Notes/2026-06-07.md" })
    }

    @Test func grepRespectsPathScope() throws {
        let root = try sampleVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)

        let hits = tools.grep(query: "pricing", path: "Captures")
        #expect(hits.count == 1)
        #expect(hits.first?.path == "Captures/Idea.md")
    }

    @Test func grepReturnsEmptyWhenNoMatch() throws {
        let root = try sampleVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)
        #expect(tools.grep(query: "nonexistentterm").isEmpty)
    }

    @Test func readReturnsFullFile() throws {
        let root = try sampleVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)

        let result = tools.read(path: "Projects/Beta.md")
        #expect(result.ok)
        #expect(result.path == "Projects/Beta.md")
        #expect(result.text.contains("Beta is on hold."))
    }

    @Test func readReturnsLineRange() throws {
        let root = try sampleVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)

        let result = tools.read(path: "Projects/Alpha/Spec.md", startLine: 2, endLine: 2)
        #expect(result.ok)
        #expect(result.text.contains("The pricing model is usage-based."))
        #expect(!result.text.contains("Alpha ships in Q2."))
    }

    @Test func readRejectsPathEscape() throws {
        let root = try sampleVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)

        let result = tools.read(path: "../../../etc/hosts")
        #expect(!result.ok)
        #expect(result.path == nil)
    }

    @Test func readMissingFileFails() throws {
        let root = try sampleVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)
        #expect(!tools.read(path: "Projects/DoesNotExist.md").ok)
    }

    @Test func listShowsDirectoriesFirstThenNotes() throws {
        let root = try sampleVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)

        let listing = tools.list()
        let lines = listing.split(separator: "\n").map(String.init)
        // First line is the header comment.
        let body = Array(lines.dropFirst())
        #expect(body.contains("Captures/"))
        #expect(body.contains("Daily Notes/"))
        #expect(body.contains("Projects/"))
        // Directories sort before notes; the first body entries end with "/".
        let firstThree = body.prefix(3)
        #expect(firstThree.allSatisfy { $0.hasSuffix("/") })
    }

    @Test func runDispatchesGrepToolCall() throws {
        let root = try sampleVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)

        let call = ToolCall(id: "c1", function: .init(name: "grep", arguments: #"{"query":"pricing"}"#))
        let result = tools.run(call)
        #expect(result.output.contains("Projects/Alpha/Spec.md:2"))
        #expect(result.readPath == nil) // grep does not contribute a source
    }

    @Test func runReadToolCallReportsSourcePath() throws {
        let root = try sampleVault()
        defer { TempVault.remove(root) }
        let tools = VaultTools(root: root)

        let call = ToolCall(id: "c2", function: .init(name: "read", arguments: #"{"path":"Projects/Beta.md"}"#))
        let result = tools.run(call)
        #expect(result.readPath == "Projects/Beta.md")
        #expect(result.output.contains("Beta is on hold."))
    }
}
