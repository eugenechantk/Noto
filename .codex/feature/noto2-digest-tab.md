# Feature: Noto 2 Digest tab

## User Story

As someone who fires thoughts into Noto 2's Capture card all day, I want a **Digest**
tab that walks me through the `inbox/` backlog one capture at a time and lets me
decide, per capture, where it goes — so the inbox reaches zero instead of becoming
a write-only pile.

## User Flow

1. Open the **Digest** tab (4th tab, `tray.full`). It loads every due capture in
   `inbox/`, oldest first, and shows the count ("3 to process").
2. The oldest capture sits on a card, framed by a **plus target above** and a
   **trash target below**. Long captures scroll inside the card. A second card
   peeks from behind whenever there is a next one; on the last capture there is no
   stack, so the final card reads as final.
3. Four directions, four outcomes. The two axes speak different visual languages on
   purpose — a horizontal swipe is a decision the swipe makes by itself, so the
   *card* answers; a vertical swipe is aimed at something, so a *target* answers:
   - **← Snooze** — the card floods **yellow** with a clock. On release it flies
     left and the note gets `snoozed_until: <now + 7 days>`, dropping out of the
     digest until that date passes.
   - **→ Add to** — the card floods **blue**. Opens the note picker; the capture is
     appended to whichever note you choose.
   - **↑ Create** — the **green plus** above fills in and scales up as the card
     travels toward it. Opens the title + folder form.
   - **↓ Discard** — the **red trash** below fills in. On release the capture is
     deleted, with **Undo** in the status line for six seconds.
   The card slides *under* both targets, so the highlight is visible exactly when it
   matters. Only the dominant axis signals, so a drag right never half-lights the
   trash. `Add to` and `Create` also have buttons under the card, since both need
   more input anyway; snooze and discard are gesture-only.
4. After any successful action the card flies off, the next card rises, and the count
   drops. When the last card is processed, an empty state says the inbox is clear.
5. Any write failure leaves the inbox file untouched, returns the card, and shows an
   error.

## Success Criteria

| # | Criterion |
|---|---|
| SC1 | The digest lists exactly the `.md` files directly inside `inbox/`, excluding any whose frontmatter `snoozed_until` parses to a date in the future, ordered oldest capture first. |
| SC2 | Snooze rewrites only the frontmatter: `snoozed_until` is set to (now + 7 days) in ISO-8601, every other frontmatter key and the entire body survive byte-for-byte, and a second snooze overwrites the existing key rather than appending a duplicate. |
| SC3 | Add-to appends the capture body to the end of the target note's body, separated by exactly one blank line, refreshes the target's `updated:` stamp, and deletes the inbox file **only after** the target write succeeds. |
| SC4 | Create writes `<folder>/<Title>.md` with fresh frontmatter (`id`, `created`, `updated`), a `# <Title>` heading, then the capture body; an existing filename resolves to `Title(2).md`; the inbox file is deleted only after the new file write succeeds. |
| SC5 | Discard deletes the inbox file and performs no other write, and the deletion can be undone for as long as its banner is on screen — Undo restores the file byte-for-byte. |
| SC10 | Each of the four drag directions resolves to its own action, diagonals resolve to the dominant axis, short drags spring back, and only the dominant axis lights its signal. |
| SC11 | A card behind the current one is visible whenever another capture is queued, and absent on the last one. |
| SC6 | If any write in SC3/SC4 fails, the inbox file still exists afterwards and the action reports failure. |
| SC7 | A capture whose file has no frontmatter, or an unparseable `snoozed_until`, is treated as due rather than crashing or being hidden. |
| SC8 | The Digest tab renders the card stack, the remaining count, the four actions, and an empty state; swipe left snoozes and swipe right opens the file sheet. |
| SC9 | Selecting the Digest tab starts the deferred vault workspace (the tab needs the vault), and Capture-first cold launch is unaffected. |

## Test Strategy

SC1–SC7 are pure filesystem + markdown logic and live in a new `NotoDigest` package,
proven with Swift Testing against temp-directory vaults with real file I/O (no mocks
except an injected clock and an injected failing filesystem for SC6). SC8 is UI and is
proven by the simulator visual evidence audit. SC9 is app-target policy logic tested in
`Noto2Tests`.

## Tests

### Package Unit — `Packages/NotoDigest/Tests/NotoDigestTests/`
- `DigestMarkdownTests.swift`
  - body/heading joining rules — verifies SC3, SC4
- `DigestInboxReaderTests.swift`
  - enumeration, snooze filtering, ordering, malformed frontmatter — verifies SC1, SC7
- `DigestFilingTests.swift`
  - snooze / add-to / create / discard against a real temp vault, plus failure paths — verifies SC2–SC6

### Package Unit — `Packages/NotoVault/Tests/NotoVaultTests/`
- `NoteFrontmatterTests.swift`
  - generic frontmatter key read/write used by snooze — verifies SC2

### App Unit — `Noto2Tests/`
- `DigestModelTests.swift` — queue advance/empty-state logic — verifies SC8's state machine
- `Noto2StartupTests.swift` — digest requires the workspace — verifies SC9

## Implementation Details

**Frontmatter contract for a snoozed capture** — only one key is added:

```yaml
---
id: …
created: …
updated: …
type: note
status: inbox
snoozed_until: 2026-09-08T12:00:00Z
---
```

`status` stays `inbox` so gbrain's cycle keeps typing it as a note; the digest alone
honours `snoozed_until`.

**Disposition** — filing (Add to / Create) and Discard both **delete** the inbox file.
Chosen over archiving so the text does not exist twice in search. The delete is ordered
strictly after the destination write returns success.

**Layering**
- `Packages/NotoDigest` (new, depends on `NotoVault`) — entries, inbox reading, the four
  filing actions. Non-UI, platform-neutral, `swift test`-able with no simulator.
- `Noto2/Digest/` — `DigestScreen` (card stack), `DigestModel` (`@Observable` queue +
  action dispatch), `DigestFileSheet` (note picker / create form).
- `NoteFrontmatter` in `NotoVault` grows generic `value(for:)` / `setting(_:to:)` /
  `removing(_:)` helpers rather than the digest re-parsing YAML.

**Gestures** — deliberately *not* identical to Capture. Capture's left = discard;
Digest's left = snooze, because in a triage pass "later" is the common left-hand
outcome and an accidental left swipe must never delete. All four directions commit,
so discard moved from a button to ↓, and the confirmation dialog was dropped: an
alert after the card has already flown off reads as a bug, and the red target is the
warning. **Undo** replaces it — `DigestFiling.discard` returns the file's exact bytes
and `restore` writes them back, held for as long as the banner is up.

`DigestSwipeResolver` keeps the geometry — thresholds, dominant-axis resolution,
signal strength — out of the view, because gesture tuning is exactly what regresses
invisibly: a threshold tweak that makes "snooze" occasionally delete would never show
up in a screenshot. `DigestSwipeTests` covers it.

**Target z-order** — the plus and trash are drawn *above* the card (`.zIndex(1)`).
Without it the card slides over the target and hides the highlight at the moment it
matters most; caught in the simulator, not by tests.

**Note picker exclusion** — the picker is fed by `VaultController.pageMentions`, which
returns *every* note in the vault including the captures in `inbox/`. `DigestNotePicker`
filters those out; without it you could pick the very capture on the card and append a note
to itself. Found during simulator verification, not by the tests — see Bugs.

**Timestamp key** — the vault carries two conventions: `VaultMarkdown.makeFrontmatter` (and
so every editor-created note) writes `updated:`, while the main Noto app's AI/agent paths and
older notes write `modified:`. Add-to therefore uses
`NoteFrontmatter.stampingExistingTimestamps`, which refreshes whichever of the two keys the
target already has (both, if it has both) and invents neither. An earlier version used
`VaultMarkdown.updateTimestamp`, which only knows `updated:` — it silently left
`Meeting Notes.md` advertising a March write time after a September append. Create still
writes `updated:` via `makeFrontmatter`, matching `NoteRepository.createNote`.

## Residual Risks

Proven by Swift tests: everything that lands on disk — enumeration, snooze filtering and
ordering, the four filing actions, filename collisions, and the write-before-delete ordering
on both failure paths. Proven by simulator verification: all four actions end to end, the
sheet chrome, the folder and note pickers, the confirmation dialog, and the empty state.

An independent `ios_visual_evidence_auditor` pass returned **PASS on all nine criteria**, with
recordings of the snooze swipe, the create flow, and the discard confirm, plus on-disk diffs —
evidence in `.codex/evidence/20260901-211025-ios-visual-audit/`. It found two defects outside
the criteria list (both now fixed and re-verified — see Bugs).

Not proven:

- **Gesture tuning.** The commit thresholds and fly-off durations are copied from
  `CaptureScreen`; only the left-swipe (snooze) path was exercised by hand. Right-swipe-to-open
  the file sheet was verified via the buttons, not the swipe.
- **`Title(2).md` collision resolution and the SC6 write-failure rollback** are proven by
  package tests but never seen in the running app.
- **Large inboxes.** `dueEntries` reads and parses every file in `inbox/` on each load, on a
  detached task. Fine for tens of captures; a vault with thousands would want a bounded read
  (`BoundedFileRead` already exists in `NotoVault`) or incremental loading.
- **The dataless-iCloud card.** `isAvailable == false` is unit-tested through an injected
  filesystem, but the "Downloading from iCloud…" card has never been seen on a real evicted
  file, and nothing re-loads the queue when the download lands — the user has to pull to
  refresh. See `[[project_vault_is_icloud_dataless]]`.
- **Concurrent edits.** If Noto (app 1) has the same capture open in its editor while the
  digest files it, the editor's autosave could recreate the file after the delete. Both apps
  over one vault is an existing hazard, not new to the digest, but the digest makes it easier
  to hit.

## Bugs

**Fixed during verification (both found in the simulator, not by tests):**

1. **Container accessibility identifiers swallowed the children.** A bare
   `.accessibilityIdentifier` on the card `ZStack` and the action `HStack` collapsed each into
   a single element, so `digestAddToButton` / `digestCreateButton` / `digestDiscardButton`
   did not exist in the accessibility tree and could not be tapped by automation — or
   distinguished by VoiceOver. Fixed with `.accessibilityElement(children: .contain)`.
2. **The "Add to" picker listed inbox captures.** Including the capture on the card, so you
   could file a note into itself. Fixed by `DigestNotePicker.filingCandidates`, now covered by
   `DigestNotePickerTests`.
3. **Un-clearable seeded title.** The Create sheet pre-fills the title from the capture's
   first line (up to 60 chars); clearing it meant holding backspace. Added an inline ✕ clear
   button (`digestCreateTitleClearButton`).

**Found by the independent visual audit, fixed and re-verified:**

4. **The queue never reloaded after its first load** — the tab's whole reason to exist is that
   Capture writes `inbox/` and Digest reads it, but `.task { if !model.hasLoaded … }` ran once
   per view lifetime, and the `.refreshable` was attached to a `GeometryReader`/`VStack` with no
   scroll ancestor, so pull-to-refresh was inert. The auditor wrote a capture to `inbox/` with
   "Inbox clear" on screen and it stayed clear until relaunch. Now `.task(id: appearCount)` with
   an `onAppear` bump, plus a `scenePhase == .active` refresh (captures also arrive from the Lock
   Screen widget and iCloud while backgrounded); `refresh()` no-ops while an action is in flight
   so a reload can't swap the card out mid-file. Covered by
   `refreshPicksUpCapturesWrittenAfterTheFirstLoad` and `refreshIsSkippedWhileAnActionIsInFlight`;
   re-verified in the simulator (wrote to `inbox/` while "Inbox clear" showed → tab away → back →
   "1 to process").
5. **Add-to left `modified:` stale** — see Implementation Details above. Now
   `NoteFrontmatter.stampingExistingTimestamps`, covered by five new `NotoVault` cases and
   `appendRefreshesAModifiedStamp`; re-verified live (`Meeting Notes.md` went
   `modified: 2026-03-15T09:00:00Z` → `2026-09-01T13:26:55Z`, `created:` untouched).

**Also fixed from the audit's smaller observations:**

6. **Discard confirmation had no visible cancel.** `confirmationDialog` rendered as a popover
   anchored to the trash button, dropping the "Keep" button and floating the destructive action
   over the tab bar. Switched to `.alert`, which always shows both choices.
7. **Suggested title kept sentence punctuation**, producing filenames like
   `draft the Q4 roadmap one-pager..md`. Now trimmed (`?`/`!` deliberately kept — they are
   title-worthy), covered by `DigestSuggestedTitleTests`.

**Open, not fixed (pre-existing, outside this feature):**

- The `Noto-iOS` scheme does not build in the current working tree: two iCloud sync-conflict
  files from 2026-08-24, `Noto/Editor/BlockEditingCommands.sync-conflict-….swift` and
  `Noto/Editor/TextKit2EditorView.sync-conflict-….swift`, redeclare every type in
  `NotoShared/Editor/`. Verified by moving them aside — `Noto-iOS` then builds clean with these
  changes — and restoring them untouched. Deleting them is Eugene's call.
- The audit noted the "Add to" search field sits above the capture preview and the mode picker
  it doesn't apply to (SwiftUI hoists `.searchable` into the navigation bar). Cosmetic; left as is.
