import Foundation

/// Events streamed out of `ChatAgent.sendStreaming`.
public enum AgentEvent: Sendable, Equatable {
    case toolCallStarted(name: String, arguments: String)
    /// `hits` carries per-match (note, snippet) for grep so the tool-trace UI can show which
    /// document and snippet matched (empty for read/list).
    case toolCallFinished(name: String, summary: String, hits: [GrepHit])
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

Workflow:
1. Use grep to find relevant notes (issue focused queries).
2. read a note when you need its full content; you may answer directly from grep snippets when they
   are already enough.
3. When you have enough, write your final Markdown answer with NO further tool calls.

Citations (REQUIRED):
- Cite your sources INLINE with bracketed numbers in the answer text — e.g. "The floor is $29 [1],
  down from $39 [2]." Put the marker right after the clause it supports. Number each distinct note
  once, in the order first referenced; reuse the same number for later references.
- At the VERY END of your answer, add one reference line per cited note, in number order, mapping
  the number to the note's exact vault path:
      [1]: <exact vault path>
      [2]: <exact vault path>
  Copy paths verbatim from the tool results. Every inline [n] must have a matching [n]: line, and
  vice versa. Add no other "Sources" heading or prose — only these reference lines.

Ground every claim in the user's notes. Be concise and write in Markdown. If the vault doesn't
contain the answer, say so plainly (and cite nothing).
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
                    var readSources = Set<String>()   // files actually read (fallback citations)
                    let toolset = VaultTools.toolDefinitions

                    var rounds = 0
                    var lastNonEmptyText = ""   // models sometimes split the answer across turns
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
                            let raw = text.isEmpty ? lastNonEmptyText : text
                            let (answer, sources) = Self.extractCitations(
                                from: raw, seenPaths: seenPaths, attached: attached, read: readSources)
                            messages.append(.assistant(answer))
                            continuation.yield(.finished(AgentResult(
                                answer: answer, sources: sources,
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
                            let result = tools.run(call)
                            seenPaths.formUnion(result.surfacedPaths)
                            if let path = result.readPath { readSources.insert(path) }
                            messages.append(.toolResult(result.output, callID: call.id, name: call.function.name))
                            continuation.yield(.toolCallFinished(name: call.function.name, summary: result.summary, hits: result.hits))
                        }
                    }

                    // Hit the round cap without a final answer.
                    continuation.yield(.finished(AgentResult(
                        answer: "I reached the tool-call limit before finishing. Try narrowing the question.",
                        sources: attached.union(readSources).sorted(),
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

    /// Pull the trailing `[n]: <path>` citation reference-definitions out of the answer.
    /// Returns the answer with those lines removed, plus the ordered, validated source paths so
    /// that `sources[n-1]` is the note for inline `[n]`. Paths are validated against files the
    /// tools actually surfaced (exact, else suffix match) so citations are never hallucinated.
    /// Falls back to the attached + read files (sorted) when the model emitted no definitions.
    static func extractCitations(from text: String, seenPaths: Set<String>,
                                 attached: Set<String>, read: Set<String>) -> (answer: String, sources: [String]) {
        var numbered: [Int: String] = [:]
        var dropped = Set<Int>()
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("["), let close = t.firstIndex(of: "]") else { continue }
            let after = t.index(after: close)
            guard after < t.endIndex, t[after] == ":" else { continue }
            guard let n = Int(t[t.index(after: t.startIndex)..<close]) else { continue }
            var path = String(t[t.index(after: after)...]).trimmingCharacters(in: .whitespaces)
            path = path.trimmingCharacters(in: CharacterSet(charactersIn: "`\"' "))
            guard let resolved = resolvePath(path, seenPaths: seenPaths) else { continue }
            numbered[n] = resolved
            dropped.insert(i)
        }
        let cleaned = lines.enumerated()
            .filter { !dropped.contains($0.offset) }
            .map(\.element).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sources = numbered.keys.sorted().compactMap { numbered[$0] }
        return (cleaned, sources.isEmpty ? attached.union(read).sorted() : sources)
    }

    private static func resolvePath(_ path: String, seenPaths: Set<String>) -> String? {
        if seenPaths.contains(path) { return path }
        return seenPaths.first(where: { $0.hasSuffix(path) || path.hasSuffix($0) })
    }
}
