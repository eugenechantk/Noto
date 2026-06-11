# Bug 022: Restored chats show attached-note text and context plumbing inside user messages

## Status: FIX DEPLOYED — verified in simulator 2026-06-11 (worktree `chat-restoration`, unmerged)

## Description

Restoring a chat from history shows each user message with the full attached-document text (and surrounding context plumbing) baked in, instead of exactly what the user typed. The restored conversation should look exactly like the original conversation did on screen.

## Steps to Reproduce

1. Open chat with a note attached (the active document auto-attaches), ask a question, get an answer. The on-screen user bubble shows just the typed question.
2. Start a new chat, then restore the previous one from History.
3. The user bubble now contains "The user attached these notes as context:" + the entire note text + `---` + the question. With notes that themselves contain `## …` headings, content also bleeds across bubbles (the parser splits saved markdown on `## You` / `## Noto`).

## Root Cause

`ChatSession.persist()` saves `history` — the **LLM message array** (`AgentResult.messages`), where each user message is the *composed prompt* built by `ChatAgent.buildInitialMessages` ("The user attached these notes as context:\n\n<full note text>\n\n---\n\n<typed message>"). The saved `Chats/*.md` therefore contains the prompt plumbing, and `parse()`'s heading-based splitting makes embedded note headings bleed between turns. The UI's `turns` array — which holds exactly what was displayed — was never used for persistence.

## Success Criteria

### 1. New transcripts persist the display conversation (typed text + assistant prose)
- [x] Unit test — `NotoTests/ChatTranscriptRestorationTests` → `transcriptTurnsUseTypedTextAndDropToolSteps` (tool blocks + empty placeholders dropped)
- [x] Round-trip — `transcriptRoundTripPreservesDisplayConversation` (markdown → parse reproduces turns)

### 2. Legacy transcripts restore to exactly what was typed
- [x] Unit tests — `legacyComposedTranscriptUnwrapsOnParse` (app) + 3 stripper tests in `NotoChatTests/ChatAgentTests` (real composed prompt, delimiter-inside-attachment, plain-text passthrough)
- [x] Simulator E2E — seeded a legacy-format transcript (full attached-note text + wrapper); restored chat shows only "summarize my pricing discussion" in the user bubble; answer intact with citation

### 3. Embedded headings in legacy content don't clobber the chat title
- [x] Unit test — title assertion in `legacyComposedTranscriptUnwrapsOnParse`
- [x] Simulator E2E — sheet title shows "Pricing question" (was "Meeting Notes" before the parse fix)

### 4. History list previews show the typed text, not the wrapper
- [x] Simulator E2E — row snippet reads "summarize my pricing discussion" (was "The user attached these notes as context:")

### 5. Live LLM continuation unchanged
- [x] By construction — in-memory `history` still carries the composed messages during an active session; only persistence and restore changed.

Suites: NotoChat 37/37 (excl. live), NotoTests/ChatTranscriptRestorationTests 6/6, app builds + runs in simulator.

## Round 2 (Eugene's follow-ups, 2026-06-11): real-vault testing, continuation context, per-turn citations

**Real-vault verification:** all 7 chats from Eugene's actual vault (incl. the 127 KB 3-turn Lego chat whose every user turn embedded the full lawyer doc, and the 4-turn Vibe coding chat) restore showing only the typed questions — zero wrapper text across full-scroll sweeps; history previews clean.

**Continuation parity:** `loadTranscript` re-seeds the transcript's `mentioned` notes as pending mentions, so the next send re-attaches their current content exactly like a fresh chat (visible as chips above the composer). Tool results aren't replayable — the model re-runs tools — and that's the inherent limit.

**Per-turn citations (the Vibe coding complaint):**
- New transcripts save each assistant turn's `[n]: path` reference lines inside its `## Noto` section (`TranscriptTurn.sources`); the ChatAgent renumbering (bug 021, ported here) keeps inline numbers == 1..K == sources order, and `.finished` now reconciles the streamed blocks with the final renumbered answer so display == persisted == tappable mapping.
- Restore maps refs per turn (renumbering non-contiguous legacy numbers, dropping unmapped brackets); legacy turns with no refs fall back to frontmatter sources on the final answer, normalizing all citations to `[1]` when there's exactly one source; turns with no mapping at all render citations as plain text instead of dead-looking links.
- Citation links got wider tap targets (narrow no-break-space padding) — a bare digit was a ~7 pt target.
- **E2E on the real Vibe coding chat:** inline citation tap → `noto-cite://1 sources=1` (handler log) → chat dismisses → editor opens 国内终于有厂商要出了.md. The refs-bearing turn shows its own SOURCES rows (Neuralink/Things I wanna make).

**Investigation note:** ~40 "failed" citation taps mid-investigation were automation artifacts (history-list reordering after fixture edits put taps into the note editor; coordinate-scale confusion), disproven by adding an os_log to the tap handler and using it as ground truth. The log lines stay — they're the right diagnostic for this class of bug. One real edge found on the way: `[n]` followed by `:` in prose (e.g. "utilities [6, 9, 12]:") is intentionally not linkified (ref-definition guard) — acceptable.

**Tests:** NotoTests/ChatTranscriptRestorationTests 5 tests ×2 destinations (round-trip with per-turn sources, legacy ref renumbering, fallback shape) + NotoChat 38/38.

## Final Summary

**Root cause:** `persist()` saved the composed LLM messages (`AgentResult.messages`) — attachment text and plumbing included — instead of the displayed conversation; the heading-based transcript parser then also let embedded note headings bleed across turns and clobber the title.
**Fix:** persistence now maps the UI's display turns (`ChatSession.transcriptTurns(from:)`); the attachment wrapper is a shared constant with `ChatAgent.strippedComposedUserContent` unwrapping legacy files on load (chat restore, history previews); `parse()` only takes the pre-turn H1 as the title.
**Verification:** 7 new tests across both layers + simulator E2E with a seeded legacy transcript (screenshots in conversation). Formal visual audit deferred to merge.

## Investigation Log

### Attempt 1

**Hypothesis:** persistence uses composed LLM messages instead of display turns.
**Evidence:** `persist()` → `turns: history.filter { … }` where `history = result.messages`; `buildInitialMessages` embeds attachment text into the user message.
**Fix plan:** (1) persist display turns (typed user text; assistant text blocks, tool steps dropped); (2) share the attachment-wrapper marker as a constant and strip it from user turns when loading legacy transcripts; (3) keep the in-memory LLM `history` unchanged for live continuation.
