import Foundation
import NotoChat
import NotoVault

/// View-model that drives one AI chat conversation: owns a `ChatAgent`, runs
/// `sendStreaming` in a Task, and publishes the streamed answer + interleaved
/// tool trace + sources for the UI.
///
/// The key design point: an assistant turn is an ORDERED list of `Block`s —
/// text and tool steps in arrival order — so tool steps interleave with the
/// streamed answer text (top and mid-paragraph), matching the design.
///
/// See `.claude/notochat-ui/component-breakdown.md`.
@MainActor
final class ChatSession: ObservableObject {

    // MARK: Published state

    @Published private(set) var turns: [ChatTurn] = []
    @Published private(set) var phase: Phase = .idle
    /// Display title for the sheet header (custom name, else first user message).
    @Published private(set) var title: String = "New chat"
    /// Composer state — held here so it survives the sheet being dismissed/reopened.
    @Published var draft: String = ""
    @Published var pendingMentions: [String] = []

    enum Phase: Equatable {
        case idle
        case thinking          // sent, awaiting first event
        case streaming         // receiving text / tool events
        case error(String)
    }

    // MARK: Model

    /// One conversation turn. A user turn carries its mentioned notes; an
    /// assistant turn carries ordered blocks and (when finished) its sources.
    struct ChatTurn: Identifiable, Equatable {
        let id = UUID()
        var role: Role
        var blocks: [Block]
        var mentioned: [String] = []   // user turn: the mention tags
        var sources: [String] = []     // assistant turn: the SOURCES chips
        var hitRoundLimit = false

        enum Role { case user, assistant }
    }

    /// A block within an assistant turn — text and tool steps interleave.
    enum Block: Identifiable, Equatable {
        case text(id: UUID, String)
        case tool(ToolStep)

        var id: UUID {
            switch self {
            case .text(let id, _): return id
            case .tool(let step): return step.id
            }
        }
    }

    /// A single tool invocation rendered as a collapsible step
    /// (collapsed = the call, expanded = the result/summary).
    struct ToolStep: Identifiable, Equatable {
        let id = UUID()
        var name: String        // "grep" | "read" | "list"
        var arguments: String   // raw JSON args from the model
        var summary: String?    // result summary (nil while running)
        var isRunning: Bool
        var hits: [GrepHit] = [] // grep: per-match (note, snippet) for the expanded trace

        /// Humanized verb + target for the collapsed row, e.g. Searched 'pricing'.
        var title: String { ToolStep.humanize(name: name, arguments: arguments) }

        static func humanize(name: String, arguments: String) -> String {
            let arg = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any]
            switch name {
            case "grep":
                if let q = arg?["query"] as? String, !q.isEmpty { return "Searched ‘\(q)’" }
                return "Searched the vault"
            case "read":
                if let p = arg?["path"] as? String { return "Read \(NotoChatPath.title(p))" }
                return "Read a note"
            case "list":
                if let p = arg?["path"] as? String, !p.isEmpty { return "Listed \(p)" }
                return "Listed the vault"
            case "cite":
                return "Cited sources"
            default:
                return name
            }
        }
    }

    // MARK: Dependencies

    private let agent: ChatAgent
    let vaultURL: URL
    private var history: [ChatMessage] = []
    private var streamTask: Task<Void, Never>?

    // Persistence: a stable id/title across a chat so re-saving overwrites one Chats/ file.
    private var transcriptID = UUID()
    private var transcriptCreatedAt = Date()
    private var allMentioned: [String] = []
    private var customTitle: String?
    private var lastSources: [String] = []

    /// True once there's a saved/active conversation (enables Rename/Delete).
    var canManage: Bool { !turns.isEmpty }

    /// - Parameters:
    ///   - apiKey: OpenRouter key (BYO, from Keychain).
    ///   - vaultURL: the vault root (from `VaultLocationManager`).
    init(apiKey: String, vaultURL: URL) {
        let client = OpenRouterClient(configuration: .init(
            apiKey: apiKey,
            referer: "https://noto.app",
            title: "Noto"
        ))
        self.vaultURL = vaultURL
        self.agent = ChatAgent(client: client, tools: VaultTools(root: vaultURL))
    }

    /// Start a fresh conversation (••• → New chat).
    /// Attach a note as a pending mention if not already present (dedup). Used to
    /// auto-attach the active editor document when the chat is opened.
    func attachMention(_ path: String) {
        guard !path.isEmpty, !pendingMentions.contains(path) else { return }
        pendingMentions.append(path)
    }

    func reset() {
        streamTask?.cancel(); streamTask = nil
        turns = []
        history = []
        allMentioned = []
        customTitle = nil
        lastSources = []
        transcriptID = UUID()
        transcriptCreatedAt = Date()
        title = "New chat"
        draft = ""
        pendingMentions = []
        phase = .idle
    }

    private let fs: any VaultFileSystem = CoordinatedVaultFileSystem()

    // MARK: Manage the current chat

    private var chatsDir: URL { vaultURL.appendingPathComponent("Chats") }
    private var currentTitle: String { customTitle ?? firstUserText().map { String($0.prefix(60)) } ?? "Chat" }
    private func fileURL(forTitle title: String) -> URL {
        chatsDir.appendingPathComponent(ChatTranscript(title: title).fileName())
    }

    /// Rename the current chat: delete the old file, re-save under the new title.
    func rename(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !turns.isEmpty else { return }
        let oldURL = fileURL(forTitle: currentTitle)
        customTitle = trimmed
        title = trimmed
        fs.delete(at: oldURL)
        persist()
    }

    /// Delete the current chat's file and start fresh.
    func deleteCurrentChat() {
        fs.delete(at: fileURL(forTitle: currentTitle))
        reset()
    }

    /// Load a past chat (from the history list) so it can be viewed and continued.
    func loadTranscript(from url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let parsed = Self.parse(text, fallbackTitle: url.deletingPathExtension().lastPathComponent)
        streamTask?.cancel(); streamTask = nil
        transcriptID = parsed.id ?? UUID()
        transcriptCreatedAt = parsed.created ?? Date()
        customTitle = parsed.title
        title = parsed.title
        allMentioned = parsed.mentioned
        lastSources = parsed.sources
        history = parsed.turns.map { $0.role == .user ? .user($0.text) : .assistant($0.text) }
        turns = parsed.turns.enumerated().map { idx, t in
            ChatTurn(
                role: t.role == .user ? .user : .assistant,
                blocks: [.text(id: UUID(), t.text)],
                sources: (t.role == .assistant && idx == parsed.turns.count - 1) ? parsed.sources : []
            )
        }
        phase = .idle
    }

    // MARK: Send

    /// Send a user message; `mentioned` are vault-relative paths from the
    /// mention tags above the composer (pre-attached as context).
    func send(_ text: String, mentioned: [String] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, phase != .thinking, phase != .streaming else { return }

        for m in mentioned where !allMentioned.contains(m) { allMentioned.append(m) }
        turns.append(ChatTurn(role: .user, blocks: [.text(id: UUID(), trimmed)], mentioned: mentioned))
        title = currentTitle
        var assistant = ChatTurn(role: .assistant, blocks: [])
        turns.append(assistant)
        let assistantIndex = turns.count - 1
        phase = .thinking

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in self.agent.sendStreaming(trimmed, mentioned: mentioned, history: self.history) {
                    self.apply(event, toAssistantAt: assistantIndex)
                }
            } catch {
                self.phase = .error(Self.friendly(error))
            }
        }
        _ = assistant   // value type; mutations happen via index
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        if phase == .thinking || phase == .streaming { phase = .idle }
    }

    // MARK: Event reduction

    private func apply(_ event: AgentEvent, toAssistantAt i: Int) {
        guard turns.indices.contains(i) else { return }
        switch event {
        case .toolCallStarted(let name, let arguments):
            phase = .streaming
            turns[i].blocks.append(.tool(ToolStep(name: name, arguments: arguments, summary: nil, isRunning: true)))

        case .toolCallFinished(let name, let summary, let hits):
            // Mark the most recent running step with this name as done.
            if let idx = turns[i].blocks.lastIndex(where: {
                if case .tool(let s) = $0 { return s.isRunning && s.name == name } else { return false }
            }), case .tool(var step) = turns[i].blocks[idx] {
                step.isRunning = false
                step.summary = summary
                step.hits = hits
                turns[i].blocks[idx] = .tool(step)
            }

        case .textDelta(let chunk):
            phase = .streaming
            // Append to the trailing text block, or start a new one (so tool
            // steps that arrived in between split the text into blocks).
            if case .text(let id, let existing)? = turns[i].blocks.last {
                turns[i].blocks[turns[i].blocks.count - 1] = .text(id: id, existing + chunk)
            } else {
                turns[i].blocks.append(.text(id: UUID(), chunk))
            }

        case .finished(let result):
            turns[i].sources = result.sources
            turns[i].hitRoundLimit = result.hitRoundLimit
            history = result.messages
            lastSources = result.sources
            phase = .idle
            persist()
        }
    }

    /// Save the chat to `<vault>/Chats/` as a markdown note (chats are first-class notes).
    private func persist() {
        guard !turns.isEmpty else { return }
        let transcript = ChatTranscript(
            id: transcriptID,
            title: currentTitle,
            createdAt: transcriptCreatedAt,
            modifiedAt: Date(),
            model: agent.model,
            mentioned: allMentioned,
            sources: lastSources,
            turns: history.filter { $0.role == .user || $0.role == .assistant }
        )
        saveTranscript(transcript, toChatsDirectory: chatsDir)
    }

    private func firstUserText() -> String? {
        for turn in turns where turn.role == .user {
            if case .text(_, let s)? = turn.blocks.first { return s }
        }
        return nil
    }

    // MARK: Transcript parsing (resume-from-history)

    struct ParsedTranscript {
        var id: UUID?
        var created: Date?
        var title: String
        var mentioned: [String]
        var sources: [String]
        var turns: [(role: ChatRole, text: String)]
    }

    /// Parse a saved `Chats/*.md` (frontmatter + `## You` / `## Noto` sections).
    static func parse(_ text: String, fallbackTitle: String) -> ParsedTranscript {
        var id: UUID?
        var created: Date?
        var title = fallbackTitle
        var mentioned: [String] = []
        var sources: [String] = []
        var turns: [(role: ChatRole, text: String)] = []

        let lines = text.components(separatedBy: "\n")
        var i = 0
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            i = 1
            var listKey: String?
            while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces) != "---" {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("- "), let key = listKey {
                    let val = String(line.dropFirst(2))
                    if key == "mentioned" { mentioned.append(val) } else if key == "sources" { sources.append(val) }
                } else if let colon = line.firstIndex(of: ":") {
                    let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                    let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    listKey = (val.isEmpty && (key == "mentioned" || key == "sources")) ? key : nil
                    if key == "id" { id = UUID(uuidString: val) }
                    if key == "created" { created = ISO8601DateFormatter().date(from: val) }
                }
                i += 1
            }
            i += 1
        }
        var role: ChatRole?
        var buffer: [String] = []
        func flush() {
            if let r = role {
                let content = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty { turns.append((r, content)) }
            }
            buffer = []
        }
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t == "## You" { flush(); role = .user }
            else if t == "## Noto" { flush(); role = .assistant }
            else if t.hasPrefix("# ") && !t.hasPrefix("## ") { title = String(t.dropFirst(2)) }
            else if role != nil { buffer.append(lines[i]) }
            i += 1
        }
        flush()
        return ParsedTranscript(id: id, created: created, title: title, mentioned: mentioned, sources: sources, turns: turns)
    }

    // MARK: Helpers

    private static func friendly(_ error: Error) -> String {
        if let llm = error as? LLMError {
            switch llm {
            case .missingAPIKey: return "Add your OpenRouter API key in Settings to chat."
            default: return "Something went wrong. Please try again."
            }
        }
        return "Something went wrong. Please try again."
    }
}

/// Holds a single persistent `ChatSession` behind a sheet so the conversation,
/// draft, and pending mentions survive the sheet being dismissed and reopened.
/// Held as a `@StateObject` by the presenter (stable identity).
@MainActor
final class ChatSessionStore: ObservableObject {
    @Published private(set) var session: ChatSession?

    func ensure(apiKey: String, vaultURL: URL, seedMention: String? = nil) {
        if session == nil {
            let s = ChatSession(apiKey: apiKey, vaultURL: vaultURL)
            if let seedMention { s.pendingMentions = [seedMention] }
            session = s
        }
    }
}

/// Path helpers for displaying vault-relative paths in the UI.
enum NotoChatPath {
    /// File name without extension, e.g. "Projects/Alpha/Q2.md" → "Q2".
    static func title(_ path: String) -> String {
        (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".md", with: "")
    }

    /// Parent breadcrumb, e.g. "Projects/Alpha/Q2.md" → "Projects › Alpha".
    static func breadcrumb(_ path: String) -> String {
        let parts = path.split(separator: "/").dropLast()
        return parts.joined(separator: " › ")
    }
}
