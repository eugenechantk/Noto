import Foundation

/// Events streamed out of `ChatAgent.sendStreaming`.
public enum AgentEvent: Sendable, Equatable {
    case toolCallStarted(name: String, arguments: String)
    case toolCallFinished(name: String, summary: String)
    case textDelta(String)
    case finished(AgentResult)
}

/// Final outcome of an agent turn.
public struct AgentResult: Sendable, Equatable {
    /// The assistant's final answer text.
    public var answer: String
    /// Vault-relative paths the agent `read` (or were attached) — the citations/sources.
    public var sources: [String]
    /// Full message list including this turn (pass back as `history` to continue the chat).
    public var messages: [ChatMessage]
    /// Number of model rounds used.
    public var rounds: Int
    /// True if the loop stopped because it hit `maxRounds` without a final answer.
    public var hitRoundLimit: Bool

    public init(answer: String, sources: [String], messages: [ChatMessage], rounds: Int, hitRoundLimit: Bool) {
        self.answer = answer
        self.sources = sources
        self.messages = messages
        self.rounds = rounds
        self.hitRoundLimit = hitRoundLimit
    }
}

public let defaultSystemPrompt = """
You are Noto's note assistant. You help the user think with their personal markdown vault.

You have tools:
- grep(query, path?) — case-insensitive search across the vault's notes; returns paths + line numbers + snippets.
- read(path, start_line?, end_line?) — open a note (or a line range) by its vault-relative path.
- list(path?) — list a folder's contents.
- cite(paths) — record the exact vault paths of the notes your answer used.

Workflow:
1. Use grep to find relevant notes (issue focused queries).
2. read a note when you need its full content; you may answer directly from grep snippets when they
   are already enough.
3. When you have enough, write your final Markdown answer AND call `cite` once in the SAME message,
   passing the exact vault paths of EVERY note you drew on — whether from a grep snippet or a full
   read. Copy the paths verbatim from the tool results. Do not call any other tool in that message.

Ground every claim in the user's notes. Be concise and write in Markdown. If the vault doesn't
contain the answer, say so plainly rather than guessing.
"""

/// Runs the agentic grep→read→answer loop over a vault using an `LLMClienting` backend.
public struct ChatAgent: Sendable {
    private let client: any LLMClienting
    private let tools: VaultTools
    public var model: String
    public var maxRounds: Int
    public var systemPrompt: String
    public var temperature: Double?

    public init(client: any LLMClienting,
                tools: VaultTools,
                model: String = defaultModel,
                maxRounds: Int = 6,
                systemPrompt: String = defaultSystemPrompt,
                temperature: Double? = nil) {
        self.client = client
        self.tools = tools
        self.model = model
        self.maxRounds = maxRounds
        self.systemPrompt = systemPrompt
        self.temperature = temperature
    }

    /// Non-streaming convenience: runs the loop and returns the final result.
    public func send(_ userMessage: String,
                     mentioned: [String] = [],
                     history: [ChatMessage] = []) async throws -> AgentResult {
        for try await event in sendStreaming(userMessage, mentioned: mentioned, history: history) {
            if case .finished(let result) = event { return result }
        }
        throw LLMError.emptyResponse
    }

    /// Streaming loop. Yields tool-call progress and incremental answer text, then `.finished`.
    public func sendStreaming(_ userMessage: String,
                              mentioned: [String] = [],
                              history: [ChatMessage] = []) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var attached = Set<String>()
                    var messages = buildInitialMessages(userMessage, mentioned: mentioned,
                                                         history: history, sources: &attached)

                    var seenPaths = Set<String>()     // files surfaced by grep/read — the citation whitelist
                    var citedSources = Set<String>()  // declared via cite, validated against seenPaths
                    var readSources = Set<String>()   // files actually read (fallback citations)
                    let toolset = VaultTools.toolDefinitions + [Self.citeToolDefinition]

                    var rounds = 0
                    var lastNonEmptyText = ""   // models often put the final answer in the cite turn
                    while rounds < maxRounds {
                        rounds += 1
                        let request = ChatRequest(model: model, messages: messages,
                                                  tools: toolset, temperature: temperature)

                        var text = ""
                        var toolCalls: [ToolCall] = []
                        for try await event in client.stream(request) {
                            switch event {
                            case .textDelta(let delta):
                                text += delta
                                continuation.yield(.textDelta(delta))
                            case .toolCalls(let calls):
                                toolCalls = calls
                            case .finished:
                                break
                            }
                        }
                        if !text.isEmpty { lastNonEmptyText = text }

                        if toolCalls.isEmpty {
                            let answer = text.isEmpty ? lastNonEmptyText : text
                            messages.append(.assistant(answer))
                            continuation.yield(.finished(AgentResult(
                                answer: answer,
                                sources: finalSources(attached: attached, cited: citedSources, read: readSources),
                                messages: messages, rounds: rounds, hitRoundLimit: false)))
                            continuation.finish()
                            return
                        }

                        // Record the assistant turn that requested tools, then run them.
                        messages.append(ChatMessage(role: .assistant,
                                                    content: text.isEmpty ? nil : text,
                                                    toolCalls: toolCalls))
                        for call in toolCalls {
                            continuation.yield(.toolCallStarted(name: call.function.name,
                                                                arguments: call.function.arguments))
                            if call.function.name == "cite" {
                                let accepted = recordCitations(call.function.arguments, seenPaths: seenPaths)
                                citedSources.formUnion(accepted)
                                messages.append(.toolResult("Recorded \(accepted.count) source(s).",
                                                            callID: call.id, name: "cite"))
                                continuation.yield(.toolCallFinished(name: "cite", summary: "\(accepted.count) source(s)"))
                                continue
                            }
                            let result = tools.run(call)
                            seenPaths.formUnion(result.surfacedPaths)
                            if let path = result.readPath { readSources.insert(path) }
                            messages.append(.toolResult(result.output, callID: call.id, name: call.function.name))
                            continuation.yield(.toolCallFinished(name: call.function.name, summary: result.summary))
                        }

                        // A turn whose only tool was `cite` means "I'm done" — the answer is in this
                        // same turn's text. Stop here instead of looping into an empty round.
                        if !toolCalls.contains(where: { $0.function.name != "cite" }) {
                            let answer = text.isEmpty ? lastNonEmptyText : text
                            continuation.yield(.finished(AgentResult(
                                answer: answer,
                                sources: finalSources(attached: attached, cited: citedSources, read: readSources),
                                messages: messages, rounds: rounds, hitRoundLimit: false)))
                            continuation.finish()
                            return
                        }
                    }

                    // Hit the round cap without a final answer.
                    continuation.yield(.finished(AgentResult(
                        answer: "I reached the tool-call limit before finishing. Try narrowing the question.",
                        sources: finalSources(attached: attached, cited: citedSources, read: readSources),
                        messages: messages, rounds: rounds, hitRoundLimit: true)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Helpers

    private func buildInitialMessages(_ userMessage: String,
                                      mentioned: [String],
                                      history: [ChatMessage],
                                      sources: inout Set<String>) -> [ChatMessage] {
        var userContent = userMessage
        if !mentioned.isEmpty {
            var blocks: [String] = []
            for path in mentioned {
                let result = tools.read(path: path)
                if result.ok, let p = result.path {
                    sources.insert(p)
                    blocks.append(result.text)
                }
            }
            if !blocks.isEmpty {
                userContent = "The user attached these notes as context:\n\n"
                    + blocks.joined(separator: "\n\n")
                    + "\n\n---\n\n" + userMessage
            }
        }
        let dateLine = "Today's date is \(Self.todayString()). Use it to resolve relative dates "
            + "like \"the last 5 days\" into ISO bounds for grep's date filters."
        return [.system(dateLine + "\n\n" + systemPrompt)] + history + [.user(userContent)]
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Sources = attached (mentioned) files, plus the model's explicit citations if it declared
    /// any, otherwise everything it read (fallback).
    private func finalSources(attached: Set<String>, cited: Set<String>, read: Set<String>) -> [String] {
        var result = attached
        result.formUnion(cited.isEmpty ? read : cited)
        return result.sorted()
    }

    /// Parse a `cite` call's `paths`, accepting only paths the tools actually surfaced (exact, else
    /// suffix match) — so citations are always real files, never hallucinated or the whole grep dump.
    private func recordCitations(_ argumentsJSON: String, seenPaths: Set<String>) -> [String] {
        let args = VaultTools.parseArguments(argumentsJSON)
        let raw = (args["paths"] as? [Any])?.compactMap { $0 as? String } ?? []
        var accepted: [String] = []
        for path in raw {
            let trimmed = path.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if seenPaths.contains(trimmed) {
                accepted.append(trimmed)
            } else if let match = seenPaths.first(where: { $0.hasSuffix(trimmed) || trimmed.hasSuffix($0) }) {
                accepted.append(match)
            }
        }
        return Array(Set(accepted))
    }

    /// The `cite` tool — handled by the agent (not the filesystem). Lets the model declare which
    /// notes its answer used, from grep snippets or full reads.
    static let citeToolDefinition = ToolDefinition(function: .init(
        name: "cite",
        description: "Record the exact vault paths of the notes your answer used (from grep snippets "
            + "or full reads). Call once, right before your final answer. Copy paths verbatim from "
            + "the tool results.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "paths": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Vault-relative paths of the notes used.")
                ])
            ]),
            "required": .array([.string("paths")])
        ])
    ))
}
