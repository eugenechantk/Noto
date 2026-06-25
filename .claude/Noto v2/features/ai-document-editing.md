# Feature: AI Document Editing (Edit Suggestions in Chat)

**Status:** Implemented & verified 2026-06-25 — live end-to-end PASS (Product tier)
**Author:** Claude (chief of staff)
**Date:** 2026-06-24
**Tier:** Product

---

## 1. Summary

Give the Noto AI chat the ability to **propose edits to a note**, surfaced as
**edit-suggestion cards** in the conversation that the user reviews and
accepts/rejects. Three edit types are supported:

1. **Addition** — insert new content (anchored relative to existing text, or at
   the start/end of the document).
2. **Edit** — replace an existing span of text with new text.
3. **Deletion** — remove an existing span of text.

Edits are **proposed, never auto-applied.** The human stays in the loop: the AI
calls a tool to propose a batch of edits against a target note; the chat renders
a diff card; the user accepts or rejects (per-edit and/or whole-card). On
accept, the change is applied to the note and reflected live in an open editor.

This requires three deliverables, matching the user's framing:

1. A **package** exposing APIs to edit a document programmatically.
2. The **UI** for edit suggestions in the AI chat.
3. **Wiring** the package and UI together through the chat agent loop.

---

## 2. Goals / Non-Goals

### Goals

- A pure, independently-testable package that, given a document's current text
  and a set of proposed edits, **resolves anchors to ranges, validates them, and
  produces both a new document and a renderable diff.**
- An LLM tool (`propose_edits`) in NotoChat that lets the model author edits
  using **text-based anchors** (not character offsets — LLMs are unreliable with
  offsets), validates them against the live note, and surfaces them to the UI.
- Edit-suggestion cards in the chat that show additions/edits/deletions as a
  clear diff, with accept/reject controls.
- Safe application: re-validate at accept time, apply through the editor session
  when the note is open (live update + autosave + same-process sync), or through
  the vault store when it is closed.

### Non-Goals (this iteration)

- No autonomous/agentic auto-apply without user confirmation.
- No multi-note batch edits in a single card (target is **one note per
  proposal**; the active note by default). Multiple proposals across a turn are
  allowed but each card targets one note.
- No structural/AST-aware editing (move section, reorder list). Edits are
  text-anchored. Heading/section awareness is a possible later refinement.
- No 3-way conflict merge. If the anchor no longer matches at accept time, the
  edit is marked stale and skipped (not force-applied).
- iPad/macOS chat layouts (chat itself is iOS-only today). The package + tool
  are platform-neutral; the card UI follows the iOS chat sheet.

---

## 3. The Three Edit Types (precise semantics)

**Terminology — operation vs. edit block (important).**

- An **operation** is one of the three primitives below (addition / edit /
  deletion).
- An **edit block** (a diff *hunk*) is the unit the user reviews and
  accepts/rejects: **one contiguous spot in the document.** A block may contain
  more than one operation as long as they touch the *same* spot.
  - Deleting a line and adding a replacement line at the **same** spot is **one
    edit block** (two operations, one spot).
  - Deleting a line at line 9, and deleting+adding at line 12, is **two edit
    blocks** (three operations, two separate spots).
- A single `propose_edits` call therefore yields **N edit blocks**, one per
  distinct spot. Each block is its **own minimal diff card** with its own
  Accept / Dismiss. The blocks are independent — accepting one does not accept
  the others. (See §3a for how operations are grouped into blocks.)

All anchors are **exact text matches** against the current note body (frontmatter
excluded). Whitespace-trimmed matching is the MVP; whitespace-tolerant matching
is a noted refinement.

| Type | Author specifies | Resolution rule | Result |
|------|------------------|-----------------|--------|
| **Addition** | `content` + an `anchor` (`position` ∈ {`after`, `before`, `startOfDocument`, `endOfDocument`} and, for after/before, an `anchorText`) | Find `anchorText` (must match exactly once). Insert `content` immediately after/before it. start/end need no anchorText. | New text inserted; diff shows added lines (green). |
| **Edit** | `target` (existing text) + `replacement` | Find `target` (exactly once). Replace it with `replacement`. | Span replaced; diff shows old (red) → new (green). |
| **Deletion** | `target` (existing text) | Find `target` (exactly once). Remove it (and a trailing newline if it leaves a blank line). | Span removed; diff shows deleted lines (red). |

**Ambiguity / failure handling (core robustness rule):**

- **0 matches** → edit is `unresolved(.notFound)`. Surfaced to the model as a
  failure so it can retry with more context; not shown as an actionable card.
- **>1 matches** → edit is `unresolved(.ambiguous)`. The model must supply a
  longer, unique `target`/`anchorText`. Not actionable.
- Only **exactly-1-match** edits become actionable suggestion cards.

This "must match uniquely" contract is the same model as Claude's own
`str_replace` editing tool and is what makes text-anchored edits reliable.

### 3a. Grouping operations into edit blocks (hunks)

After every operation is resolved to a range, `NotoEdit` coalesces them into
blocks exactly like a `git`/GitHub diff coalesces hunks:

- Sort resolved operations by range.
- Operations whose ranges are **equal, adjacent, or overlapping** (or separated
  only by whitespace/one short line of context) merge into **one block**.
- Operations on **non-adjacent** regions stay in **separate blocks**.

This is what makes "delete + re-add at the same line" render as one block while
"delete at line 9" and "edit at line 12" render as two. The model does not have
to declare block boundaries — it just proposes operations, and grouping is
deterministic. (An `edit` operation is already a same-spot replace, so it is
always its own single block unless an adjacent operation merges in.)

---

## 4. Component 1 — The Package (`NotoEdit`)

### Why a new package

Per the project's "packages for all non-UI logic" principle and the
new-package rule ("distinct responsibility with its own testable surface"):
edit modeling + anchor resolution + diff generation is pure string logic,
distinct from `NotoVault`'s file CRUD and from `NotoChat`'s agent loop. It must
be testable via `swift test` with zero UI. → **New package `Packages/NotoEdit`.**

It depends on nothing (or only Foundation). `NotoChat` and the app target both
import it.

### Public API (shape, not final code)

```swift
// What the model authors (decoded from tool arguments).
public enum ProposedEdit: Equatable, Sendable, Codable {
    case addition(anchor: Anchor, content: String)
    case edit(target: String, replacement: String)
    case deletion(target: String)
}

public enum Anchor: Equatable, Sendable, Codable {
    case after(String)        // insert after this exact text
    case before(String)       // insert before this exact text
    case startOfDocument
    case endOfDocument
}

// One resolved operation (primitive) against a concrete document.
public struct ResolvedOp: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: EditKind            // addition | edit | deletion
    public let range: NSRange            // resolved span in the body
    public let replacement: String       // "" for deletion
    public let status: ResolutionStatus  // resolved | unresolved(reason)
}

// An EDIT BLOCK = one contiguous spot = the user-facing review/accept unit.
// Contains one or more same-spot operations coalesced into a single hunk.
public struct EditBlock: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let ops: [ResolvedOp]         // 1+ operations at this spot
    public let span: NSRange             // union range covered by the block
    public let preview: DiffPreview      // context lines + −/+ rows + trailing context
    public let locationHint: String?     // e.g. nearest heading, for a quiet label
}

// A renderable hunk with expandable context (NO line numbers). The change rows
// plus a few UNCHANGED context lines above/below (default ~2-3, clamped to note
// bounds). The view can request MORE context on demand (expand up / down).
public struct DiffPreview: Equatable, Sendable {
    public let contextBefore: [DiffLine]   // unchanged lines above (dimmed)
    public let rows: [DiffLine]            // the changed −/+ lines
    public let contextAfter: [DiffLine]    // unchanged lines below (dimmed)
    public let canExpandUp: Bool           // more lines exist above the shown window
    public let canExpandDown: Bool         // more lines exist below
}
public struct DiffLine: Equatable, Sendable {
    public enum Kind { case context, removed, added }   // context dimmed / − red / + green
    public let kind: Kind
    public let text: String
}

// EditApplier can re-render a block's preview with a larger context radius when
// the user taps "expand up/down":
//   static func preview(for block: EditBlock, in body: String,
//                       contextBefore: Int, contextAfter: Int) -> DiffPreview

public enum ResolutionStatus: Equatable, Sendable {
    case resolved
    case unresolved(Reason)   // .notFound | .ambiguous(count:)
}

public struct EditApplier {
    // Resolve operations, then coalesce contiguous ones into edit blocks (§3a).
    // Pure; no I/O. Unresolved ops are reported but not placed in actionable blocks.
    public static func plan(_ edits: [ProposedEdit], in body: String)
        -> (blocks: [EditBlock], unresolved: [ResolvedOp])

    // Apply one or more ACCEPTED blocks to the body, producing the new body.
    // Applies blocks sorted by span descending so earlier ranges stay valid.
    // Throws if any span is stale (overlaps / out of bounds).
    public static func apply(_ blocks: [EditBlock], to body: String) throws -> String
}
```

Each `EditBlock` is atomic: accepting it applies *all* its operations together
(so a same-spot delete+add applies as one replace); the block is the smallest
thing the user can accept or reject.

### Responsibilities

- **Resolve:** map each operation to an `NSRange` in the body, set status, build
  the diff preview (context lines + the −/+ rows for that hunk).
- **Group (§3a):** coalesce contiguous/overlapping operations into `EditBlock`s
  (hunks). One block per distinct spot.
- **Apply:** given accepted block(s), produce the new body. Apply blocks **sorted
  by span descending** so applying one doesn't shift the others' offsets. Detect
  overlapping spans and reject.
- **Re-resolve:** because the user may edit the note between proposal and
  acceptance, the wiring layer re-runs `plan` at accept time against the
  then-current body. The package makes this cheap and pure.

### Tests (`swift test`)

- Each edit type: happy path (1 match), not-found (0), ambiguous (>1).
- Addition at start, end, after-anchor, before-anchor.
- **Grouping:** same-spot delete+add coalesces to **one** block; two distant ops
  produce **two** blocks; adjacent ops merge; the line-9 / line-12 example from
  §3 yields exactly two blocks.
- Accepting **one** block of several applies only that spot; the others remain
  proposed.
- Multiple accepted blocks applied together (offset correctness).
- Overlapping spans rejected.
- Empty document / empty body boundary (matches the project's "test the
  empty-content boundary" rule).
- Trailing-newline cleanup on deletion.
- **Context lines:** preview includes N unchanged lines before/after; clamped
  correctly at the start/end of the note (fewer lines, no crash).
- Unicode / multi-byte (NSRange vs String.Index correctness).

---

## 5. Component 2 — The Tool (`NotoChat`)

### New tool: `propose_edits`

Added to `VaultTools` alongside `grep`/`read`/`list`/`search`. **It does not
write to disk.** It resolves the proposed edits against the current note and
returns a structured result that (a) tells the model whether each edit resolved,
and (b) surfaces the actionable edits to the UI.

**Schema (JSON given to the LLM):**

```jsonc
{
  "name": "propose_edits",
  "description": "Propose edits to a note for the user to review and accept. Edits are NOT applied automatically.",
  "parameters": {
    "path": "vault-relative path of the note to edit (defaults to the note in context)",
    "edits": [
      {
        "type": "addition" | "edit" | "deletion",
        // addition:
        "position": "after" | "before" | "start_of_document" | "end_of_document",
        "anchor_text": "exact existing text to anchor after/before (required for after/before)",
        "content": "text to insert",
        // edit:
        "target": "exact existing text to replace",
        "replacement": "new text",
        // deletion:
        "target": "exact existing text to remove"
      }
    ],
    "summary": "one-line, user-facing description of the change set"
  }
}
```

**Execution flow inside the tool:**

1. Resolve `path` (default = the in-context note). Read its current body.
2. `EditApplier.resolve(edits, in: body)`.
3. `EditApplier.plan(edits, in: body)` → `[EditBlock]` + any unresolved ops.
4. Build a `ToolRunResult` whose **`output`** (returned to the LLM) reports per
   operation: resolved / not-found / ambiguous, and how many blocks resulted, so
   the model can fix and re-propose unresolved ones in the next round.
5. Surface the resulting **edit blocks** to the UI. This needs a new carrier on
   the event/result path (see §6) — e.g. extend `ToolRunResult` with
   `editBlocks: [EditBlock]` and add an `AgentEvent.editBlocks(path:, [EditBlock])`
   (or carry it on `toolCallFinished`).

The tool deliberately stops at "proposed." Acceptance is a **post-turn,
user-driven** action handled by the app, outside the agent loop.

### System-prompt additions

Tell the model: it can propose edits with `propose_edits`; anchors must be
**unique exact quotes** from the note; prefer the smallest unique anchor; never
claim an edit was applied (the user must accept); if an edit comes back
ambiguous/not-found, re-quote with more surrounding text.

---

## 6. Component 3 — UI + Wiring

### Data model (ChatSession)

Each **edit block is its own chat block**, so multiple spots render as multiple
stacked minimal diff cards, interleaved with text/tool steps like everything
else in an AI turn:

```swift
enum Block {
    case text(id: UUID, String)
    case tool(ToolStep)
    case editBlock(EditBlockState)   // NEW — ONE per spot/hunk
}

struct EditBlockState: Identifiable, Equatable {
    let id: UUID
    var targetPath: String         // which note — ALWAYS shown in the block header
    var targetTitle: String        // note title; show folder breadcrumb when nested
    var locationHint: String?       // quiet label, e.g. nearest heading within the note
    var diff: DiffPreview           // context lines + −/+ rows + trailing context
    var status: BlockStatus         // .proposed | .applied | .dismissed | .stale
}
```

`ChatSession` reduces the new `AgentEvent.editBlocks` into one `.editBlock` per
returned block, the same way it currently reduces tool events. There is no
parent "proposal card" wrapping all spots — each spot is its own contained card
and is accepted or dismissed independently.

### The Edit Block card (`EditBlockView`) — one contained card per spot

Lives in `Noto/Views/Chat/`, styled with `NotoChatTokens`. **One block per edit
spot.** Several edits in a turn → several stacked. **Reuse the existing
tool-step styling** (`ToolStepView` — the grep/read/list blocks): the same
subtle left rule, monochrome glyph + quiet/muted header, tight type — so an edit
suggestion reads as another quiet step in the interleaved AI reply. More
minimal than a bordered card; **no line-number gutter**.

- **Anatomy (tool-step styling):**
  - **Tool-name header line (always shown):** like every other tool, the first
    line is the **tool name** + its target, in the tool-step label style:
    **`Suggested Edits ・ [doc glyph] [file name]`** (folder breadcrumb when
    nested, e.g. `Projects › Alpha`). This mirrors `Searched … · N notes`,
    `Read …`, `Listed …` — so an edit reads as a named tool step. Never leave the
    user guessing which file an edit touches. Optional `locationHint`.
  - **Diff body — context, no line numbers:** dimmed unchanged **context lines**
    around the changed rows; changed rows red `−` / green `+`, subtly tinted. A
    same-spot replace shows its `−` line(s) then `+` line(s). No `@@`, no gutter.
  - **Expand toggles:** small `⌃` / `⌄` chevrons at the top/bottom of the hunk to
    pull in more context on demand (shown only when `canExpandUp`/`canExpandDown`).
  - **Footer controls (per block):** quiet/minimal to match the tool-step block
    — **Accept** as a light text/ghost action in orange ink (`NotoChatTokens.accent`),
    NOT a solid filled orange pill, paired with an equally quiet secondary
    **Dismiss**. Small, low-emphasis; orange ink alone signals the primary action.
  - **Icon alignment:** the doc glyph, the `−`/`+` markers, the expand chevrons,
    and the footer control icons must all sit on a **consistent left alignment
    grid / shared baseline** — no ragged icon edges. This is an explicit
    requirement.
- **Terminal states (designed + visible):**
  - **Applied** → quiet one-line `✓ Applied · <file>`.
  - **Dismissed** → visibly distinct `✕ Dismissed · <file>` (muted, struck file
    name) so a declined suggestion is obviously declined, not vanished. Own
    artboard.
  - **Stale** → `No longer applies`.

Design language: dark (`#0E1116`), orange accent (`#FF6A2E`), additions green /
deletions red, dimmed context lines, **tool-step (left-rule) styling**, aligned
icons, note-native (no chat bubbles), consistent with the locked-in AI Chat
design.

### Apply mechanism (wiring accept → disk)

On **Accept of a block**, the app layer:

1. **Re-resolve** that block against the note's *current* body (it may have
   changed since the proposal). If its operations no longer resolve uniquely →
   mark the block `stale` and do not apply. (Safety rule: never force-apply a
   stale anchor.) Other blocks are unaffected.
2. `EditApplier.apply([block], to: body)` → new body.
3. Persist:
   - **Note is open in the editor** (the common case — chat auto-attaches the
     active note): route through `NoteEditorSession`. Add a method
     `applyEdits(_ blocks: [EditBlock])` that mutates `content` by range,
     updates `latestEditorText`, persists (`persistEditorText(force:)`), and
     thereby triggers the existing **`NoteSyncCenter`** broadcast so any other
     open window updates too. This reuses the same path as the existing
     `applyExternalContentEdit(_:)` but range-based instead of whole-document.
   - **Note is closed:** write through `MarkdownNoteStore` / `VaultManager`
     (`updateNote(id:content:)`), bumping `modified`. The editor, if later
     opened, reads fresh from disk; if open elsewhere, `VaultFileWatcher` picks
     it up.
4. Update that block to `applied`. (Each block is independent — one block can be
   applied while a sibling is dismissed or left pending.)

### End-to-end data flow

```
User: "tighten the intro and add a TODO at the end"
        │
ChatAgent loop → LLM → tool_call: propose_edits{ path, edits:[edit, addition], summary }
        │
VaultTools.propose_edits → read body → EditApplier.resolve
        │   ├─ output → LLM: "2 edits, both resolved"  (loop continues/finishes)
        │   └─ editProposal → AgentEvent.editProposal
        │
ChatSession → append .editProposal block → EditSuggestionCardView (diff)
        │
User taps Accept
        │
App: re-resolve vs current body → EditApplier.apply → new body
        │
NoteEditorSession.applyEdits (open)  OR  VaultManager.updateNote (closed)
        │
NoteSyncCenter broadcast → live editor updates → card → "Applied"
```

---

## 7. Edge Cases

- **Target note not open / not the active note:** tool still resolves by path;
  apply goes through the vault store.
- **User edits note between propose and accept:** re-resolve; stale edits
  skipped, card reflects partial/stale.
- **Overlapping edits in one batch:** package rejects overlaps; UI disables
  accepting a conflicting subset.
- **Empty note / addition into empty body:** start/end-of-document anchors work;
  covered by tests.
- **iCloud not-yet-downloaded note:** reuse `read`'s existing coordinated-read /
  download-on-demand path before resolving.
- **Frontmatter safety:** edits operate on **body only**; the applier never
  touches the YAML frontmatter block. Persistence re-serializes frontmatter via
  the existing write path.
- **Multi-byte / emoji in anchors:** NSRange computed via NSString to stay
  consistent with the editor's TextKit ranges.

---

## 8. Testing Plan

- **Package (`swift test` in `Packages/NotoEdit`):** the resolution/apply/diff
  matrix in §4.
- **NotoChat:** `propose_edits` argument parsing; resolved vs unresolved output
  string; proposal surfaced on the event path. Reuse the existing
  `LLMClienting` mock to drive a fake tool call.
- **App (`test_sim`):** `NoteEditorSession.applyEdits` range application +
  persistence + sync broadcast; re-resolve-on-accept staleness.
- **Simulator visual validation (required for UI):** seed vault, open chat,
  drive a proposal, screenshot a block in proposed / applied / dismissed / stale
  states, **plus a multi-spot turn rendering several stacked minimal blocks**.
  Validate diff colors, per-block accept/dismiss, and that the open editor
  reflects an applied block while a sibling stays pending.

---

## 9. Decisions

1. **Accept granularity — DECIDED: per edit block (spot).** The review/accept
   unit is the **edit block** — one contiguous spot in the document (§3, §3a).
   Each block is its own minimal diff card with its own Accept / Dismiss; several
   spots in a turn render as several stacked blocks, accepted independently.
   Operations within one block (e.g. a same-spot delete+add) apply together as a
   unit — that is still one block, one Accept. (No per-operation buttons; the
   block is the atom.)
2. **Edit scope — DECIDED: any note by path, default in-context.** The AI may
   target any note in the vault via `path`; when omitted it defaults to the
   note attached to the chat. The card header always names the target note so an
   edit to a non-attached note is never silent.
3. **Package name — DECIDED: `NotoEdit`** — distinct testable surface, keeps
   `NotoVault` focused on file CRUD.
4. **Anchor matching strictness — DECIDED: exact (trimmed) match for MVP**; add
   whitespace tolerance only if the model trips on it during testing.

---

## 10. Deliverable Checklist

- [x] `Packages/NotoEdit` — models, `EditApplier` (resolve + group into blocks +
      apply + expand-radius preview), `LineDiff`. **24 tests pass** (`swift test`).
- [x] `NotoChat` — `propose_edits` tool + schema + system-prompt + `EditProposal`
      carrier on `ToolRunResult` + `AgentEvent.editProposal`; `@_exported import
      NotoEdit` so the app gets the types without a new product. **62 tests pass.**
- [x] `ChatSession` — `.editBlock` block (one per spot) + `.editProposal`
      reduction + per-block `acceptEdit` / `dismissEdit` / `expandEdit`, with
      re-resolution against the current body and `ActiveEditorBridge` vs file IO.
- [x] `EditBlockView` — tool-step-styled card: `Suggested Edits ・ [doc] <file>`
      header, context + −/+ rows, expand chevrons, quiet Dismiss / orange-ink
      Accept, ✓ Applied / ✕ Dismissed / stale terminal states. + SwiftUI preview.
- [x] Open-editor apply via `NoteEditorSession.applyExternalContentEdit` (reused,
      gives live update + same-process sync); closed-note apply via file IO.
- [x] App-target integration tests (`NotoTests/ChatEditSuggestionTests`): accept
      writes to disk (frontmatter preserved), dismiss is a no-op, accept goes
      stale when the anchor is gone, multi-spot → independent cards.

## 11. Test Mapping

- **NotoEdit (`swift test`, 24):** resolution happy/notFound/ambiguous/empty for
  each type; additions start/end/after/before; grouping (same-spot→1, distant→2,
  adjacent merge); apply single/multi/offset/overlap/stale; deletion newline
  cleanup; context clamping + expand; unicode; LineDiff add/remove/replace.
- **NotoChat (`swift test`, +6):** parse+plan+frontmatter-strip; unresolved
  reporting; default-path; missing-path error; tool advertised; agent loop
  surfaces `.editProposal` (and not a tool-step row).
- **App (`flowdeck test`, NotoTests/ChatEditSuggestionTests):** accept→disk,
  dismiss no-op, stale-on-changed-body, multi-spot independent apply.

## 12. Verification & Residual Risks

- **Live-AI end-to-end — VERIFIED (PASS) 2026-06-25.** Independently driven by
  `ios_visual_evidence_auditor` on the running app (bundled OpenRouter key → chat
  works live). "Add 'Eggs' to my shopping list" → model called `propose_edits` →
  `Suggested Edits ・ 📄 Shopping List` card → **Accept** → file changed on disk.
  Raw `od -c` bytes confirm `- Eggs` landed on its **own line** (real `0x0A`, no
  literal `\n`). Evidence: `.codex/evidence/20260625-013000-ios-visual-audit/`.
- **`modified` is a property of the file write — VERIFIED.** Programmatic edits
  now write via file IO and stamp `modified` at the write
  (`NotoVault.NoteFrontmatter.stampingModified`), independent of any editor.
  Live run bumped `modified` `2026-03-15` → `2026-06-25T04:30:44Z`; `id`/`created`
  preserved. Built for the coming wave of programmatic edits.
- **Open editor live sync — VERIFIED.** Accepting an edit publishes a
  `NoteSyncCenter` snapshot; the note open in the editor updated live (no reopen)
  in the audit. The `ActiveEditorBridge` was removed — both open and closed notes
  go through the same file-IO + sync path.
- **Model output normalization:** models sometimes emit a literal `\n` (escaped)
  in edit text; `VaultTools.normalizeEscapes` converts `\n`/`\t` to real
  characters so additions land as real lines. Covered by a unit test; LLM
  anchor-quality variability otherwise remains inherent.
- Dismiss / stale / multi-spot terminal states are covered by the app-target
  tests (not separately screenshot-driven live).
- iPad/macOS chat presents from the list with no `ActiveEditorBridge`, so an
  accepted edit to the open detail note lands via file IO and the detail editor
  reflects it through `VaultFileWatcher` (not the in-process sync path).
- Expand toggles re-read + re-plan on each tap; on a note edited since the
  proposal the anchor may be gone and expand simply no-ops (safe).
- Closed-note file write keeps the existing `updated:` frontmatter timestamp
  (not bumped). Minor; can refine.
