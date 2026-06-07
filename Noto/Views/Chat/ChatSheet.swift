import SwiftUI

/// The AI chat surface, presented as a large-detent sheet over the file list
/// or editor. Renders the conversation (user pill + note-native AI markdown
/// with interleaved tool trace + SOURCES) and the composer.
/// See `.claude/notochat-ui/component-breakdown.md`.
struct ChatSheet: View {
    @StateObject private var session: ChatSession
    @Environment(\.dismiss) private var dismiss

    private let vaultURL: URL
    @State private var draft = ""
    @State private var mentioned: [String]
    @State private var showAddContext = false
    @State private var showHistory = false
    @State private var showRename = false
    @State private var renameText = ""

    /// - Parameters:
    ///   - apiKey: OpenRouter key (Keychain).
    ///   - vaultURL: vault root.
    ///   - initialMention: vault-relative path pre-attached when opened from a note.
    init(apiKey: String, vaultURL: URL, initialMention: String? = nil) {
        _session = StateObject(wrappedValue: ChatSession(apiKey: apiKey, vaultURL: vaultURL))
        self.vaultURL = vaultURL
        _mentioned = State(initialValue: initialMention.map { [$0] } ?? [])
    }

    var body: some View {
        ZStack {
            NotoChatTokens.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if session.turns.isEmpty {
                    emptyState
                } else {
                    messageList
                }
                ComposerView(
                    draft: $draft,
                    mentioned: $mentioned,
                    isBusy: session.phase == .thinking || session.phase == .streaming,
                    onSend: send,
                    onAttach: { showAddContext = true }
                )
            }
        }
        .accessibilityIdentifier("chatSheet")
        .preferredColorScheme(.dark)
        .tint(NotoChatTokens.accent)
        .sheet(isPresented: $showAddContext) {
            AddContextSheet(vaultURL: vaultURL, initiallySelected: Set(mentioned)) { sel in
                mentioned = sel.sorted()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHistory) {
            ChatHistorySheet(vaultURL: vaultURL) { url in
                session.loadTranscript(from: url)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Rename chat", isPresented: $showRename) {
            TextField("Title", text: $renameText)
            Button("Rename") { session.rename(to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Header (grabber + title + •••)

    private var header: some View {
        HStack {
            Text(session.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NotoChatTokens.head)
                .lineLimit(1)
                .accessibilityIdentifier("chatSheet.title")
            Spacer()
            Menu {
                Button("New chat", systemImage: "square.and.pencil") { session.reset() }
                Button("Chat history", systemImage: "clock") { showHistory = true }
                Button("Attach files", systemImage: "paperclip") { showAddContext = true }
                if session.canManage {
                    Button("Rename chat", systemImage: "pencil") { renameText = session.title; showRename = true }
                    Button("Delete chat", systemImage: "trash", role: .destructive) { session.deleteCurrentChat() }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NotoChatTokens.ink)
                    .frame(width: 36, height: 36)
            }
            .accessibilityIdentifier("chatSheet.more")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .frame(height: 48)
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
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(session.turns) { turn in
                        ChatTurnView(turn: turn).id(turn.id)
                    }
                    if session.phase == .thinking {
                        ThinkingIndicator()
                    }
                    if case .error(let msg) = session.phase {
                        Text(msg).font(NotoChatTokens.Font.secondary())
                            .foregroundStyle(NotoChatTokens.faint)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .onChange(of: session.turns.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private func send() {
        let text = draft
        draft = ""
        session.send(text, mentioned: mentioned)
    }
}

// MARK: - Turn routing

private struct ChatTurnView: View {
    let turn: ChatSession.ChatTurn
    var body: some View {
        switch turn.role {
        case .user: UserMessageView(turn: turn)
        case .assistant: AIReplyView(turn: turn)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NotoEyebrow()
            ForEach(turn.blocks) { block in
                switch block {
                case .text(_, let s):
                    MarkdownText(s)
                case .tool(let step):
                    ToolStepView(step: step)
                }
            }
            if !turn.sources.isEmpty {
                SourcesView(sources: turn.sources)
            }
            if turn.hitRoundLimit {
                Text("I couldn't fully resolve that — try narrowing the question.")
                    .font(NotoChatTokens.Font.secondary())
                    .foregroundStyle(NotoChatTokens.faint)
            }
        }
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
    @State private var expanded = false

    private var glyph: String {
        switch step.name {
        case "grep": return "magnifyingglass"
        case "read": return "doc"
        case "list": return "folder"
        default: return "wrench.and.screwdriver"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation { expanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: glyph).font(.system(size: 12))
                        .foregroundStyle(NotoChatTokens.faint).frame(width: 16)
                    Text(step.title).font(NotoChatTokens.Font.toolLabel())
                        .foregroundStyle(NotoChatTokens.faint).lineLimit(1)
                    Spacer(minLength: 4)
                    if step.isRunning {
                        ProgressView().controlSize(.mini).tint(NotoChatTokens.faint)
                    } else if let summary = step.summary, !summary.isEmpty {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NotoChatTokens.faint)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(step.isRunning || (step.summary ?? "").isEmpty)

            if expanded, let summary = step.summary, !summary.isEmpty {
                Text(summary)
                    .font(NotoChatTokens.Font.secondary())
                    .foregroundStyle(NotoChatTokens.faint)
                    .padding(.leading, 24)
                    .accessibilityIdentifier("toolStep.result")
            }
        }
        .padding(.leading, 2)
        .overlay(alignment: .leading) {
            Rectangle().fill(NotoChatTokens.hairline).frame(width: 1)
                .padding(.leading, 7)
        }
        .padding(.leading, 8)
        .accessibilityIdentifier("toolStep.\(step.name)")
    }
}

// MARK: - Sources

private struct SourcesView: View {
    let sources: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOURCES").font(NotoChatTokens.Font.eyebrow()).tracking(1.0)
                .foregroundStyle(NotoChatTokens.faint)
            ForEach(Array(sources.enumerated()), id: \.element) { idx, path in
                HStack(spacing: 8) {
                    Text("\(idx + 1)").font(NotoChatTokens.Font.secondary())
                        .foregroundStyle(NotoChatTokens.accent).frame(width: 14)
                    Image(systemName: "doc").font(.system(size: 12)).foregroundStyle(NotoChatTokens.faint)
                    Text(NotoChatPath.title(path)).font(NotoChatTokens.Font.secondary())
                        .foregroundStyle(NotoChatTokens.ink).lineLimit(1)
                }
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
        HStack(spacing: 8) {
            NotoEyebrow()
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(NotoChatTokens.faint).frame(width: 5, height: 5)
                        .opacity(on ? 1 : 0.3)
                        .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.15), value: on)
                }
            }
        }
        .onAppear { on = true }
    }
}

// MARK: - Composer (mention tags above field + send)

private struct ComposerView: View {
    @Binding var draft: String
    @Binding var mentioned: [String]
    let isBusy: Bool
    let onSend: () -> Void
    let onAttach: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !mentioned.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(mentioned, id: \.self) { path in
                            HStack(spacing: 4) {
                                Image(systemName: "doc").font(.system(size: 11))
                                Text(NotoChatPath.title(path)).font(NotoChatTokens.Font.secondary()).lineLimit(1)
                                Button { mentioned.removeAll { $0 == path } } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                }.buttonStyle(.plain)
                            }
                            .foregroundStyle(NotoChatTokens.faint)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(NotoChatTokens.userPill, in: Capsule())
                            .accessibilityIdentifier("composer.mentionTag.\(path)")
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button(action: onAttach) {
                    Image(systemName: "plus").font(.system(size: 16, weight: .medium))
                        .foregroundStyle(NotoChatTokens.ink).frame(width: 28, height: 28)
                }
                .accessibilityIdentifier("composer.attach")

                TextField("Ask anything…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(NotoChatTokens.ink)
                    .lineLimit(1...5)
                    .accessibilityIdentifier("composer.field")

                Button(action: onSend) {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white).frame(width: 32, height: 32)
                        .background(NotoChatTokens.accent, in: Circle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy ? 0.4 : 1)
                .accessibilityIdentifier("composer.send")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(NotoChatTokens.pill, in: Capsule())
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityIdentifier("composer")
    }
}

// MARK: - Lightweight markdown block renderer (note-native)

/// Renders a markdown string as note-native blocks: `##` headings, `-`/`*`
/// bullets, and paragraphs, with inline markdown (bold/italic/`code`) via
/// AttributedString. Good enough for the streaming AI answer; can be replaced
/// by the editor's renderer later.
struct MarkdownText: View {
    let raw: String
    init(_ raw: String) { self.raw = raw }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let s):
                    inline(s).font(NotoChatTokens.Font.h2()).foregroundStyle(NotoChatTokens.head)
                        .padding(.top, 4)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(NotoChatTokens.ink)
                        inline(s).foregroundStyle(NotoChatTokens.ink)
                    }
                case .paragraph(let s):
                    inline(s).font(NotoChatTokens.Font.body()).foregroundStyle(NotoChatTokens.ink)
                        .lineSpacing(3)
                }
            }
        }
    }

    private func inline(_ s: String) -> Text {
        if let attr = try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }

    private enum Block { case heading(String), bullet(String), paragraph(String) }

    private func blocks() -> [Block] {
        raw.split(separator: "\n", omittingEmptySubsequences: false).compactMap { lineSub in
            let line = String(lineSub)
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return nil }
            if t.hasPrefix("## ") { return .heading(String(t.dropFirst(3))) }
            if t.hasPrefix("# ") { return .heading(String(t.dropFirst(2))) }
            if t.hasPrefix("- ") || t.hasPrefix("* ") { return .bullet(String(t.dropFirst(2))) }
            return .paragraph(t)
        }
    }
}
