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

    /// A block within an assistant turn — text, tool steps, and edit suggestions interleave.
    enum Block: Identifiable, Equatable {
        case text(id: UUID, String)
        case tool(ToolStep)
        case editBlock(EditBlockState)   // one per edit spot (Suggested Edits card)

        var id: UUID {
            switch self {
            case .text(let id, _): return id
            case .tool(let step): return step.id
            case .editBlock(let state): return state.id
            }
        }
    }

    /// One edit-suggestion card (one contiguous spot in a note). Carries the
    /// resolved block (with its source proposals, for independent re-resolution
    /// on accept/expand) and its display/terminal status.
    struct EditBlockState: Identifiable, Equatable {
        let id = UUID()
        var targetPath: String       // vault-relative note the edit changes
        var title: String            // note title for the "Suggested Edits ・ file" header
        var breadcrumb: String?      // folder breadcrumb when nested
        var locationHint: String?    // nearest heading within the note
        var block: EditBlock         // NotoEdit block (immutable; .sources for re-resolution)
        var preview: DiffPreview     // current preview (replaced when expanded)
        var beforeRadius: Int        // context lines shown above (grows on expand-up)
        var afterRadius: Int         // context lines shown below (grows on expand-down)
        var status: Status

        enum Status: Equatable { case proposed, applied, dismissed, stale }
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
            case "search":
                var title = "Searched"
                if let q = arg?["query"] as? String, !q.isEmpty { title += " ‘\(q)’" }
                var filters: [String] = []
                if let d = arg?["created_after"] as? String { filters.append("created ≥ \(d)") }
                if let d = arg?["created_before"] as? String { filters.append("created ≤ \(d)") }
                if let d = arg?["updated_after"] as? String { filters.append("updated ≥ \(d)") }
                if let d = arg?["updated_before"] as? String { filters.append("updated ≤ \(d)") }
                if !filters.isEmpty { title += " · " + filters.joined(separator: ", ") }
                return title
            case "grep":
                if let q = arg?["query"] as? String, !q.isEmpty { return "Matched ‘\(q)’" }
                return "Matched in the vault"
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
            baseURL: OpenRouterBaseURLStore.resolved(),
            referer: "https://noto.app",
            title: "Noto"
        ))
        self.vaultURL = vaultURL
        self.agent = ChatAgent(client: client, tools: VaultTools(
            root: vaultURL,
            searchProvider: HybridChatSearchProvider(vaultURL: vaultURL)
        ))
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
        // Transcripts saved before display-level persistence (bug 022) carry the
        // composed prompt in user turns — unwrap it so restoration shows exactly
        // what was typed. New transcripts pass through unchanged.
        let displayTurns = parsed.turns.map { t in
            (role: t.role,
             text: t.role == .user ? ChatAgent.strippedComposedUserContent(t.text) : t.text,
             sources: t.sources)
        }
        history = displayTurns.map { $0.role == .user ? .user($0.text) : .assistant($0.text) }
        let lastIndex = displayTurns.count - 1
        turns = displayTurns.enumerated().map { idx, t in
            // Per-turn sources from the transcript; legacy files without
            // per-turn reference lines fall back to the frontmatter sources
            // for the final answer (the only mapping the old format saved).
            let isFallback = t.sources.isEmpty
            let turnSources = !isFallback
                ? t.sources
                : ((t.role == .assistant && idx == lastIndex) ? parsed.sources : [])
            // Legacy fallback with a single source: every inline citation in
            // the turn can only mean that one note — normalize the numbers so
            // they're tappable instead of dead (e.g. a stray "[7]").
            var text = t.text
            if isFallback, t.role == .assistant, turnSources.count == 1 {
                text = ChatAgent.normalizeAllCitations(in: text, to: 1)
            }
            return ChatTurn(
                role: t.role == .user ? .user : .assistant,
                blocks: [.text(id: UUID(), text)],
                sources: turnSources
            )
        }
        // Continuing a restored chat should behave like a fresh chat with the
        // same notes attached: re-seed the previously mentioned documents so
        // the next send re-attaches their current content.
        for m in parsed.mentioned where !pendingMentions.contains(m) {
            pendingMentions.append(m)
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

        case .editProposal(let proposal):
            phase = .streaming
            // One card per spot; multiple spots stack as multiple cards.
            for b in proposal.blocks {
                turns[i].blocks.append(.editBlock(EditBlockState(
                    targetPath: proposal.path,
                    title: proposal.title,
                    breadcrumb: proposal.breadcrumb,
                    locationHint: b.locationHint,
                    block: b,
                    preview: b.preview,
                    beforeRadius: EditApplier.defaultContextRadius,
                    afterRadius: EditApplier.defaultContextRadius,
                    status: .proposed
                )))
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
            // Reconcile the streamed blocks with the finalized answer:
            // extractCitations renumbered inline citations and stripped the
            // `[n]: path` reference lines from result.answer, so the raw
            // streamed text would mismatch turn.sources (dead/wrong citation
            // taps) and leak reference lines into the saved transcript. Tool
            // steps stay, stacked above the final text.
            if !result.answer.isEmpty {
                // Keep the non-text blocks (tool steps + edit cards) in order,
                // and replace the streamed text with the finalized answer below them.
                let keptBlocks = turns[i].blocks.filter {
                    if case .text = $0 { return false } else { return true }
                }
                turns[i].blocks = keptBlocks + [.text(id: UUID(), result.answer)]
            }
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
            turns: Self.transcriptTurns(from: turns)
        )
        saveTranscript(transcript, toChatsDirectory: chatsDir)
    }

    /// The display-level conversation — what the user actually typed and what
    /// Noto answered — for the saved transcript. NOT the composed LLM history,
    /// whose user messages embed attached-note text and context plumbing that
    /// must never resurface when the chat is restored (bug 022). Tool-step
    /// blocks are dropped; empty turns (e.g. a failed send's placeholder) too.
    /// Assistant turns keep their per-turn sources so citations survive.
    nonisolated static func transcriptTurns(from turns: [ChatTurn]) -> [TranscriptTurn] {
        turns.compactMap { turn in
            let text = turn.blocks.compactMap { block -> String? in
                if case .text(_, let s) = block { return s }
                return nil
            }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return turn.role == .user
                ? .user(text)
                : .assistant(text, sources: turn.sources)
        }
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
        /// Assistant turns carry their own sources (in inline-number order);
        /// user turns have none.
        var turns: [(role: ChatRole, text: String, sources: [String])]
    }

    /// Parse a saved `Chats/*.md` (frontmatter + `## You` / `## Noto` sections).
    nonisolated static func parse(_ text: String, fallbackTitle: String) -> ParsedTranscript {
        var id: UUID?
        var created: Date?
        var title = fallbackTitle
        var mentioned: [String] = []
        var sources: [String] = []
        var turns: [(role: ChatRole, text: String, sources: [String])] = []

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
            guard let r = role else { buffer = []; return }
            // Pull this turn's `[n]: path` reference lines out of the body. The
            // numbers map citations to notes; the text is renumbered to the
            // compacted 1..K order so `sources[n-1]` is the note for inline [n]
            // in every turn (legacy transcripts can have gaps or no refs).
            var refs: [Int: String] = [:]
            var bodyLines: [String] = []
            for line in buffer {
                let t = line.trimmingCharacters(in: .whitespaces)
                if r == .assistant, t.hasPrefix("["), let close = t.firstIndex(of: "]"),
                   close < t.endIndex, t.index(after: close) < t.endIndex,
                   t[t.index(after: close)] == ":",
                   let n = Int(t[t.index(after: t.startIndex)..<close]) {
                    let path = String(t[t.index(close, offsetBy: 2)...]).trimmingCharacters(in: .whitespaces)
                    if !path.isEmpty { refs[n] = path; continue }
                }
                bodyLines.append(line)
            }
            var content = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            var turnSources: [String] = []
            if !refs.isEmpty {
                let ordered = refs.keys.sorted()
                let renumbering = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element, $0.offset + 1) })
                content = ChatAgent.renumberInlineCitations(in: content, renumbering: renumbering)
                turnSources = ordered.compactMap { refs[$0] }
            }
            if !content.isEmpty { turns.append((r, content, turnSources)) }
            buffer = []
        }
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t == "## You" { flush(); role = .user }
            else if t == "## Noto" { flush(); role = .assistant }
            // Only the document's own H1 (before any turn section) is the title —
            // an `# Heading` inside a turn (e.g. attached-note text in legacy
            // transcripts) is content, not the chat title (bug 022).
            else if role == nil, t.hasPrefix("# "), !t.hasPrefix("## ") { title = String(t.dropFirst(2)) }
            else if role != nil { buffer.append(lines[i]) }
            i += 1
        }
        flush()
        return ParsedTranscript(id: id, created: created, title: title, mentioned: mentioned, sources: sources, turns: turns)
    }

    #if DEBUG
    /// Test/preview seam: append an assistant turn carrying an edit proposal,
    /// reducing it through the normal event path (no live AI needed).
    func _seedEditProposalForTesting(_ proposal: EditProposal) {
        turns.append(ChatTurn(role: .assistant, blocks: []))
        apply(.editProposal(proposal), toAssistantAt: turns.count - 1)
    }

    /// Test seam: the first edit card's id and current status, if any.
    func _firstEditBlock() -> (id: UUID, status: EditBlockState.Status)? {
        for turn in turns {
            for block in turn.blocks {
                if case .editBlock(let s) = block { return (s.id, s.status) }
            }
        }
        return nil
    }
    #endif

    // MARK: Edit suggestions — accept / dismiss / expand

    /// Accept one edit card: re-resolve its source proposals against the note's
    /// CURRENT body (it may have changed since the suggestion), apply, and persist
    /// — through the open editor when it's the active note, else via file IO.
    /// Each card is independent; a stale anchor marks just that card `.stale`.
    func acceptEdit(blockID: UUID) {
        guard let loc = locateEditBlock(blockID), case .editBlock(var state) = turns[loc.turn].blocks[loc.block] else { return }
        guard state.status == .proposed else { return }
        guard let full = currentFullContent(for: state.targetPath) else {
            setEditStatus(blockID, .stale); return
        }
        let (prefix, body) = Self.splitFrontmatter(full)
        let (blocks, _) = EditApplier.plan(state.block.sources, in: body)
        guard !blocks.isEmpty, let newBody = try? EditApplier.apply(blocks, to: body) else {
            setEditStatus(blockID, .stale); return
        }
        let newFull = prefix + newBody
        guard writeFullContent(newFull, for: state.targetPath) else {
            setEditStatus(blockID, .stale); return
        }
        state.status = .applied
        turns[loc.turn].blocks[loc.block] = .editBlock(state)
        persist()
    }

    /// Dismiss one edit card (no change to the note).
    func dismissEdit(blockID: UUID) {
        setEditStatus(blockID, .dismissed)
        persist()
    }

    /// Reveal more context lines above (`up`) or below an edit card's hunk.
    func expandEdit(blockID: UUID, up: Bool, by amount: Int = 5) {
        guard let loc = locateEditBlock(blockID), case .editBlock(var state) = turns[loc.turn].blocks[loc.block] else { return }
        guard let full = currentFullContent(for: state.targetPath) else { return }
        let (_, body) = Self.splitFrontmatter(full)
        if up { state.beforeRadius += amount } else { state.afterRadius += amount }
        // Re-resolve this block's sources to a fresh block, then re-render its
        // preview with the larger radius (anchors may have shifted; bail if gone).
        let (blocks, _) = EditApplier.plan(state.block.sources, in: body)
        guard let fresh = blocks.first else { return }
        state.preview = EditApplier.preview(for: fresh, in: body,
                                            contextBefore: state.beforeRadius, contextAfter: state.afterRadius)
        turns[loc.turn].blocks[loc.block] = .editBlock(state)
    }

    private func setEditStatus(_ blockID: UUID, _ status: EditBlockState.Status) {
        guard let loc = locateEditBlock(blockID), case .editBlock(var state) = turns[loc.turn].blocks[loc.block] else { return }
        state.status = status
        turns[loc.turn].blocks[loc.block] = .editBlock(state)
    }

    private func locateEditBlock(_ blockID: UUID) -> (turn: Int, block: Int)? {
        for (ti, turn) in turns.enumerated() {
            if let bi = turn.blocks.firstIndex(where: { $0.id == blockID }) { return (ti, bi) }
        }
        return nil
    }

    /// Full markdown of a note, read from disk — the file is the source of truth
    /// for programmatic edits.
    private func currentFullContent(for path: String) -> String? {
        guard let url = noteURL(for: path) else { return nil }
        return fs.readString(from: url) ?? (try? String(contentsOf: url, encoding: .utf8))
    }

    /// Persist new full markdown to a note via FILE IO, stamping `modified` at the
    /// write (the timestamp is a property of the write, not of any editor). Then
    /// publish an in-process sync snapshot so a note open in the editor updates
    /// live (its session adopts the change through `handleRemoteSnapshot`).
    private func writeFullContent(_ content: String, for path: String) -> Bool {
        guard let url = noteURL(for: path) else { return false }
        let stamped = NoteFrontmatter.stampingModified(content, to: Date())
        guard fs.writeString(stamped, to: url) else { return false }
        if let id = NoteFrontmatter.id(of: stamped) {
            NoteSyncCenter.publish(NoteSyncSnapshot(
                noteID: id, fileURL: url, text: stamped,
                sourceEditorID: editApplySourceID, savedAt: Date()))
        }
        return true
    }

    /// Stable non-editor source id for sync snapshots from accepted AI edits, so
    /// editor sessions never mistake them for their own saves.
    private let editApplySourceID = UUID()

    private func noteURL(for path: String) -> URL? {
        var rel = path
        while rel.hasPrefix("/") { rel.removeFirst() }
        guard !rel.isEmpty else { return nil }
        let url = vaultURL.appendingPathComponent(rel).standardizedFileURL
        let base = vaultURL.standardizedFileURL.path
        guard url.path == base || url.path.hasPrefix(base + "/") else { return nil }
        return url
    }

    /// Split full markdown into (frontmatter prefix incl. closing `---\n`, body).
    static func splitFrontmatter(_ content: String) -> (prefix: String, body: String) {
        guard content.hasPrefix("---") else { return ("", content) }
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ("", content)
        }
        let prefix = lines[0...close].joined(separator: "\n") + "\n"
        let body = lines[(close + 1)...].joined(separator: "\n")
        return (prefix, body)
    }

    // MARK: Helpers

    private static func friendly(_ error: Error) -> String {
        if let llm = error as? LLMError {
            switch llm {
            case .missingAPIKey:
                return "Add your OpenRouter API key in Settings to chat."
            case let .http(status, body):
                // 403 with no/HTML body from a region-blocked edge (e.g. Cloudflare
                // refusing Hong Kong-origin requests) is the most common "needs VPN" case.
                if status == 403 {
                    return "OpenRouter refused the request (HTTP 403). This usually means your network/region is blocked at OpenRouter's edge. Try a VPN, or set a custom OpenRouter base URL (proxy) in Settings.\n\n\(Self.snippet(body))"
                }
                return "OpenRouter returned HTTP \(status).\n\n\(Self.snippet(body))"
            case .emptyResponse:
                return "OpenRouter returned an empty response. Please try again."
            case let .decoding(detail):
                return "Couldn't read OpenRouter's response. \(Self.snippet(detail))"
            }
        }
        // URLError (no route, timeout, DNS) — typical when the carrier's path to
        // openrouter.ai is blocked and only a VPN gets through.
        if let url = error as? URLError {
            return "Network error reaching OpenRouter (\(url.code.rawValue): \(url.localizedDescription)). If this only works on a VPN, your network is blocking openrouter.ai."
        }
        return "Something went wrong: \(error.localizedDescription)"
    }

    /// Trim a response/error body to a readable one-liner for the chat error bubble.
    private static func snippet(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.count > 300 ? String(trimmed.prefix(300)) + "…" : trimmed
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
