import Foundation
import Testing
import NotoChat
@testable import Noto

/// End-to-end (no live AI) proof of the edit-suggestion ACCEPT/DISMISS wiring:
/// inject a proposal, accept/dismiss a card, and assert the note file on disk is
/// (or isn't) changed — and that acceptance re-resolves against the CURRENT body.
@MainActor
@Suite("Chat edit suggestions", .serialized)
struct ChatEditSuggestionTests {

    private func makeVault(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("noto-edit-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (rel, content) in files {
            let url = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private let note = """
    ---
    id: 22222222-2222-2222-2222-222222222222
    created: 2026-06-01T00:00:00Z
    updated: 2026-06-10T00:00:00Z
    ---
    # Pricing notes

    ## Tiers
    - Free
    - Pro $29
    """

    private func proposal(path: String, _ edits: [ProposedEdit]) -> EditProposal {
        let body = ChatSession.splitFrontmatter(note).body
        let (blocks, _) = EditApplier.plan(edits, in: body)
        return EditProposal(path: path, title: "Pricing", breadcrumb: nil,
                            proposals: edits, blocks: blocks, unresolvedCount: 0)
    }

    @Test("Accepting an edit card writes the change to the note file (frontmatter preserved)")
    func acceptWritesToDisk() throws {
        let vault = try makeVault(["Pricing.md": note])
        defer { try? FileManager.default.removeItem(at: vault) }
        let session = ChatSession(apiKey: "test-key", vaultURL: vault)

        session._seedEditProposalForTesting(proposal(path: "Pricing.md",
                                                     [.edit(target: "Pro $29", replacement: "Pro $25")]))
        let card = try #require(session._firstEditBlock())
        #expect(card.status == .proposed)

        session.acceptEdit(blockID: card.id)
        #expect(session._firstEditBlock()?.status == .applied)

        let written = try String(contentsOf: vault.appendingPathComponent("Pricing.md"), encoding: .utf8)
        #expect(written.contains("Pro $25"))
        #expect(!written.contains("Pro $29"))
        #expect(written.contains("id: 22222222-2222-2222-2222-222222222222")) // frontmatter intact
        // `modified` is stamped at the file write (not the original seed value).
        #expect(!written.contains("modified: 2026-06-10T00:00:00Z"))
        #expect(written.contains("modified: "))
    }

    @Test("Dismissing an edit card leaves the file unchanged")
    func dismissLeavesFileUnchanged() throws {
        let vault = try makeVault(["Pricing.md": note])
        defer { try? FileManager.default.removeItem(at: vault) }
        let session = ChatSession(apiKey: "test-key", vaultURL: vault)

        session._seedEditProposalForTesting(proposal(path: "Pricing.md",
                                                     [.deletion(target: "- Free")]))
        let card = try #require(session._firstEditBlock())
        session.dismissEdit(blockID: card.id)
        #expect(session._firstEditBlock()?.status == .dismissed)

        let written = try String(contentsOf: vault.appendingPathComponent("Pricing.md"), encoding: .utf8)
        #expect(written.contains("- Free"))   // untouched
    }

    @Test("Accepting goes stale when the anchor no longer exists in the current body")
    func acceptStaleWhenAnchorGone() throws {
        let vault = try makeVault(["Pricing.md": note])
        defer { try? FileManager.default.removeItem(at: vault) }
        let session = ChatSession(apiKey: "test-key", vaultURL: vault)
        session._seedEditProposalForTesting(proposal(path: "Pricing.md",
                                                     [.edit(target: "Pro $29", replacement: "Pro $25")]))
        let card = try #require(session._firstEditBlock())

        // Simulate the user editing the note out from under the suggestion.
        let mutated = note.replacingOccurrences(of: "- Pro $29", with: "- Pro $40")
        try mutated.write(to: vault.appendingPathComponent("Pricing.md"), atomically: true, encoding: .utf8)

        session.acceptEdit(blockID: card.id)
        #expect(session._firstEditBlock()?.status == .stale)
        let written = try String(contentsOf: vault.appendingPathComponent("Pricing.md"), encoding: .utf8)
        #expect(written.contains("Pro $40"))   // not corrupted
    }

    @Test("A multi-spot proposal renders one card per spot, each applied independently")
    func multiSpotCardsApplyIndependently() throws {
        let vault = try makeVault(["Pricing.md": note])
        defer { try? FileManager.default.removeItem(at: vault) }
        let session = ChatSession(apiKey: "test-key", vaultURL: vault)
        // Two DISTANT spots (line 1 heading vs the last tier line) → two cards.
        session._seedEditProposalForTesting(proposal(path: "Pricing.md", [
            .edit(target: "# Pricing notes", replacement: "# Pricing notes v2"),
            .edit(target: "Pro $29", replacement: "Pro $25")
        ]))
        let cards = session.turns.flatMap { $0.blocks }.compactMap { block -> UUID? in
            if case .editBlock(let s) = block { return s.id } else { return nil }
        }
        #expect(cards.count == 2)

        // Accept only the first card (the heading); the second spot stays untouched.
        session.acceptEdit(blockID: cards[0])
        let written = try String(contentsOf: vault.appendingPathComponent("Pricing.md"), encoding: .utf8)
        #expect(written.contains("# Pricing notes v2"))
        #expect(written.contains("Pro $29"))   // the other card not yet accepted
    }
}
