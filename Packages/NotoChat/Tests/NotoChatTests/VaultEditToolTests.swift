import Foundation
import Testing
@testable import NotoChat

// Test index
//  - proposeEdits: parses edits, plans blocks, strips frontmatter, reports unresolved
//  - default path falls back to the in-context note
//  - missing path / unreadable note error cleanly
//  - the agent loop surfaces .editProposal (and not a tool-step) for propose_edits

private let noteWithFrontmatter = """
---
id: 11111111-1111-1111-1111-111111111111
created: 2026-06-01T00:00:00Z
updated: 2026-06-10T00:00:00Z
---
# Pricing notes

## Tiers
- Free
- Pro $29
"""

@Test("propose_edits parses edits, strips frontmatter, and returns rendered blocks")
func proposeEditsHappyPath() throws {
    let root = try TempVault.make(["Pricing.md": noteWithFrontmatter])
    defer { TempVault.remove(root) }
    let tools = VaultTools(root: root)

    let args = """
    {"path":"Pricing.md","summary":"raise pro price",
     "edits":[{"type":"edit","target":"Pro $29","replacement":"Pro $25"}]}
    """
    let result = tools.proposeEdits(arguments: args, defaultPath: nil)
    let proposal = try #require(result.editProposal)
    #expect(proposal.path == "Pricing.md")
    #expect(proposal.title == "Pricing")
    #expect(proposal.blocks.count == 1)
    #expect(proposal.unresolvedCount == 0)
    // Frontmatter must never appear in a diff line.
    let allText = proposal.blocks.flatMap { $0.preview.lines }.map(\.text).joined(separator: "\n")
    #expect(!allText.contains("id:"))
    #expect(!allText.contains("---"))
    #expect(allText.contains("Pro $29"))   // removed row
    #expect(allText.contains("Pro $25"))   // added row
}

@Test("propose_edits reports unresolved edits back to the model")
func proposeEditsUnresolved() throws {
    let root = try TempVault.make(["Pricing.md": noteWithFrontmatter])
    defer { TempVault.remove(root) }
    let tools = VaultTools(root: root)
    let args = """
    {"path":"Pricing.md","edits":[{"type":"edit","target":"not in the note","replacement":"x"}]}
    """
    let result = tools.proposeEdits(arguments: args, defaultPath: nil)
    #expect(result.editProposal?.unresolvedCount == 1)
    #expect(result.output.lowercased().contains("not found"))
}

@Test("propose_edits defaults to the in-context note when path is omitted")
func proposeEditsDefaultPath() throws {
    let root = try TempVault.make(["Daily/Today.md": noteWithFrontmatter])
    defer { TempVault.remove(root) }
    let tools = VaultTools(root: root)
    let args = """
    {"edits":[{"type":"deletion","target":"- Free"}]}
    """
    let result = tools.proposeEdits(arguments: args, defaultPath: "Daily/Today.md")
    #expect(result.editProposal?.path == "Daily/Today.md")
    #expect(result.editProposal?.breadcrumb == "Daily")
}

@Test("propose_edits without a path or default errors cleanly")
func proposeEditsMissingPath() throws {
    let root = try TempVault.make(["Pricing.md": noteWithFrontmatter])
    defer { TempVault.remove(root) }
    let tools = VaultTools(root: root)
    let result = tools.proposeEdits(arguments: #"{"edits":[{"type":"deletion","target":"- Free"}]}"#,
                                    defaultPath: nil)
    #expect(result.editProposal == nil)
    #expect(result.output.lowercased().contains("path"))
}

@Test("propose_edits is advertised in the tool definitions")
func proposeEditsAdvertised() throws {
    let root = try TempVault.make(["Pricing.md": noteWithFrontmatter])
    defer { TempVault.remove(root) }
    let tools = VaultTools(root: root)
    #expect(tools.toolDefinitions.contains { $0.function.name == "propose_edits" })
}

@Test("literal \\n in model content is normalized to a real newline before applying")
func normalizesLiteralNewlines() throws {
    let root = try TempVault.make(["Pricing.md": noteWithFrontmatter])
    defer { TempVault.remove(root) }
    let tools = VaultTools(root: root)
    // The model double-escaped the newline, so the decoded JSON value is the
    // two characters backslash-n. The tool must turn that into a real newline.
    let args = #"""
    {"path":"Pricing.md","edits":[{"type":"addition","position":"after","anchor_text":"- Pro $29","content":"\\n- Enterprise"}]}
    """#
    let result = tools.proposeEdits(arguments: args, defaultPath: nil)
    let proposal = try #require(result.editProposal)
    // The added row must be a clean "- Enterprise" line — never a literal "\n".
    let added = proposal.blocks.flatMap { $0.preview.lines }.filter { $0.kind == .added }
    #expect(added.contains { $0.text == "- Enterprise" })
    #expect(!added.contains { $0.text.contains("\\n") })
}

@Test("normalizeEscapes turns literal escape sequences into real characters")
func normalizeEscapesUnit() {
    #expect(VaultTools.normalizeEscapes("a\\nb") == "a\nb")
    #expect(VaultTools.normalizeEscapes("x\\ty") == "x\ty")
    #expect(VaultTools.normalizeEscapes("no escapes") == "no escapes")
}

@Test("the agent loop surfaces .editProposal for a propose_edits tool call")
func agentSurfacesEditProposal() async throws {
    let root = try TempVault.make(["Pricing.md": noteWithFrontmatter])
    defer { TempVault.remove(root) }

    let toolCall = ToolCall(id: "call_1", function: .init(
        name: "propose_edits",
        arguments: #"{"path":"Pricing.md","edits":[{"type":"edit","target":"Pro $29","replacement":"Pro $25"}]}"#
    ))
    let client = ScriptedClient(rounds: [
        [.toolCalls([toolCall]), .finished(reason: "tool_calls")],
        [.textDelta("I've suggested one edit."), .finished(reason: "stop")]
    ])
    let agent = ChatAgent(client: client, tools: VaultTools(root: root))

    var proposals: [EditProposal] = []
    var sawToolStep = false
    for try await event in agent.sendStreaming("raise the pro price") {
        switch event {
        case .editProposal(let p): proposals.append(p)
        case .toolCallStarted: sawToolStep = true
        default: break
        }
    }
    #expect(proposals.count == 1)
    #expect(proposals.first?.blocks.count == 1)
    #expect(sawToolStep == false)   // edit proposals are NOT rendered as tool-step rows
}
