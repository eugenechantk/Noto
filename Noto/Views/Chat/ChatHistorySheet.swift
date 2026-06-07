import SwiftUI

/// The past-chats list (title · snippet · relative date), rendered INLINE inside
/// the chat panel (••• → Chat history) rather than a modal sheet. Chats are saved
/// as `.md` notes in `<vault>/Chats/`, so this is that folder as rows.
struct ChatHistoryList: View {
    let vaultURL: URL
    /// Called with the chosen chat's file URL to resume it.
    let onSelect: (URL) -> Void
    @State private var chats: [ChatHistorySheet.PastChat] = []

    var body: some View {
        Group {
            if chats.isEmpty {
                VStack {
                    Spacer()
                    Text("No chats yet")
                        .font(NotoChatTokens.Font.body())
                        .foregroundStyle(NotoChatTokens.faint)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(chats) { chat in
                        Button { onSelect(chat.url) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(chat.title).font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(NotoChatTokens.head).lineLimit(1)
                                    Spacer()
                                    Text(chat.relativeDate).font(NotoChatTokens.Font.secondary())
                                        .foregroundStyle(NotoChatTokens.faint)
                                }
                                if !chat.snippet.isEmpty {
                                    Text(chat.snippet).font(NotoChatTokens.Font.secondary())
                                        .foregroundStyle(NotoChatTokens.faint).lineLimit(1)
                                }
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("chatHistory.row")
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .task { chats = ChatHistorySheet.loadChats(in: vaultURL) }
        .accessibilityIdentifier("chatHistory.list")
    }
}

/// Past chats, presented as its own sheet (••• → Chat history). Chats are
/// saved as `.md` notes in `<vault>/Chats/`, so this is effectively that
/// folder rendered as title · snippet · relative date rows.
/// See `.claude/notochat-ui/component-breakdown.md`.
struct ChatHistorySheet: View {
    let vaultURL: URL
    /// Called with the chosen chat's file URL to resume it.
    let onSelect: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chats: [PastChat] = []

    var body: some View {
        ZStack {
            NotoChatTokens.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if chats.isEmpty {
                    Spacer()
                    Text("No chats yet")
                        .font(NotoChatTokens.Font.body())
                        .foregroundStyle(NotoChatTokens.faint)
                    Spacer()
                } else {
                    List {
                        ForEach(chats) { chat in
                            Button {
                                onSelect(chat.url)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(chat.title).font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(NotoChatTokens.head).lineLimit(1)
                                        Spacer()
                                        Text(chat.relativeDate).font(NotoChatTokens.Font.secondary())
                                            .foregroundStyle(NotoChatTokens.faint)
                                    }
                                    if !chat.snippet.isEmpty {
                                        Text(chat.snippet).font(NotoChatTokens.Font.secondary())
                                            .foregroundStyle(NotoChatTokens.faint).lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .accessibilityIdentifier("chatHistory.row")
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(NotoChatTokens.accent)
        .task { chats = Self.loadChats(in: vaultURL) }
        .accessibilityIdentifier("chatHistory.sheet")
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NotoChatTokens.ink).frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            Spacer()
            Text("Chat history").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NotoChatTokens.head)
            Spacer()
            Color.clear.frame(width: 30, height: 30)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
    }

    struct PastChat: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
        let snippet: String
        let modified: Date
        var relativeDate: String { Self.fmt.localizedString(for: modified, relativeTo: Date()) }
        static let fmt = RelativeDateTimeFormatter()
    }

    static func loadChats(in vaultURL: URL) -> [PastChat] {
        let fm = FileManager.default
        let dir = vaultURL.appendingPathComponent("Chats")
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var out: [PastChat] = []
        for url in urls where url.pathExtension == "md" {
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            out.append(PastChat(
                url: url,
                title: Self.title(from: content, fallback: url.deletingPathExtension().lastPathComponent),
                snippet: Self.snippet(from: content),
                modified: modified
            ))
        }
        return out.sorted { $0.modified > $1.modified }
    }

    /// Title = the `# Heading` line (after frontmatter), else the filename.
    private static func title(from content: String, fallback: String) -> String {
        for line in content.split(separator: "\n") where line.hasPrefix("# ") {
            return String(line.dropFirst(2))
        }
        return fallback
    }

    /// Snippet = first non-empty body line that isn't frontmatter/heading.
    private static func snippet(from content: String) -> String {
        var inFrontmatter = false
        for raw in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" { inFrontmatter.toggle(); continue }
            if inFrontmatter || line.isEmpty || line.hasPrefix("#") { continue }
            return String(line.prefix(80))
        }
        return ""
    }
}
