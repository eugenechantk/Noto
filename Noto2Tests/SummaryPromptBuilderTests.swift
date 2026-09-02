import Foundation
import NotoSearch
import Testing
@testable import Noto2

/// Test case index
/// 1. takesTopNDistinctNotesAndTruncates — ranked hits dedupe by file, cap at maxSources, bodies truncated, frontmatter stripped (SC4)
/// 2. emptyResultsProducesNoPrompt — no sources → nil messages/request (SC4)
/// 3. messagesCarryQueryTitlesAndBodies — system + user message, user lists each source with title/path/body (SC4)
/// 4. unreadableFilesAreSkipped — readBody nil drops the source without breaking the rest (SC4)
/// 5. renderedStripsMarkdownAsterisksAndBullets — **bold** becomes styling (no literal asterisks), "* " lines become "•", newlines kept (SC4)
struct SummaryPromptBuilderTests {
    @Test func renderedStripsMarkdownAsterisksAndBullets() {
        let rendered = SummaryPromptBuilder.rendered("**Meeting Notes** covers the roadmap.\n*   first point\n- second point")
        let plain = String(rendered.characters)
        #expect(!plain.contains("*"))
        #expect(plain == "Meeting Notes covers the roadmap.\n• first point\n• second point")
        let system = SummaryPromptBuilder.messages(query: "q", sources: [.init(title: "t", relativePath: "t.md", body: "b")])?.first?.content ?? ""
        #expect(system.contains("no Markdown"))
    }

    private let vault = URL(fileURLWithPath: "/tmp/vault", isDirectory: true)

    private func hit(_ name: String, title: String? = nil, kind: SearchResultKind = .note) -> SearchResult {
        SearchResult(
            id: UUID(),
            kind: kind,
            noteID: UUID(),
            fileURL: vault.appendingPathComponent("\(name).md"),
            title: title ?? name,
            breadcrumb: "",
            snippet: "",
            lineStart: nil,
            score: 1,
            updatedAt: nil,
            createdAt: nil
        )
    }

    @Test func takesTopNDistinctNotesAndTruncates() {
        var hits: [SearchResult] = []
        for index in 0..<12 {
            hits.append(hit("note\(index)"))
            hits.append(hit("note\(index)", kind: .section)) // duplicate file as a section hit
        }
        let longBody = String(repeating: "x", count: SummaryPromptBuilder.maxCharactersPerSource + 50)
        let sources = SummaryPromptBuilder.sources(from: hits, vaultURL: vault) { url in
            "---\nid: abc\n---\n\n" + (url.lastPathComponent == "note0.md" ? longBody : "body of \(url.lastPathComponent)")
        }
        #expect(sources.count == SummaryPromptBuilder.maxSources)
        #expect(sources.map(\.title) == (0..<SummaryPromptBuilder.maxSources).map { "note\($0)" })
        #expect(sources[0].body.count == SummaryPromptBuilder.maxCharactersPerSource + 1) // + ellipsis
        #expect(sources[0].body.hasSuffix("…"))
        #expect(sources[1].body == "body of note1.md")      // frontmatter stripped
        #expect(sources[1].relativePath == "note1.md")
    }

    @Test func emptyResultsProducesNoPrompt() {
        #expect(SummaryPromptBuilder.sources(from: [], vaultURL: vault) { _ in "x" }.isEmpty)
        #expect(SummaryPromptBuilder.messages(query: "q", sources: []) == nil)
        #expect(SummaryPromptBuilder.request(query: "q", sources: []) == nil)
    }

    @Test func messagesCarryQueryTitlesAndBodies() throws {
        let sources = [
            SummaryPromptBuilder.Source(title: "Granite", relativePath: "ml/granite.md", body: "Embeddings on device."),
            SummaryPromptBuilder.Source(title: "Search plan", relativePath: "plans/search.md", body: "RRF over FTS5."),
        ]
        let messages = try #require(SummaryPromptBuilder.messages(query: "semantic search", sources: sources))
        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[1].role == .user)
        let user = try #require(messages[1].content)
        #expect(user.hasPrefix("Query: semantic search"))
        #expect(user.contains("### 1. Granite (ml/granite.md)\nEmbeddings on device."))
        #expect(user.contains("### 2. Search plan (plans/search.md)\nRRF over FTS5."))
        let request = try #require(SummaryPromptBuilder.request(query: "semantic search", sources: sources))
        #expect(request.model == SummaryPromptBuilder.model)
        #expect(request.tools.isEmpty)
    }

    @Test func unreadableFilesAreSkipped() {
        let sources = SummaryPromptBuilder.sources(from: [hit("a"), hit("b"), hit("c")], vaultURL: vault) { url in
            url.lastPathComponent == "b.md" ? nil : "body"
        }
        #expect(sources.map(\.title) == ["a", "c"])
    }
}
