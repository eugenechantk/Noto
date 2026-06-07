import Foundation
import NotoChat

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
        var name: String        // "grep" | "read" | "list" | "cite"
        var arguments: String   // raw JSON args from the model
        var summary: String?    // result summary (nil while running)
        var isRunning: Bool

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
    private let vaultURL: URL
    private var history: [ChatMessage] = []
    private var streamTask: Task<Void, Never>?

    // Persistence: a stable id/title across a chat so re-saving overwrites one Chats/ file.
    private var transcriptID = UUID()
    private var transcriptCreatedAt = Date()
    private var allMentioned: [String] = []

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
    func reset() {
        streamTask?.cancel(); streamTask = nil
        turns = []
        history = []
        allMentioned = []
        transcriptID = UUID()
        transcriptCreatedAt = Date()
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

        case .toolCallFinished(let name, let summary):
            // Mark the most recent running step with this name as done.
            if let idx = turns[i].blocks.lastIndex(where: {
                if case .tool(let s) = $0 { return s.isRunning && s.name == name } else { return false }
            }), case .tool(var step) = turns[i].blocks[idx] {
                step.isRunning = false
                step.summary = summary
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
            phase = .idle
            persist(latestSources: result.sources)
        }
    }

    /// Save the chat to `<vault>/Chats/` as a markdown note (chats are first-class notes).
    private func persist(latestSources: [String]) {
        let title = firstUserText().map { String($0.prefix(60)) } ?? "Chat"
        let transcript = ChatTranscript(
            id: transcriptID,
            title: title,
            createdAt: transcriptCreatedAt,
            modifiedAt: Date(),
            model: agent.model,
            mentioned: allMentioned,
            sources: latestSources,
            turns: history.filter { $0.role == .user || $0.role == .assistant }
        )
        saveTranscript(transcript, toChatsDirectory: vaultURL.appendingPathComponent("Chats"))
    }

    private func firstUserText() -> String? {
        for turn in turns where turn.role == .user {
            if case .text(_, let s)? = turn.blocks.first { return s }
        }
        return nil
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
