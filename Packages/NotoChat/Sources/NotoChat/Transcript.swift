import Foundation
import NotoVault

/// One displayed conversation turn in a saved chat. Assistant turns carry
/// their own cited sources in inline-number order (`sources[n-1]` is the note
/// for inline `[n]`), so citations stay tappable in every restored turn — not
/// just the last one (whose sources used to be the only ones saved, in
/// frontmatter).
public struct TranscriptTurn: Sendable, Equatable {
    public var role: ChatRole
    public var text: String
    public var sources: [String]

    public init(role: ChatRole, text: String, sources: [String] = []) {
        self.role = role
        self.text = text
        self.sources = sources
    }

    public static func user(_ text: String) -> TranscriptTurn {
        TranscriptTurn(role: .user, text: text)
    }

    public static func assistant(_ text: String, sources: [String] = []) -> TranscriptTurn {
        TranscriptTurn(role: .assistant, text: text, sources: sources)
    }
}

/// A chat saved as a vault note. Serializes to markdown with YAML frontmatter so chats are
/// first-class notes in `Chats/`.
public struct ChatTranscript: Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var model: String
    public var mentioned: [String]
    public var sources: [String]
    /// User/assistant turns in order (system/tool messages are omitted from the saved document).
    public var turns: [TranscriptTurn]

    public init(id: UUID = UUID(),
                title: String,
                createdAt: Date = Date(),
                modifiedAt: Date = Date(),
                model: String = defaultModel,
                mentioned: [String] = [],
                sources: [String] = [],
                turns: [TranscriptTurn] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.model = model
        self.mentioned = mentioned
        self.sources = sources
        self.turns = turns
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Render the transcript as markdown with frontmatter. Each assistant
    /// section ends with its own `[n]: path` reference lines so per-turn
    /// citations survive the round trip.
    public func markdown() -> String {
        var out = "---\n"
        out += "id: \(id.uuidString)\n"
        out += "created: \(Self.iso.string(from: createdAt))\n"
        out += "modified: \(Self.iso.string(from: modifiedAt))\n"
        out += "type: chat\n"
        out += "model: \(model)\n"
        if !mentioned.isEmpty {
            out += "mentioned:\n" + mentioned.map { "  - \($0)" }.joined(separator: "\n") + "\n"
        }
        if !sources.isEmpty {
            out += "sources:\n" + sources.map { "  - \($0)" }.joined(separator: "\n") + "\n"
        }
        out += "---\n\n"
        out += "# \(title)\n\n"
        for turn in turns {
            switch turn.role {
            case .user:
                out += "## You\n\n\(turn.text)\n\n"
            case .assistant:
                guard !turn.text.isEmpty else { continue }
                out += "## Noto\n\n\(turn.text)\n\n"
                if !turn.sources.isEmpty {
                    out += turn.sources.enumerated()
                        .map { "[\($0.offset + 1)]: \($0.element)" }
                        .joined(separator: "\n") + "\n\n"
                }
            case .system, .tool:
                continue
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// A filesystem-safe filename derived from the title.
    public func fileName() -> String {
        let base = title.isEmpty ? "Chat" : title
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let safe = base.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return (safe.isEmpty ? "Chat" : safe) + ".md"
    }
}

/// Save a transcript into `chatsDirectory` (created if needed). Returns the file URL on success.
@discardableResult
public func saveTranscript(_ transcript: ChatTranscript,
                           toChatsDirectory chatsDirectory: URL,
                           fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem()) -> URL? {
    if !fileSystem.fileExists(at: chatsDirectory) {
        _ = fileSystem.createDirectory(at: chatsDirectory)
    }
    let url = chatsDirectory.appendingPathComponent(transcript.fileName())
    return fileSystem.writeString(transcript.markdown(), to: url) ? url : nil
}
