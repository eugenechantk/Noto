import Foundation
import NotoAgentCore
import NotoVault
import Testing

@Suite("Noto agent filesystem integration", .serialized)
struct NotoAgentServiceTests {
    @Test("daily append creates the templated note and deduplicates retries")
    func dailyAppendIsIdempotent() throws {
        let fixture = try Fixture()
        let date = try #require(ISO8601DateFormatter().date(from: "2026-08-07T09:30:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Hong_Kong"))

        let first = try fixture.service.dailyAppend(
            text: "Onboarding should begin with a concrete win.",
            requestID: "wa-123",
            date: date,
            calendar: calendar
        )
        let retry = try fixture.service.dailyAppend(
            text: "Onboarding should begin with a concrete win.",
            requestID: "wa-123",
            date: date,
            calendar: calendar
        )

        #expect(first.changed)
        #expect(!first.duplicate)
        #expect(!retry.changed)
        #expect(retry.duplicate)
        #expect(first.path == "Daily Notes/2026-08-07.md")
        #expect(first.deepLink == "https://noto.eugenechantk.me/open#path=Daily%20Notes%2F2026-08-07.md")
        #expect(retry.deepLink == first.deepLink)

        let markdown = try String(contentsOf: fixture.root.appendingPathComponent(first.path), encoding: .utf8)
        #expect(markdown.contains(DailyNoteTemplate.notoDefault.marker))
        #expect(markdown.contains("## Captures"))
        #expect(markdown.contains("modified: 2026-08-07T09:30:00Z"))
        #expect(markdown.components(separatedBy: "Onboarding should begin with a concrete win.").count == 2)
    }

    @Test("append preserves frontmatter, stamps modified, and refreshes search")
    func appendAndSearch() throws {
        let fixture = try Fixture()
        let noteURL = try fixture.writeNote(
            path: "Projects/Noto.md",
            title: "Noto capture",
            body: "Frictionless capture is the central product promise."
        )

        let result = try fixture.service.append(
            relativePath: "Projects/Noto.md",
            text: "A WhatsApp inbox reduces capture latency.",
            requestID: "wa-append-1"
        )

        #expect(result.changed)
        #expect(result.deepLink == "https://noto.eugenechantk.me/open#path=Projects%2FNoto.md")
        let markdown = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(NoteFrontmatter.id(of: markdown) != nil)
        #expect(markdown.contains("modified:"))
        #expect(markdown.contains("A WhatsApp inbox reduces capture latency."))

        let hits = try fixture.service.search(query: "WhatsApp inbox", limit: 5)
        #expect(hits.contains { $0.path == "Projects/Noto.md" })
        #expect(hits.first { $0.path == "Projects/Noto.md" }?.deepLink == result.deepLink)
    }

    @Test("read supports bounded line ranges")
    func boundedRead() throws {
        let fixture = try Fixture()
        _ = try fixture.writeNote(path: "Ideas/Flow.md", title: "Flow", body: "alpha\nbeta\ngamma")

        let result = try fixture.service.read(relativePath: "Ideas/Flow.md", startLine: 8, endLine: 9)

        #expect(result.path == "Ideas/Flow.md")
        #expect(result.deepLink == "https://noto.eugenechantk.me/open#path=Ideas%2FFlow.md")
        #expect(result.startLine == 8)
        #expect(result.endLine == 9)
        #expect(result.text == "beta\ngamma")
    }

    @Test("append rejects traversal and symlinks that escape the vault")
    func rejectsEscapedPaths() throws {
        let fixture = try Fixture()

        #expect(throws: NotoAgentError.self) {
            _ = try fixture.service.append(
                relativePath: "../outside.md",
                text: "nope",
                requestID: "escape-1"
            )
        }

        let outside = fixture.root.deletingLastPathComponent().appendingPathComponent("outside.md")
        try "# Outside".write(to: outside, atomically: true, encoding: .utf8)
        let link = fixture.root.appendingPathComponent("linked.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        #expect(throws: NotoAgentError.self) {
            _ = try fixture.service.append(
                relativePath: "linked.md",
                text: "nope",
                requestID: "escape-2"
            )
        }
    }

    @Test("health reports the temporary vault and note counts")
    func health() throws {
        let fixture = try Fixture()
        _ = try fixture.writeNote(path: "One.md", title: "One", body: "first")
        _ = try fixture.writeNote(path: "Daily Notes/2026-08-06.md", title: "Yesterday", body: "second")

        let health = try fixture.service.health()

        #expect(health.readable)
        #expect(health.writable)
        #expect(health.markdownFiles == 2)
        #expect(health.dailyNotes == 1)
    }
}

private struct Fixture {
    let root: URL
    let service: NotoAgentService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoAgentCLI-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let index = root.appendingPathComponent(".test-index", isDirectory: true)
        service = NotoAgentService(vaultURL: root, indexDirectory: index)
    }

    func writeNote(path: String, title: String, body: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let markdown = VaultMarkdown.makeFrontmatter(id: UUID()) + "# \(title)\n\(body)"
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
