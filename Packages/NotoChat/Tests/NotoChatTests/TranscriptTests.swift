import Foundation
import Testing
@testable import NotoChat

// Verifies SC9: transcript markdown serialization + save.
@Suite struct TranscriptTests {

    @Test func rendersFrontmatterAndTurns() {
        let transcript = ChatTranscript(
            title: "Pricing questions",
            model: "google/gemini-3.1-flash-lite",
            mentioned: ["Projects/Alpha/Spec.md"],
            sources: ["Projects/Alpha/Spec.md", "Captures/Idea.md"],
            turns: [
                .user("How do these compare?"),
                .assistant("They share a usage-based base."),
            ]
        )
        let md = transcript.markdown()
        #expect(md.hasPrefix("---\n"))
        #expect(md.contains("type: chat"))
        #expect(md.contains("model: google/gemini-3.1-flash-lite"))
        #expect(md.contains("sources:\n  - Projects/Alpha/Spec.md\n  - Captures/Idea.md"))
        #expect(md.contains("# Pricing questions"))
        #expect(md.contains("## You\n\nHow do these compare?"))
        #expect(md.contains("## Noto\n\nThey share a usage-based base."))
        // System/tool messages are excluded from the saved document.
        #expect(!md.contains("## System"))
    }

    @Test func sanitizesFileName() {
        let t = ChatTranscript(title: "Q2/Q3: pricing?")
        #expect(t.fileName() == "Q2 Q3  pricing.md")
    }

    @Test func savesToChatsDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notochat-chats-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let transcript = ChatTranscript(title: "Saved chat",
                                        turns: [.user("hi"), .assistant("hello")])
        let url = try #require(saveTranscript(transcript, toChatsDirectory: dir))
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.contains("# Saved chat"))
        #expect(written.contains("## Noto\n\nhello"))
    }
}
