import Foundation
import NotoChat
import NotoSearch

/// Turns search hits into the prompt for the streamed summary. Pure, so the
/// top-N selection, truncation, and prompt shape are unit-testable.
enum SummaryPromptBuilder {
    struct Source: Equatable {
        let title: String
        let relativePath: String
        let body: String
    }

    static let maxSources = 8
    static let maxCharactersPerSource = 1_800
    static let model = NotoChat.defaultModel

    /// Picks the first `maxSources` distinct notes (hits are ranked; a note can
    /// appear several times as sections) and truncates each body.
    static func sources(
        from results: [SearchResult],
        vaultURL: URL,
        readBody: (URL) -> String?
    ) -> [Source] {
        var seen = Set<URL>()
        var out: [Source] = []
        let root = vaultURL.standardizedFileURL.path
        for result in results {
            let url = result.fileURL.standardizedFileURL
            guard !seen.contains(url) else { continue }
            seen.insert(url)
            guard let raw = readBody(url) else { continue }
            let body = truncate(stripFrontmatter(raw), to: maxCharactersPerSource)
            guard !body.isEmpty else { continue }
            let path = url.path.hasPrefix(root + "/") ? String(url.path.dropFirst(root.count + 1)) : url.lastPathComponent
            out.append(Source(title: result.title, relativePath: path, body: body))
            if out.count == maxSources { break }
        }
        return out
    }

    static func messages(query: String, sources: [Source]) -> [ChatMessage]? {
        guard !sources.isEmpty else { return nil }
        let system = """
        You summarize the user's own notes. You are given the notes that matched a search query. \
        Write a tight summary (3-6 sentences, or a short bullet list if the notes are unrelated) of what these notes say about the query. \
        Reference notes by their title in plain text. Do not invent facts that are not in the notes. Do not add a preamble. \
        Plain prose only: no Markdown, no asterisks, no headings; if you must list, use "•" bullets on separate lines.
        """
        var user = "Query: \(query)\n\nMatching notes:\n"
        for (index, source) in sources.enumerated() {
            user += "\n### \(index + 1). \(source.title) (\(source.relativePath))\n\(source.body)\n"
        }
        return [
            ChatMessage(role: .system, content: system),
            ChatMessage(role: .user, content: user),
        ]
    }

    static func request(query: String, sources: [Source]) -> ChatRequest? {
        guard let messages = messages(query: query, sources: sources) else { return nil }
        return ChatRequest(model: model, messages: messages, temperature: 0.2, maxTokens: 400)
    }

    // MARK: - Rendering

    /// Renders streamed summary text: inline Markdown (bold/italic/links) becomes
    /// styling, newlines survive, and leading "* "/"- " bullets become "•". Pure.
    static func rendered(_ summary: String) -> AttributedString {
        let bulleted = summary
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.drop(while: { $0 == " " })
                if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") {
                    return "• " + trimmed.dropFirst(2).drop(while: { $0 == " " })
                }
                return String(line)
            }
            .joined(separator: "\n")
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: bulleted, options: options)) ?? AttributedString(bulleted)
    }

    // MARK: - Text helpers

    static func stripFrontmatter(_ content: String) -> String {
        guard content.hasPrefix("---") else { return content }
        let lines = content.components(separatedBy: "\n")
        guard lines.count > 1 else { return content }
        for index in 1..<lines.count where lines[index].trimmingCharacters(in: .whitespaces) == "---" {
            return lines[(index + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return content
    }

    static func truncate(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}
