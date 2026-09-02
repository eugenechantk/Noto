# Bug 024: macOS — selecting a search result opens a blank editor

## Status: FIXED — verified 2026-07-13

## Description

On the macOS app, opening the search overlay, running a search, and clicking a
result closes the overlay but the editor detail shows **blank content**. Only
after pressing the editor's back (history) button does the chosen note's
content appear.

Expected: selecting a search result opens that note in the editor with its
content immediately visible.

## Steps to Reproduce

1. Launch Noto on macOS with a vault containing several notes; open any note.
2. Open search (⌘K → macOS search overlay).
3. Type a query matching a *different* note that has not been opened this
   session (so it is not in `NoteContentCache`); click the result row.
4. Overlay closes; the editor pane is completely blank.
5. Press the editor back button → previous note appears (from cache), and
   navigating forward/back eventually shows the chosen note.

Reproduced 2026-07-13 via AX automation on the Debug build (screenshot
`07-after-select.png`: sidebar row "Quitting should be normalized" selected,
editor pane fully black).

## Root Cause

A SwiftUI callback-ordering race in `NoteEditorScreen` when the split-view
editor is **reused** for a different note (macOS always reuses it; iPhone
pushes a fresh screen, which is why iOS doesn't show this):

- `.task(id: note.id)` (NoteEditorScreen.swift:241) is the ONLY place that
  calls `session.loadNoteContent()`, guarded by `!session.hasLoaded`.
- `.onChange(of: note)` (line ~263) performs `session.switchTo(...)`, which
  clears `content` and sets `hasLoaded = false` on a `NoteContentCache` miss.
- On macOS the restarted task runs **before** `.onChange` fires. DebugTrace
  from the live app:

  ```
  selectNote        id=95A5F032 (Birthday)   prevID=FE55000F (Quitting)
  editor task fired noteID=95A5F032 sessionID=FE55000F hasLoaded=true   ← task first, stale session
  session switchTo  new-id … cache-miss  (content="", hasLoaded=false)  ← onChange second
  mac updateVC      doc-change len=0                                    ← empty text applied
  (no further events — loadNoteContent never runs)
  ```

  The task saw the *outgoing* note's `hasLoaded == true` and skipped the load;
  `switchTo` then emptied the session; nothing reloads → blank editor.

- Pressing back re-selects the previous note whose content IS in
  `NoteContentCache`, so `switchTo` restores it synchronously — which is why
  back appears to "fix" it.
- Search results are the common trigger because they usually target notes not
  yet in the cache. Any cache-miss note switch through the reused editor
  (including sidebar clicks after the first open) could blank the same way.

## Fix

`NoteEditorScreen.swift` `.task(id: note.id)`: switch the session **inside the
task** before the load decision, making the task correct regardless of whether
it runs before or after `.onChange(of: note)`:

```swift
.task(id: note.id) {
    session.switchTo(note: note, store: store, isNew: isNew)   // no-op if already switched
    guard !session.hasLoaded else { return }
    await session.loadNoteContent()
}
```

`switchTo` already guards the same-id case (updates store/isNew only), so the
first-appear call and the duplicate call from `.onChange` are harmless.

Also added (DEBUG-only) while investigating, kept for future debugging:
- DebugTrace records in `selectNote`, `switchTo` (cache hit/miss), and the
  macOS `updateNSViewController` apply path.
- A `DistributedNotificationCenter` hook (`NotoDebug.command` / `openSearch`)
  so CLI test drivers can open the search overlay without key-window focus —
  SwiftUI menu commands are window-scoped and unreachable via AX when the app
  isn't key.

## Success Criteria

### 1. Selecting a search result for a non-cached note shows its content immediately
- [x] Verified in unit test
- [x] Verified in simulator (macOS app)

**Unit test:** `NEW` — `NotoTests/NoteEditorSessionTests.swift` →
`switchThenLoadShowsIncomingNoteRegardlessOfCallbackOrder`

**App verification (macOS):**
1. Build and launch the macOS app; note A open.
2. Open search overlay (debug hook), type query for note B (never opened), press result row.
3. Screenshot editor.
4. **Expected:** note B's title and body visible; DebugTrace shows `editor load readable note=B` after `switchTo`.

### 2. First appear / same-id updates don't clear loaded content (inverse case)
- [x] Verified in unit test
- [x] Verified in simulator (macOS app)

**Unit test:** `NEW` — `NotoTests/NoteEditorSessionTests.swift` →
`switchToSameNoteIDPreservesLoadedContent`

**App verification (macOS):**
1. Launch app (restores last note) → content visible, not blanked by the task's unconditional switchTo.
2. **Expected:** restored note renders normally.

### 3. History back still works after a search-open; re-opening from search (cache-hit) shows content
- [x] Verified in simulator (macOS app)

**Unit test:** `EXISTING` — history navigation logic unchanged; covered by NoteListView/history tests.
(No forward button exists in the macOS editor chrome — forward not applicable.)

**App verification (macOS):**
1. After criterion 1, press editor back button → previous note ("Birthday note to mom") content appears (`16-back.png`).
2. Search-open the same note again → cache-hit path renders content (`17-reopen-cachehit.png`).

### 4. No regression in the session load suite
- [x] `NoteEditorSessionTests` 9/9 pass (macOS destination, includes 2 new tests).
- Note: a full `NotoTests` run was attempted but the xcodebuild
  `test-without-building` phase hung for 35+ min without ever spawning an
  xctest host (even after killing the running app instance) and was aborted.
  The change only touches the note-switch load path, which the targeted suite
  covers directly; the full-suite hang is an environment issue, not a test
  failure.

## Investigation Log

### Attempt 1

**Hypothesis (pre-repro static reading):** failure in the selection pipeline —
stale cache, id mismatch, or first-responder guard swallowing the async apply.
**Changes:** none — reproduced first with DebugTrace + AX automation.
**Result:** Reproduced. Trace disproved the cache/id/first-responder theories
and showed `loadNoteContent` never ran after `switchTo` (see Root Cause).

### Attempt 2

**Hypothesis:** `.task(id:)` restarts before `.onChange(of: note)` switches the
session, so the load guard reads the stale `hasLoaded == true`.
**Changes:** added `editor task fired` trace; re-ran repro.
**Result:** Confirmed — `editor task fired noteID=<new> sessionID=<old>
hasLoaded=true` logged BEFORE `session switchTo new-id`. Implemented the fix
(switch inside the task), added regression tests.

### Verification (2026-07-13)

- `NoteEditorSessionTests`: 9/9 pass on macOS destination (includes the 2 new tests).
- Live macOS app (Debug build, pid 23865):
  - Pre-state confirmed: "Birthday note to mom" open (restored at launch).
  - Search "Punch higher" → select result → editor **immediately shows** the
    full content of "Punch higher than you can reach", a note never opened in
    this process (non-cached) — the exact flow that rendered blank pre-fix
    (`15-punch-opened.png` vs pre-fix `07-after-select.png`).
  - Back button → "Birthday note to mom" content renders (`16-back.png`).
  - Search-open the same note again (cache-hit) → content renders (`17-reopen-cachehit.png`).
- Note: an earlier verification attempt (search "Birthday" while Birthday was
  already restored/open) was discarded as invalid — same-id path proves nothing.
