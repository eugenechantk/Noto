#if os(iOS)
import Foundation
import Testing
import NotoChat
@testable import Noto

/// Test case index (bug 022 — restored chats must show the conversation as displayed)
/// 1. transcriptTurnsUseTypedTextAndDropToolSteps — persistence maps display turns: typed user text, assistant text + per-turn sources, tool blocks and empty placeholders dropped
/// 2. transcriptRoundTripPreservesDisplayConversation — markdown() → parse() reproduces turns AND per-turn sources for every assistant turn
/// 3. legacyComposedTranscriptUnwrapsOnParse — old transcripts with composed user prompts strip down to the typed message; embedded headings don't clobber the title
/// 4. legacyPerTurnReferenceLinesMapAndRenumber — `[n]: path` lines inside an assistant section become that turn's sources; non-contiguous inline numbers renumber; unmapped citations are removed
/// 5. legacyLastTurnFallsBackToFrontmatterSources — turns without reference lines keep the old behavior (frontmatter sources on the final answer)
@Suite("Chat transcript restoration")
struct ChatTranscriptRestorationTests {

    @MainActor
    @Test("Persisted turns are the display conversation with per-turn sources")
    func transcriptTurnsUseTypedTextAndDropToolSteps() {
        let displayTurns: [ChatSession.ChatTurn] = [
            .init(role: .user, blocks: [.text(id: UUID(), "what did I save about pricing?")]),
            .init(role: .assistant, blocks: [
                .tool(.init(name: "search", arguments: "{}", summary: "3 results", isRunning: false)),
                .text(id: UUID(), "You saved two notes about pricing [1]."),
            ], sources: ["Projects/Pricing.md"]),
            .init(role: .assistant, blocks: []),   // failed-send placeholder → dropped
        ]

        let persisted = ChatSession.transcriptTurns(from: displayTurns)

        #expect(persisted.count == 2)
        #expect(persisted[0].role == .user)
        #expect(persisted[0].text == "what did I save about pricing?")
        #expect(persisted[1].role == .assistant)
        #expect(persisted[1].text == "You saved two notes about pricing [1].")
        #expect(persisted[1].sources == ["Projects/Pricing.md"])
    }

    @MainActor
    @Test("Saved markdown parses back with per-turn sources intact")
    func transcriptRoundTripPreservesDisplayConversation() {
        let transcript = ChatTranscript(
            title: "Pricing chat",
            mentioned: ["Projects/Pricing.md"],
            sources: ["Daily Notes/2026-06-03.md"],
            turns: [
                .user("what did I save about pricing?"),
                .assistant("You saved two notes about pricing [1].", sources: ["Projects/Pricing.md"]),
                .user("and anything from last week?"),
                .assistant("Yes — one note from Tuesday [1].", sources: ["Daily Notes/2026-06-03.md"]),
            ]
        )

        let parsed = ChatSession.parse(transcript.markdown(), fallbackTitle: "x")

        #expect(parsed.title == "Pricing chat")
        #expect(parsed.mentioned == ["Projects/Pricing.md"])
        #expect(parsed.turns.map(\.text) == [
            "what did I save about pricing?",
            "You saved two notes about pricing [1].",
            "and anything from last week?",
            "Yes — one note from Tuesday [1].",
        ])
        #expect(parsed.turns.map(\.role) == [.user, .assistant, .user, .assistant])
        #expect(parsed.turns[1].sources == ["Projects/Pricing.md"])
        #expect(parsed.turns[3].sources == ["Daily Notes/2026-06-03.md"])
        #expect(parsed.turns[0].sources.isEmpty)
    }

    @MainActor
    @Test("Legacy transcripts with composed prompts unwrap to the typed message")
    func legacyComposedTranscriptUnwrapsOnParse() {
        // A transcript saved by the old code: the user turn carries the full
        // attachment wrapper (note text + delimiter + typed message).
        let composed = ChatAgent.attachmentContextPrefix + "\n\n"
            + "# Pricing\n\nThe floor is $29 and the anchor is $99."
            + ChatAgent.attachmentContextDelimiter + "summarize my pricing note"
        let legacy = ChatTranscript(
            title: "Legacy chat",
            turns: [.user(composed), .assistant("The floor is $29 [1].")]
        )

        let parsed = ChatSession.parse(legacy.markdown(), fallbackTitle: "x")
        // loadTranscript runs every parsed user turn through the stripper:
        let restoredUserText = ChatAgent.strippedComposedUserContent(parsed.turns[0].text)

        #expect(restoredUserText == "summarize my pricing note")
        #expect(parsed.turns[1].text == "The floor is $29 [1].")
        // The `# Pricing` heading inside the attached content must not clobber
        // the chat title — only the document's own H1 (before any turn) counts.
        #expect(parsed.title == "Legacy chat")
    }

    @MainActor
    @Test("Per-turn reference lines map to sources and renumber non-contiguous citations")
    func legacyPerTurnReferenceLinesMapAndRenumber() {
        // Real-world legacy shape (Vibe coding chat): inline [1] and [4] with
        // matching ref lines, plus an unmapped [11] the model never defined.
        let markdown = """
        ---
        id: 00000000-0000-0000-0000-000000000001
        type: chat
        ---

        # Refs chat

        ## You

        which notes mention keyboards?

        ## Noto

        Custom keycaps appear in your DIY note [1], and the concept resurfaces later [4]. An undefined claim [11].

        [1]: Captures/Keyboards.md
        [4]: Projects/Things I wanna make.md
        """

        let parsed = ChatSession.parse(markdown, fallbackTitle: "x")
        let answer = parsed.turns[1]

        // Refs extracted as this turn's sources, in number order…
        #expect(answer.sources == ["Captures/Keyboards.md", "Projects/Things I wanna make.md"])
        // …inline citations renumbered to match (1→1, 4→2), the unmapped [11] removed,
        // and the reference lines stripped from the displayed text.
        #expect(answer.text == "Custom keycaps appear in your DIY note [1], and the concept resurfaces later [2]. An undefined claim.")
        #expect(!answer.text.contains("[1]:"))
    }

    @MainActor
    @Test("Turns without reference lines keep the frontmatter-sources fallback shape")
    func legacyLastTurnFallsBackToFrontmatterSources() {
        let legacy = ChatTranscript(
            title: "Old chat",
            sources: ["Captures/Only.md"],
            turns: [.user("q1"), .assistant("a1 [1]"), .user("q2"), .assistant("a2 [1]")]
        )
        let parsed = ChatSession.parse(legacy.markdown(), fallbackTitle: "x")

        // parse() leaves per-turn sources empty when no ref lines exist —
        // loadTranscript then applies frontmatter sources to the LAST turn only.
        #expect(parsed.turns.allSatisfy { $0.sources.isEmpty })
        #expect(parsed.sources == ["Captures/Only.md"])
    }
}
#endif
