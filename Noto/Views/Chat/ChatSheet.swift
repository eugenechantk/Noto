import SwiftUI
import os.log
#if canImport(UIKit)
import UIKit
#endif

let chatLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "ChatSheet")

/// The AI chat surface, presented as a large-detent sheet over the file list
/// or editor. Renders the conversation (user pill + note-native AI markdown
/// with interleaved tool trace + SOURCES) and the composer.
/// See `.claude/notochat-ui/component-breakdown.md`.
struct ChatSheet: View {
    /// The session is owned by the presenter so the conversation, draft, and
    /// pending mentions survive the sheet being dismissed and reopened.
    @ObservedObject var session: ChatSession
    /// Open a cited note (tapped citation / SOURCES row): the presenter dismisses + navigates.
    var onOpenNote: ((String) -> Void)?
    /// Explicit close action. Used when hosted in a macOS inspector sidebar (no sheet
    /// `dismiss` to call); falls back to the environment `dismiss` for sheet presentation.
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var showAddContext = false
    @State private var showHistory = false
    @State private var showRename = false
    @State private var renameText = ""
    /// Measured height of the floating composer; used as the conversation's bottom inset.
    @State private var composerHeight: CGFloat = 84

    private var vaultURL: URL { session.vaultURL }

    var body: some View {
        // The GeometryReader ignores the keyboard so its height is the full
        // screen; the composer input caps at half of it (≈ half the screen).
        GeometryReader { geo in
        ZStack {
            NotoChatTokens.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if showHistory {
                    // History shown inline in the panel (not a modal sheet).
                    ChatHistoryList(vaultURL: vaultURL) { url in
                        session.loadTranscript(from: url)
                        showHistory = false
                    }
                } else if session.turns.isEmpty {
                    emptyState
                } else {
                    messageList
                }
            }
        }
        // Floating composer: the conversation scrolls BENEATH it (messageList adds a
        // bottom inset = composerHeight so the last reply clears it), with a fade.
        .overlay(alignment: .bottom) {
            if !showHistory {
                ComposerView(
                    draft: $session.draft,
                    mentioned: $session.pendingMentions,
                    isBusy: session.phase == .thinking || session.phase == .streaming,
                    vaultURL: vaultURL,
                    maxInputHeight: max(160, geo.size.height * 0.5),
                    onSend: send,
                    onAttach: { showAddContext = true }
                )
                .background(alignment: .bottom) {
                    LinearGradient(
                        colors: [NotoChatTokens.bg.opacity(0), NotoChatTokens.bg.opacity(0.95), NotoChatTokens.bg],
                        startPoint: .top, endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                }
                .background {
                    GeometryReader { g in
                        Color.clear.preference(key: ComposerHeightKey.self, value: g.size.height)
                    }
                }
            }
        }
        .onPreferenceChange(ComposerHeightKey.self) { composerHeight = $0 }
        .accessibilityIdentifier("chatSheet")
        .preferredColorScheme(.dark)
        .tint(NotoChatTokens.accent)
        .sheet(isPresented: $showAddContext) {
            AddContextSheet(vaultURL: vaultURL, initiallySelected: Set(session.pendingMentions)) { sel in
                session.pendingMentions = sel.sorted()
            }
            .chatLargeSheet()
        }
        .alert("Rename chat", isPresented: $showRename) {
            TextField("Title", text: $renameText)
            Button("Rename") { session.rename(to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: Header (grabber + title + •••)

    private var header: some View {
        ZStack {
            // Center: title (or "Chat history" while browsing past chats)
            Text(showHistory ? "Chat history" : session.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NotoChatTokens.head)
                .lineLimit(1)
                .frame(maxWidth: 210)
                .accessibilityIdentifier("chatSheet.title")

            HStack {
                // Left: close — or, while browsing history, a back arrow to the chat.
                Button {
                    if showHistory { showHistory = false }
                    else if let onClose { onClose() } else { dismiss() }
                } label: {
                    Image(systemName: showHistory ? "chevron.left" : "xmark")
                        .font(.system(size: showHistory ? 15 : 13, weight: .bold))
                        .foregroundStyle(NotoChatTokens.ink)
                        .frame(width: 34, height: 34)
                        .chatGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chatSheet.close")

                Spacer()

                // Right: more actions (hidden while browsing history)
                if showHistory {
                    Color.clear.frame(width: 34, height: 34)
                } else {
                Menu {
                    Button("New chat", systemImage: "square.and.pencil") { session.reset() }
                    Button("Chat history", systemImage: "clock") { showHistory = true }
                    if session.canManage {
                        Button("Rename chat", systemImage: "pencil") { renameText = session.title; showRename = true }
                        Button("Delete chat", systemImage: "trash", role: .destructive) { session.deleteCurrentChat() }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NotoChatTokens.ink)
                        .frame(width: 34, height: 34)
                        .chatGlassCircle()
                }
                // Render the menu as a plain button so its label (the Liquid Glass
                // circle) shows exactly like the ✕ close button — no default pill,
                // chevron, or accent tint.
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityIdentifier("chatSheet.more")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .frame(height: 52)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("Chat about notes")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(NotoChatTokens.head)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { Self.dismissKeyboard() }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(session.turns) { turn in
                        ChatTurnView(turn: turn, session: session, onOpenNote: openNote).id(turn.id)
                    }
                    if session.phase == .thinking {
                        ThinkingIndicator()
                    }
                    if case .error(let msg) = session.phase {
                        Text(msg).font(NotoChatTokens.Font.secondary())
                            .foregroundStyle(NotoChatTokens.faint)
                    }
                    // Bottom inset so the last reply scrolls clear of the floating
                    // composer; the scroll anchor sits at the end of this spacer.
                    Color.clear.frame(height: composerHeight + 8).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            // Any scroll drag dismisses the keyboard (in either direction — scrolling up
            // to read history dismisses too, not only dragging down toward the keyboard).
            .scrollDismissesKeyboard(.immediately)
            // Tapping the conversation also dismisses. A *simultaneous* tap gesture fires
            // alongside citation-link taps rather than swallowing them, so links still work.
            .simultaneousGesture(TapGesture().onEnded { Self.dismissKeyboard() })
            .onChange(of: session.turns.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    /// Resign first responder to hide the software keyboard (iOS/iPadOS). No-op
    /// elsewhere (macOS has no software keyboard).
    static func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func send() {
        let text = session.draft
        session.draft = ""
        session.send(text, mentioned: session.pendingMentions)
    }

    /// Tapped a citation / SOURCES row — hand the note to the presenter (which dismisses + opens it).
    private func openNote(_ path: String) {
        onOpenNote?(path)
    }
}

// MARK: - Turn routing

private struct ChatTurnView: View {
    let turn: ChatSession.ChatTurn
    @ObservedObject var session: ChatSession
    var onOpenNote: ((String) -> Void)?
    var body: some View {
        switch turn.role {
        case .user: UserMessageView(turn: turn)
        case .assistant: AIReplyView(turn: turn, session: session, onOpenNote: onOpenNote)
        }
    }
}

// MARK: - User message (right pill + mentioned notes below)

private struct UserMessageView: View {
    let turn: ChatSession.ChatTurn
    private var text: String {
        if case .text(_, let s)? = turn.blocks.first { return s } else { return "" }
    }
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text)
                .font(NotoChatTokens.Font.body())
                .foregroundStyle(NotoChatTokens.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(NotoChatTokens.userPill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !turn.mentioned.isEmpty {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(turn.mentioned, id: \.self) { path in
                        DocChip(path: path)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityIdentifier("chat.userMessage")
    }
}

// MARK: - AI reply (eyebrow + interleaved blocks + sources)

private struct AIReplyView: View {
    let turn: ChatSession.ChatTurn
    @ObservedObject var session: ChatSession
    var onOpenNote: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NotoEyebrow()
            ForEach(turn.blocks) { block in
                switch block {
                case .text(_, let s):
                    MarkdownText(s, citationsTappable: !turn.sources.isEmpty)
                case .tool(let step):
                    ToolStepView(step: step, onOpenNote: onOpenNote)
                case .editBlock(let state):
                    EditBlockView(
                        state: state,
                        onAccept: { session.acceptEdit(blockID: state.id) },
                        onDismiss: { session.dismissEdit(blockID: state.id) },
                        onExpand: { up in session.expandEdit(blockID: state.id, up: up) }
                    )
                }
            }
            if !turn.sources.isEmpty {
                SourcesView(sources: turn.sources, onOpenNote: onOpenNote)
            }
            if turn.hitRoundLimit {
                Text("I couldn't fully resolve that — try narrowing the question.")
                    .font(NotoChatTokens.Font.secondary())
                    .foregroundStyle(NotoChatTokens.faint)
            }
        }
        .tint(NotoChatTokens.accent)
        // Inline [n] citations are rendered as `noto-cite:n` links → open sources[n-1].
        .environment(\.openURL, OpenURLAction { url in
            // Always consume noto-cite links so they never fall through to a system
            // URL open (which on macOS pops the default browser). Open the note when
            // the citation index is valid; otherwise no-op.
            chatLogger.info("citation tap url=\(url.absoluteString, privacy: .public) sources=\(turn.sources.count)")
            guard url.scheme == "noto-cite" else { return .systemAction }
            if let n = Int(url.host ?? url.lastPathComponent),
               n >= 1, n <= turn.sources.count {
                onOpenNote?(turn.sources[n - 1])
            } else {
                chatLogger.warning("citation tap unmapped url=\(url.absoluteString, privacy: .public)")
            }
            return .handled
        })
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("chat.aiReply")
    }
}

private struct NotoEyebrow: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(NotoChatTokens.accent)
            Text("NOTO").font(NotoChatTokens.Font.eyebrow()).tracking(1.2)
                .foregroundStyle(NotoChatTokens.faint)
        }
        .accessibilityIdentifier("chat.eyebrow")
    }
}

// MARK: - Tool step (collapsible: call → result)

private struct ToolStepView: View {
    let step: ChatSession.ToolStep
    var onOpenNote: ((String) -> Void)?
    @State private var expanded = false

    private var glyph: String {
        switch step.name {
        case "search": return "sparkle.magnifyingglass"
        case "grep": return "magnifyingglass"
        case "read": return "doc"
        case "list": return "folder"
        default: return "wrench.and.screwdriver"
        }
    }
    private var canExpand: Bool { !step.hits.isEmpty }
    private static let muted = Color(white: 0.925).opacity(0.55)

    /// Grep-result note titles can be long enough to push the snippet off-row; cap them with an
    /// ellipsis so the matched snippet always stays visible after the "›".
    private static func truncatedTitle(_ path: String, max: Int = 22) -> String {
        let t = NotoChatPath.title(path)
        return t.count > max ? String(t.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…" : t
    }

    private var stepAction: String {
        switch step.name {
        case "search": return "Searched"
        case "grep": return "Matched"
        case "read": return step.isRunning ? "Reading" : "Read"
        case "list": return "Listed"
        default: return step.name.capitalized
        }
    }
    private var stepTarget: String {
        let arg = (try? JSONSerialization.jsonObject(with: Data(step.arguments.utf8))) as? [String: Any]
        switch step.name {
        case "search":
            var target = ""
            if let q = arg?["query"] as? String, !q.isEmpty { target = "‘\(q)’" }
            var filters: [String] = []
            if let d = arg?["created_after"] as? String { filters.append("created ≥ \(d)") }
            if let d = arg?["created_before"] as? String { filters.append("created ≤ \(d)") }
            if let d = arg?["updated_after"] as? String { filters.append("updated ≥ \(d)") }
            if let d = arg?["updated_before"] as? String { filters.append("updated ≤ \(d)") }
            if !filters.isEmpty { target += " · " + filters.joined(separator: ", ") }
            return target
        case "grep": if let q = arg?["query"] as? String, !q.isEmpty { return "‘\(q)’" }; return ""
        case "read": if let p = arg?["path"] as? String { return NotoChatPath.title(p) }; return ""
        case "list": if let p = arg?["path"] as? String, !p.isEmpty { return p }; return "the vault"
        default: return ""
        }
    }
    private var stepMeta: String {   // result count, e.g. " · 4 matches in 4 notes"
        guard step.name == "grep" || step.name == "search", let s = step.summary, !s.isEmpty else { return "" }
        return " · " + s
    }

    var body: some View {
        // Design's ToolBlock: a 1.5px left rule (the "trailing line") + indented content.
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1.5)
            VStack(alignment: .leading, spacing: 5) {
                Button { if canExpand { withAnimation { expanded.toggle() } } } label: {
                    HStack(spacing: 9) {
                        Image(systemName: glyph).font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.45)).frame(width: 16)
                        (Text(stepAction + (stepTarget.isEmpty ? "" : " ")).foregroundStyle(Self.muted)
                            + Text(stepTarget).foregroundStyle(NotoChatTokens.ink)
                            + Text(stepMeta).foregroundStyle(NotoChatTokens.faint))
                            .font(.system(size: 13.5)).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        if step.isRunning {
                            ProgressView().controlSize(.mini).tint(NotoChatTokens.faint)
                        } else if canExpand {
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NotoChatTokens.faint)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canExpand)

                // Expanded grep trace: one row per match → note (muted) › snippet (faint).
                if expanded {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(step.hits.enumerated()), id: \.offset) { _, hit in
                            Button { onOpenNote?(hit.path) } label: {
                                (Text(Self.truncatedTitle(hit.path)).foregroundStyle(Self.muted)
                                    + Text(" › ").foregroundStyle(Color.white.opacity(0.28))
                                    + Text(hit.snippet.trimmingCharacters(in: .whitespaces)).foregroundStyle(NotoChatTokens.faint))
                                    .font(.system(size: 12.5)).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 24).padding(.bottom, 4)
                    .accessibilityIdentifier("toolStep.result")
                }
            }
            .padding(.leading, 14)
        }
        .padding(.leading, 3)
        .accessibilityIdentifier("toolStep.\(step.name)")
    }
}

// MARK: - Sources

private struct SourcesView: View {
    let sources: [String]
    var onOpenNote: ((String) -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOURCES").font(NotoChatTokens.Font.eyebrow()).tracking(1.0)
                .foregroundStyle(NotoChatTokens.faint)
            ForEach(Array(sources.enumerated()), id: \.element) { idx, path in
                Button { onOpenNote?(path) } label: {
                    HStack(spacing: 8) {
                        Text("\(idx + 1)").font(NotoChatTokens.Font.secondary())
                            .foregroundStyle(NotoChatTokens.accent)
                            .lineLimit(1).fixedSize()
                            .frame(minWidth: 16, alignment: .trailing)
                        Image(systemName: "doc").font(.system(size: 12)).foregroundStyle(NotoChatTokens.faint)
                        Text(NotoChatPath.title(path)).font(NotoChatTokens.Font.secondary())
                            .foregroundStyle(NotoChatTokens.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sources.row.\(path)")
            }
        }
        .padding(.top, 4)
        .accessibilityIdentifier("sources")
    }
}

// MARK: - Doc chip / note ref

private struct DocChip: View {
    let path: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc").font(.system(size: 11)).foregroundStyle(NotoChatTokens.faint)
            Text(NotoChatPath.title(path)).font(NotoChatTokens.Font.secondary())
                .foregroundStyle(NotoChatTokens.faint).lineLimit(1)
        }
    }
}

private struct ThinkingIndicator: View {
    @State private var on = false
    var body: some View {
        // Just the animated dots — no "✶ NOTO" eyebrow before the loading state.
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(NotoChatTokens.faint).frame(width: 5, height: 5)
                    .opacity(on ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { on = true }
    }
}

// MARK: - Composer (mention tags above field + send)

private struct ComposerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 84
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}



private struct ComposerView: View {
    @Binding var draft: String
    @Binding var mentioned: [String]
    let isBusy: Bool
    let vaultURL: URL
    /// Max height the text input grows to before it scrolls (≈ half the sheet).
    let maxInputHeight: CGFloat
    let onSend: () -> Void
    let onAttach: () -> Void

    @State private var allNotes: [VaultNoteRef] = []

    /// The "@…" token currently being typed at the end of the draft (start index + query),
    /// or nil. Triggers as soon as "@" is typed (empty query → browse all).
    private var activeMention: (start: String.Index, query: String)? {
        guard let at = draft.lastIndex(of: "@") else { return nil }
        if at > draft.startIndex, !draft[draft.index(before: at)].isWhitespace { return nil }
        let query = String(draft[draft.index(after: at)...])
        if query.contains(where: { $0.isWhitespace }) { return nil }
        return (at, query)
    }

    private var mentionSuggestions: [VaultNoteRef] {
        guard let m = activeMention else { return [] }
        let q = m.query.lowercased()
        return allNotes
            .filter { !mentioned.contains($0.path) }
            .filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.path.lowercased().contains(q) }
            .prefix(6).map { $0 }
    }

    private func selectMention(_ note: VaultNoteRef) {
        if !mentioned.contains(note.path) { mentioned.append(note.path) }
        // Replace the "@query" being typed with the note's file name inline, so the
        // message reads naturally (e.g. "tell me about @$100M Offers ").
        if let m = activeMention {
            draft = String(draft[draft.startIndex..<m.start]) + "@" + note.title + " "
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !mentionSuggestions.isEmpty {
                mentionAutocomplete
            }
            if !mentioned.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(mentioned, id: \.self) { path in
                            HStack(spacing: 6) {
                                Image(systemName: "doc").font(.system(size: 12))
                                    .foregroundStyle(NotoChatTokens.faint)
                                Text(NotoChatPath.title(path))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(NotoChatTokens.ink).lineLimit(1)
                                Button { mentioned.removeAll { $0 == path } } label: {
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.white.opacity(0.55))
                                }.buttonStyle(.plain)
                            }
                            .padding(.leading, 9).padding(.trailing, 6)
                            .frame(height: 27)
                            // Opaque background so the tag doesn't show the conversation
                            // text behind it when the composer floats over the chat.
                            .background(NotoChatTokens.pill,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                            }
                            .accessibilityIdentifier("composer.mentionTag.\(path)")
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                // Text input on top — grows with the prompt and, once it reaches
                // ~half the sheet, caps there and scrolls internally (native
                // TextField behavior), so long prompts stay fully editable while
                // the +/send row below stays pinned. The line cap is derived from
                // half the sheet height (≈22pt/line).
                TextField("Ask anything…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(NotoChatTokens.ink)
                    .font(.body)
                    .lineLimit(1...max(3, Int(maxInputHeight / 22)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("composer.field")

                // Second row: attach (+) on the left, send on the right.
                HStack(spacing: 10) {
                    Button(action: onAttach) {
                        Image(systemName: "plus").font(.system(size: 16, weight: .medium))
                            .foregroundStyle(NotoChatTokens.ink).frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("composer.attach")

                    Spacer(minLength: 0)

                    Button(action: onSend) {
                        Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white).frame(width: 32, height: 32)
                            .background(NotoChatTokens.accent, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                    .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy ? 0.4 : 1)
                    .accessibilityIdentifier("composer.send")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(NotoChatTokens.pill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityIdentifier("composer")
        .task { allNotes = AddContextSheet.enumerateNotes(in: vaultURL) }
    }

    /// "@" autocomplete: matching notes shown above the input; tap to add as a mention.
    private var mentionAutocomplete: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(mentionSuggestions) { note in
                Button { selectMention(note) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc").font(.system(size: 13))
                            .foregroundStyle(NotoChatTokens.faint)
                        Text(note.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(NotoChatTokens.ink).lineLimit(1)
                        if !note.breadcrumb.isEmpty {
                            Text(note.breadcrumb)
                                .font(.system(size: 12))
                                .foregroundStyle(NotoChatTokens.faint).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).frame(height: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer.mentionSuggestion.\(note.path)")
                if note.id != mentionSuggestions.last?.id {
                    Divider().overlay(Color.white.opacity(0.06))
                }
            }
        }
        .background(NotoChatTokens.pill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        }
        .accessibilityIdentifier("composer.mentionAutocomplete")
    }
}

// MARK: - Liquid Glass circular control (sheet header)

extension View {
    /// Large sheet presentation on iOS/iPadOS; a no-op on macOS where sheets size
    /// to their content and `presentationDetents` is unavailable.
    @ViewBuilder
    func chatLargeSheet() -> some View {
        #if os(iOS)
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #else
        frame(minWidth: 480, minHeight: 600)
        #endif
    }

    /// iOS/macOS 26 Liquid Glass circle for the sheet's close / more buttons.
    /// A faint fill + hairline border keep the circle legible even over the chat's
    /// opaque background (where bare `glassEffect` has nothing to refract and reads
    /// flat); a translucent material fallback covers earlier OSes.
    @ViewBuilder
    func chatGlassCircle() -> some View {
        if #available(iOS 26, macOS 26, *) {
            background(Color.white.opacity(0.06), in: Circle())
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5) }
        } else {
            background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5) }
        }
    }
}

// MARK: - Shared markdown type ramp

extension MarkdownVisualSpec.Font {
    /// Bridge the editor's platform-neutral font spec to a SwiftUI font, so the AI
    /// chat renders headings/body/code at the SAME sizes and weights as the editor.
    var swiftUIFont: Font {
        let w: Font.Weight
        switch weight {
        case .regular: w = .regular
        case .medium: w = .medium
        case .semibold: w = .semibold
        case .bold: w = .bold
        }
        return isMonospaced
            ? .system(size: pointSize, weight: w, design: .monospaced)
            : .system(size: pointSize, weight: w)
    }
}

// MARK: - Lightweight markdown block renderer (note-native)

/// Renders a markdown string as note-native blocks: `#`/`##`/`###` headings,
/// `-`/`*` bullets, and paragraphs, with inline markdown (bold/italic/`code`) via
/// AttributedString — using the editor's shared `MarkdownVisualSpec` type ramp.
struct MarkdownText: View {
    let raw: String
    /// False for restored turns with no citation→note mapping (legacy
    /// transcripts that never saved per-turn reference lines): their `[n]`
    /// markers render as plain text instead of dead-looking tappable links.
    let citationsTappable: Bool

    init(_ raw: String, citationsTappable: Bool = true) {
        self.raw = raw
        self.citationsTappable = citationsTappable
    }

    // Share the editor's markdown type ramp (MarkdownVisualSpec) so AI replies and
    // the note editor render headings/body/code at the same sizes and weights.
    private static let bodyFont = MarkdownVisualSpec.bodyFont.swiftUIFont
    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return MarkdownVisualSpec.h1Font.swiftUIFont
        case 2: return MarkdownVisualSpec.h2Font.swiftUIFont
        default: return MarkdownVisualSpec.h3Font.swiftUIFont
        }
    }

    var body: some View {
        // Per-block trailing spacing (shared MarkdownVisualSpec values) for legibility.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let s):
                    inline(s).font(Self.headingFont(level)).foregroundStyle(NotoChatTokens.head)
                        .padding(.top, 6)
                        .padding(.bottom, MarkdownVisualSpec.listItemSpacing)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(Self.bodyFont).foregroundStyle(NotoChatTokens.ink)
                        inline(s).font(Self.bodyFont).foregroundStyle(NotoChatTokens.ink)
                            .lineSpacing(3)
                    }
                    .padding(.bottom, MarkdownVisualSpec.listItemSpacing)
                case .paragraph(let s):
                    inline(s).font(Self.bodyFont).foregroundStyle(NotoChatTokens.ink)
                        .lineSpacing(3)
                        .padding(.bottom, MarkdownVisualSpec.paragraphSpacing)
                }
            }
        }
    }

    private func inline(_ s: String) -> Text {
        let linked = citationsTappable ? Self.linkifyCitations(s) : s
        if let attr = try? AttributedString(markdown: linked,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }

    /// Turn inline citations into tappable links: `[1]` and grouped `[4, 9, 17]` both
    /// become individual `noto-cite://n` links (one per number). Skips `[n](…)` links
    /// and `[n]:` reference definitions.
    static func linkifyCitations(_ s: String) -> String {
        let pattern = "\\[(\\d+(?:\\s*,\\s*\\d+)*)\\](?![(:])"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let inner = ns.substring(with: m.range(at: 1))
            let nums = inner.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            // Narrow no-break spaces inside the link widen the tappable run —
            // a bare digit is a ~7pt target and taps regularly miss it.
            out += nums.map { "[\u{202F}\($0)\u{202F}](noto-cite://\($0))" }.joined(separator: ", ")
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private enum Block { case heading(Int, String), bullet(String), paragraph(String) }

    private func blocks() -> [Block] {
        var result: [Block] = []
        // The block currently being extended by lazy continuation lines. Markdown joins a
        // soft-wrapped line (a non-blank line with no block marker) into the preceding block.
        // Without this, a wrapped bullet's continuation became its own left-flush paragraph —
        // so the first line (after "• ") sat further right than the rest of the item.
        var open: Block?
        func close() { if let o = open { result.append(o); open = nil } }

        for lineSub in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = String(lineSub).trimmingCharacters(in: .whitespaces)
            if t.isEmpty { close(); continue }
            // Drop any trailing `[n]: path` citation reference-definition lines (the package
            // already strips them from the final answer; this guards the streamed text too).
            if t.range(of: "^\\[\\d+\\]:\\s", options: .regularExpression) != nil { continue }
            if t.hasPrefix("### ") { close(); result.append(.heading(3, String(t.dropFirst(4)))); continue }
            if t.hasPrefix("## ") { close(); result.append(.heading(2, String(t.dropFirst(3)))); continue }
            if t.hasPrefix("# ") { close(); result.append(.heading(1, String(t.dropFirst(2)))); continue }
            if t.hasPrefix("- ") || t.hasPrefix("* ") {
                close()
                open = .bullet(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                continue
            }
            // Lazy continuation: fold into the open bullet/paragraph; otherwise start a paragraph.
            switch open {
            case .bullet(let s): open = .bullet(s + " " + t)
            case .paragraph(let s): open = .paragraph(s + " " + t)
            default: open = .paragraph(t)
            }
        }
        close()
        return result
    }
}
