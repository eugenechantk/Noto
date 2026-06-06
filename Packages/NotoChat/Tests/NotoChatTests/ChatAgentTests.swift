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

    // Real models write the final answer in the same turn as the cite call.
    private func citeCallRound(paths: [String], answer: String? = nil) -> [ChatStreamEvent] {
        let json = "{\"paths\":[" + paths.map { "\"\($0)\"" }.joined(separator: ",") + "]}"
        var events: [ChatStreamEvent] = []
        if let answer { events.append(.textDelta(answer)) }
        events.append(.toolCalls([ToolCall(id: "cite1", function: .init(name: "cite", arguments: json))]))
        events.append(.finished(reason: "tool_calls"))
        return events
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
            case .toolCallFinished(let name, _): if name == "read" { sawToolFinish = true }
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
        // grep surfaces Note.md → model cites it (no read) → it becomes a source.
        let client = ScriptedClient(rounds: [
            grepCallRound(query: "answer"),
            citeCallRound(paths: ["Note.md"], answer: "It's 42, per your note."),
        ])
        let agent = ChatAgent(client: client, tools: VaultTools(root: root))

        let result = try await agent.send("What's the answer?")
        #expect(result.answer == "It's 42, per your note.")
        #expect(result.sources == ["Note.md"]) // cited from grep, never read
    }

    @Test func rejectsCitationsForFilesNotSurfaced() async throws {
        let root = try vault()
        defer { TempVault.remove(root) }
        // Model cites a path the tools never surfaced → it must be dropped (grounded citations).
        let client = ScriptedClient(rounds: [
            grepCallRound(query: "answer"),          // surfaces Note.md
            citeCallRound(paths: ["Ghost.md"]),      // not a surfaced file
            [.textDelta("done"), .finished(reason: "stop")],
        ])
        let agent = ChatAgent(client: client, tools: VaultTools(root: root))

        let result = try await agent.send("q")
        #expect(result.sources.isEmpty) // hallucinated citation rejected, nothing read
    }
}
