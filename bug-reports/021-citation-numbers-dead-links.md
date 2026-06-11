# Bug 021: Tapping inline citation numbers sometimes doesn't open the document

## Status: FIX DEPLOYED — unit-verified 2026-06-11; ships with the next device install

## Description

In AI chat, tapping an inline citation number (`[n]`) sometimes does nothing. It should always open the cited note.

## Steps to Reproduce

1. Ask the chat something that makes the model cite several sources, where the model's trailing reference list has **non-contiguous numbers** — e.g. it emits `[1]: A.md`, `[3]: B.md` (skipped `[2]`), or one reference's path fails validation against tool-surfaced files.
2. The answer renders citations `[1]`, `[3]`.
3. Tap `[3]`.
4. Nothing happens (or the wrong note opens).

## Root Cause

`ChatAgent.extractCitations` collapses the model's `[n]: path` reference definitions into a **positional array** (`numbered.keys.sorted().compactMap…`), but the renderer (`AIReplyView`) opens `sources[n-1]` for inline `[n]` (via `noto-cite://n` links). The `sources[n-1] == note for [n]` invariant only holds when the model's numbers are exactly contiguous `1..K` **and** every path resolves. When numbers are skipped or a path is dropped:

- inline `[n]` with `n > sources.count` → silent no-op (the tap guard rejects it), and
- inline numbers between gaps shift → they open the **wrong** note.

The UI also renders citation links during streaming before sources exist (taps no-op until the turn finishes) — that's inherent to streaming and acceptable.

## Success Criteria

### 1. Non-contiguous reference numbers still produce working citations
- [x] Unit test — `ChatAgentTests.nonContiguousCitationNumbersAreRenumbered` (inline `[1]`,`[3]` → `[1]`,`[2]`; sources aligned)

### 2. A dropped (unvalidated) reference removes its inline citation instead of leaving a dead link
- [x] Unit test — `droppedReferenceRemovesItsInlineCitation` (also strips the rejected `[n]: path` line from the answer)

### 3. Grouped citations renumber member-wise
- [x] Unit test — `groupedCitationsRenumberMemberWise` (`[1, 4]` → `[1, 2]`)

### 4. The common contiguous case is byte-for-byte unchanged
- [x] Unit test — `contiguousCitationsPassThroughUnchanged`

### 5. Markdown links/definitions are not mistaken for citations
- [x] Unit test — `renumberingLeavesMarkdownLinksAndDefinitionsAlone`

Suite: NotoChat 47/47 pass (excl. live suites); app builds clean.

## Final Summary

**Root cause:** `extractCitations` compacted the model's numbered references into a positional array while the renderer opens `sources[n-1]` for inline `[n]` — any skipped or validation-dropped reference number made later citations dead (out of range) or wrong-target.
**Fix:** renumber inline citations to the compacted `1..K` order (grouped citations member-wise), remove inline citations whose reference was dropped, and strip rejected reference lines from the answer. Renderer untouched — its `sources[n-1]` contract now actually holds.
**Residual:** the no-definitions fallback (sources = attached+read, sorted) still can't guarantee inline-number mapping; the system prompt demands matching `[n]:` lines, so this path is rare. During streaming, citation taps no-op until the turn finishes (pre-existing, inherent).

## Investigation Log

### Attempt 1

**Hypothesis:** positional `sources` array vs model-numbered inline citations mismatch on non-contiguous/dropped references.
**Evidence:** `extractCitations` compacts numbered defs into an array; `AIReplyView` maps `noto-cite://n` → `sources[n-1]`; guard `n <= sources.count` silently no-ops. Any skipped/dropped number breaks the mapping.
**Fix:** after validating references, renumber the inline citations in the answer text to the compacted order (`[1]…[K]`, matching `sources`), and remove inline citations whose reference was dropped (dead links otherwise). Grouped citations (`[1, 3]`) are renumbered member-wise.
