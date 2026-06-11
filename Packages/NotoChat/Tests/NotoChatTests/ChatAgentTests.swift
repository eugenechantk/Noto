import Foundation
import Testing
@testable import NotoChat

// Verifies SC6: the agentic loop executes tool calls, feeds results back, streams a final answer,
// collects sources, and caps at maxRounds.
@Suite struct ChatAgentTests {

    private func vault() throws -> URL {
        try TempVault.make([
            "Note.md": "# Note\nThe answer is 42.\n",
        ])
    }

    private func readCallRound(path: String) -> [ChatStreamEvent] {
        [.toolCalls([ToolCall(id: "c1", function: .init(name: "read", arguments: "{\"path\":\"\(path)\"}"))]),
         .finished(reason: "tool_calls")]
    }

    private func grepCallRound(query: String) -> [ChatStreamEvent] {
        [.toolCalls([ToolCall(id: "g1", function: .init(name: "grep", arguments: "{\"query\":\"\(query)\"}"))]),
         .finished(reason: "tool_calls")]
    }

    // Final answer turn: inline-cited text plus trailing `[n]: path` reference lines (no cite tool).
    private func answerRound(_ answer: String, refs: [String] = []) -> [ChatStreamEvent] {
        var text = answer
        if !refs.isEmpty {
            text += "\n\n" + refs.enumerated().map { "[\($0.offset + 1)]: \($0.element)" }.joined(separator: "\n")
        }
        return [.textDelta(text), .finished(reason: "stop")]
    }

    @Test func runsToolRoundThenAnswersAndCollectsSources() async throws {
        let root = try vault()
        defer { TempVault.remove(root) }
        let client = ScriptedClient(rounds: [
            readCallRound(path: "Note.md"),
            [.textDelta("It's "), .textDelta("42."), .finished(reason: "stop")],
        ])
        let agent = ChatAgent(client: client, tools: VaultTools(root: root))

        let result = try await agent.send("What is the answer?")
        #expect(result.answer == "It's 42.")
        #expect(result.sources == ["Note.md"])
        #expect(result.rounds == 2)
        #expect(result.hitRoundLimit == false)
        // The tool result must have been fed back into the message history.
        #expect(result.messages.contains { $0.role == .tool && ($0.content?.contains("The answer is 42.") ?? false) })
    }

    @Test func streamingEmitsToolProgressAndTextDeltas() async throws {
        let root = try vault()
        defer { TempVault.remove(root) }
        let client = ScriptedClient(rounds: [
            readCallRound(path: "Note.md"),
            [.textDelta("Hi"), .finished(reason: "stop")],
        ])
        let agent = ChatAgent(client: client, tools: VaultTools(root: root))

        var sawToolStart = false
        var sawToolFinish = false
        var text = ""
        for try await event in agent.sendStreaming("q") {
            switch event {
            case .toolCallStarted(let name, _): if name == "read" { sawToolStart = true }
            case .toolCallFinished(let name, _, _): if name == "read" { sawToolFinish = true }
            case .textDelta(let d): text += d
            case .finished: break
            }
        }
        #expect(sawToolStart)
        #expect(sawToolFinish)
        #expect(text == "Hi")
    }

    @Test func answersImmediatelyWithoutTools() async throws {
        let root = try vault()
        defer { TempVault.remove(root) }
        let client = ScriptedClient(rounds: [
            [.textDelta("Direct answer."), .finished(reason: "stop")],
        ])
        let agent = ChatAgent(client: client, tools: VaultTools(root: root))

        let result = try await agent.send("hi")
        #expect(result.answer == "Direct answer.")
        #expect(result.rounds == 1)
        #expect(result.sources.isEmpty)
    }

    @Test func mentionedFilesArePreAttachedAsContextAndSources() async throws {
        let root = try vault()
        defer { TempVault.remove(root) }
        let client = ScriptedClient(rounds: [
            [.textDelta("ok"), .finished(reason: "stop")],
        ])
        let agent = ChatAgent(client: client, tools: VaultTools(root: root))

        let result = try await agent.send("summarize", mentioned: ["Note.md"])
        #expect(result.sources == ["Note.md"])
        let userMessage = result.messages.first { $0.role == .user }
        #expect(userMessage?.content?.contains("The answer is 42.") ?? false)
    }

    @Test func stopsAtRoundLimit() async throws {
        let root = try vault()
        defer { TempVault.remove(root) }
        // Always requests a tool — never finishes with a plain answer.
        let client = ScriptedClient(rounds: [readCallRound(path: "Note.md")])
        let agent = ChatAgent(client: client, tools: VaultTools(root: root), maxRounds: 3)

        let result = try await agent.send("loop forever")
        #expect(result.hitRoundLimit)
        #expect(result.rounds == 3)
    }

    @Test func citesGrepSurfacedFilesWithoutReading() async throws {
        let root = try vault()
        defer { TempVault.remove(root) }
        // grep surfaces Note.md → model cites it inline (no read) → it becomes a source,
        // and the trailing `[1]: path` reference line is stripped from the answer.
        let client = ScriptedClient(rounds: [
            grepCallRound(query: "answer"),
            answerRound("It's 42, per your note. [1]", refs: ["Note.md"]),
        ])
        let agent = ChatAgent(client: client, tools: VaultTools(root: root))

        let result = try await agent.send("What's the answer?")
        #expect(result.answer == "It's 42, per your note. [1]")
        #expect(result.sources == ["Note.md"]) // cited from grep, never read
    }

    @Test func rejectsCitationsForFilesNotSurfaced() async throws {
        let root = try vault()
        defer { TempVault.remove(root) }
        // Model cites a path the tools never surfaced → it must be dropped (grounded citations).
        let client = ScriptedClient(rounds: [
            grepCallRound(query: "answer"),                       // surfaces Note.md
            answerRound("done [1]", refs: ["Ghost.md"]),          // Ghost.md not surfaced
        ])
        let agent = ChatAgent(client: client, tools: VaultTools(root: root))

        let result = try await agent.send("q")
        #expect(result.sources.isEmpty) // hallucinated citation rejected, nothing read
    }

    // MARK: - Citation renumbering (bug 021: inline [n] must always map to sources[n-1])

    @Test func nonContiguousCitationNumbersAreRenumbered() {
        let (answer, sources) = ChatAgent.extractCitations(
            from: "Alpha fact [1] and beta fact [3].\n\n[1]: A.md\n[3]: B.md",
            seenPaths: ["A.md", "B.md"], attached: [], read: []
        )
        #expect(answer == "Alpha fact [1] and beta fact [2].")
        #expect(sources == ["A.md", "B.md"])
    }

    @Test func droppedReferenceRemovesItsInlineCitation() {
        // [2]'s path was never surfaced → its definition is rejected; the inline
        // [2] must disappear instead of becoming a dead or wrong-target link.
        let (answer, sources) = ChatAgent.extractCitations(
            from: "One [1] two [2] three [3].\n\n[1]: A.md\n[2]: Ghost.md\n[3]: B.md",
            seenPaths: ["A.md", "B.md"], attached: [], read: []
        )
        #expect(answer == "One [1] two three [2].")
        #expect(sources == ["A.md", "B.md"])
    }

    @Test func groupedCitationsRenumberMemberWise() {
        let (answer, sources) = ChatAgent.extractCitations(
            from: "Both notes agree [1, 4].\n\n[1]: A.md\n[4]: B.md",
            seenPaths: ["A.md", "B.md"], attached: [], read: []
        )
        #expect(answer == "Both notes agree [1, 2].")
        #expect(sources == ["A.md", "B.md"])
    }

    @Test func contiguousCitationsPassThroughUnchanged() {
        let (answer, sources) = ChatAgent.extractCitations(
            from: "First [1], second [2], both [1, 2].\n\n[1]: A.md\n[2]: B.md",
            seenPaths: ["A.md", "B.md"], attached: [], read: []
        )
        #expect(answer == "First [1], second [2], both [1, 2].")
        #expect(sources == ["A.md", "B.md"])
    }

    @Test func renumberingLeavesMarkdownLinksAndDefinitionsAlone() {
        let (answer, _) = ChatAgent.extractCitations(
            from: "See [1](https://example.com/1) and cite [3].\n\n[3]: A.md",
            seenPaths: ["A.md"], attached: [], read: []
        )
        #expect(answer == "See [1](https://example.com/1) and cite [1].")
    }
}
