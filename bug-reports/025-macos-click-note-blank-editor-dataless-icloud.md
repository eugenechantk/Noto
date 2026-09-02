# Bug 025: macOS — clicking a note shows a permanently blank editor

## Status: FIXED — verified 2026-08-03

> The app no longer shows a blank pane; it now degrades to
> "Loading note…" → "Downloading from iCloud…" → "Note Not Available / Try Again".
> The *content* still cannot appear until iCloud materializes the files — that part
> is a machine-state problem outside the app (see Root Cause → Trigger).

## Description

On the macOS app, clicking a note in the sidebar selects the row (it highlights)
but the editor pane stays **completely blank** — no content, no spinner, no error.
It never recovers; the note never appears.

Expected: the note's content appears, or — if it genuinely needs to come down from
iCloud — a visible loading/downloading state, and eventually an actionable error.

## Steps to Reproduce

1. Launch Noto on macOS with the iCloud Drive vault
   (`~/Library/Mobile Documents/com~apple~CloudDocs/Noto`).
2. Ensure at least one note file is **evicted** by iCloud ("Optimize Mac Storage"),
   i.e. `ls -lO <note>.md` shows the `dataless` flag.
3. Click that note in the sidebar.
4. Row highlights, editor pane is fully blank — indefinitely.

Reproduced 2026-08-03 on the live Debug build via axdriver:
- `scratchpad/01-launch.png` — restored note "Annoyance Diary" selected, editor black.
- `scratchpad/02-click-arya.png` — "Arya's podcast" selected, editor black.
- AX tree: `AXTextArea note_editor` present with `AXNumberOfCharacters = 0`,
  and **no** "Loading note..." placeholder anywhere in the tree.

## Root Cause

Two independent defects, plus an environmental trigger.

### Trigger (environment)

The vault notes are iCloud **dataless** (evicted) files:

```
$ ls -lO "Arya’s podcast.md"
-rw-------@ 1 eugenechan staff  compressed,dataless  6324 Jun 25 14:38 Arya’s podcast.md
```

`fileproviderd` was pegged at ~90% CPU on its `iCloudDriveFileProvider … database`
queue and was not materializing files, so *any* `read()` of a vault `.md` file
blocks indefinitely — reproducible outside the app:

```
$ head -c 200 "…/Noto/Arya’s podcast.md"     # hangs forever, Noto not running
$ head -c 200 "…/Noto/.noto/sync/readwise.json"   # OK (locally materialized)
```

Restarting `fileproviderd` did not clear it (12 probes over ~4 min, still blocked).

### Defect 1 — the content probe read is unbounded and runs on the cooperative pool

`NoteEditorSession.loadReadableContent` (NoteEditorSession.swift:352) deliberately
prefers "a real read first" over `ubiquitousItemDownloadingStatus` (per the iOS
iCloud rule in CLAUDE.md). But on a dataless file that real read *blocks in the
kernel until materialization*, so:

- `loadNoteContent()` never returns → `hasLoaded` stays false, `content` stays "" →
  blank editor forever. The `needsDownload` branch (spinner + `startDownloading`
  + 30 s deadline) is **never reached**, because the probe that would select it is
  itself the thing that hangs.
- The probe runs via `Task.detached`, i.e. on the Swift **cooperative** thread pool.
  Live sample of the running app showed 7 cooperative threads parked in
  `read()` (via `MarkdownPrefixReader`) plus 2 in
  `NSFileCoordinator._blockOnAccessClaim` — blocking syscalls starve the pool.

DebugTrace from the live app (nothing after the load starts):

```
editor task fired noteID=A6DAA319… sessionID=A6DAA319… hasLoaded=false
session switchTo same-id id=A6DAA319… file=Arya’s podcast.md
(no "editor load readable" — loadNoteContent never returns)
```

### Defect 2 — the loading placeholder never renders

`EditorContentView.DelayedLoadingPlaceholder` (EditorContentView.swift:246) is
supposed to show "Loading note..." after 300 ms. Its body is

```swift
Group { if isVisible && !session.hasLoaded { … } }
    .task { … isVisible = true }
```

`isVisible` starts `false`, so the `Group` resolves to empty content and the
`.task` that would flip `isVisible` never runs — the placeholder can never appear.
Confirmed at runtime: no "Loading" node in the AX tree while unloaded. The user
therefore gets a blank pane instead of any feedback, for *any* slow load.

## Fix

**`Packages/NotoVault/Sources/NotoVault/BoundedFileRead.swift` (NEW).**
`BoundedFileRead.run(timeout:qos:work:)` runs a blocking read on the global
(overcommitting) dispatch queue instead of the cooperative pool, and releases the
caller at a deadline with `.value` / `.failed` / `.timedOut`. The abandoned thread
stays parked until the kernel returns — it cannot be cancelled — but it is a
disposable pool thread, not a cooperative one, so it cannot starve the app's async
work. A `ResumeOnce` box guarantees single continuation resumption.

**`NoteEditorSession.swift`.** `loadReadableContent` still prefers a real read over
ubiquitous metadata (per the CLAUDE.md iCloud rule), but now bounds it at 2 s; a
timeout means "not locally available whatever the metadata says" → `.needsDownload`,
which drives the existing spinner + `startDownloading` + 30 s deadline. Each poll
inside `downloadReadableContent` is bounded at 3 s for the same reason — an unbounded
first poll would block past the overall deadline and the loop could never give up.
Both helpers dropped their `Task.detached` wrappers (that was the cooperative-pool
leak); `downloadReadableContent` now awaits directly and stays cancellable.

**`EditorContentView.swift`.** `DelayedLoadingPlaceholder` now hangs its delay task
off a `Color.clear` base instead of conditional-empty content, so `.task` actually
runs and "Loading note..." can appear. The `downloadFailed` state became an
actionable `ContentUnavailableView` ("Note Not Available") with a **Try Again**
button wired to `session.loadNoteContent()`.

## Success Criteria

### 1. A note whose content cannot be read shows visible state, never a blank pane
- [x] Verified in unit test
- [x] Verified in app (macOS)

**Unit test:** `NEW` — `Packages/NotoVault/Tests/NotoVaultTests/BoundedFileReadTests.swift`
→ `timesOutWhenReadBlocks`, `releasesCallerWhileReadIsStillBlocked`

**App verification (macOS):**
1. Launch with the wedged iCloud vault (notes `dataless`, `fileproviderd` pegged).
2. Observe the editor pane.
3. **Expected:** spinner + "Downloading from iCloud...", then after the 30 s deadline
   "Note Not Available" with a Try Again button.

**Result:** PASS — `scratchpad/03-fixed-loading.png` (spinner) and
`scratchpad/04-fixed-unavailable.png` (error + Try Again). DebugTrace:
`editor load download-timeout note=Arya’s podcast.md` at T+36 s.
Pre-fix, the same state was a fully black pane forever (`02-click-arya.png`).

### 2. Clicking a different note in the sidebar shows that state too (the reported action)
- [x] Verified in app (macOS)

**App verification (macOS):** click "Failure resume" in the sidebar; AX tree query for
placeholder text.
**Result:** PASS — AX tree contains "Downloading from iCloud" (`05-click-other-note.png`).

### 3. Inverse case — a readable local note still loads immediately
- [x] Verified in unit test
- [x] Verified in test suite run

**Unit test:** `EXISTING` — `NotoTests/NoteEditorSessionTests.swift` →
`loadNoteContentReadsExistingFileIntoSession`, `switchThenLoadShowsIncomingNoteRegardlessOfCallbackOrder`,
`switchToSameNoteIDPreservesLoadedContent`
**Unit test:** `NEW` — `BoundedFileReadTests` → `returnsValueWhenReadCompletesInTime`

**Result:** PASS — 18/18 in the macOS app test run.

### 4. Inverse case — a genuinely missing/unreadable file still reports failure fast
- [x] Verified in unit test

**Unit test:** `EXISTING` — `NotoTests/NoteEditorSessionTests.swift` →
`loadNoteContentMarksUnreadableCurrentFileAsFailed`
**Unit test:** `NEW` — `BoundedFileReadTests` → `returnsFailedWhenReadYieldsNil`
(`.failed` must stay distinct from `.timedOut`, or a missing file would be
misreported as "still downloading").

**Result:** PASS.

### 5. Concurrent stalled reads don't stall each other
- [x] Verified in unit test

**Unit test:** `NEW` — `BoundedFileReadTests` → `concurrentBoundedReadsAllResolve`,
`abandonedReadResultIsDiscarded`

**Result:** PASS — 12 simultaneous blocked reads all resolve on their own deadline.

### 6. No regression in the vault/session suites
- [x] `swift test` in `Packages/NotoVault`: 77 tests / 12 suites pass.
- [x] `flowdeck test -s Noto-macOS --only NotoTests/NoteEditorSessionTests`: 18/18 pass.

## Remaining Risk (not fixed — out of scope of the reported bug)

`VaultDirectoryLoader.loadItems` → `MarkdownPrefixReader.readPrefix` reads note
prefixes with the same unbounded, uncoordinated `FileHandle.read` and runs on the
cooperative pool via `MarkdownNoteStore.loadItemsInBackground`. The live sample showed
**7** cooperative threads parked there. The note list still renders (titles fall back
to filenames), so this does not reproduce the reported symptom, but it is the same
class of defect and should get the same `BoundedFileRead` treatment.

## Environmental remediation (the reason content still can't load on this Mac)

The vault notes are evicted and iCloud is not materializing them. To recover:
- System Settings → Apple Account → iCloud → iCloud Drive → turn **off**
  "Optimize Mac Storage" for this Mac, so vault notes stay on disk; and/or
- right-click the `Noto` folder in Finder → **Download Now**;
- if `fileproviderd` stays pegged near 100% CPU, a reboot is the reliable reset
  (`killall -9 fileproviderd` alone did not clear it here — 12 probes over ~4 min
  still blocked).

## Investigation Log

### Attempt 1

**Hypothesis (pre-repro):** regression from the uncommitted tag-system work
(`TagController.rebuildMembership` scans and reads every `.md` in the vault, and is
re-run on every file-watcher tick with no coalescing).
**Changes:** added a temporary `NOTO_DISABLE_TAG_SCAN` env kill-switch to
`TagController.rebuildMembership`, rebuilt, relaunched with the scan disabled.
**Result:** Disproved. With the tag scan confirmed off (`scanTagRecords` absent from
the sample), the editor still hung in exactly the same place
(`loadReadableContent → NSFileCoordinator._blockOnAccessClaim`). Kill-switch reverted.

### Attempt 2

**Hypothesis:** the reads themselves are blocked at the OS level.
**Changes:** none — probed from the shell with Noto killed.
**Result:** Confirmed. `.md` reads in the vault hang indefinitely; a materialized
`.json` in the same vault reads fine; `ls -lO` shows the notes are `dataless`;
`fileproviderd` pegged ~90% CPU. See Root Cause.

### Attempt 3 (fix)

**Hypothesis:** the blank pane is two app defects — an unbounded probe read that can
never reach the download UI, and a loading placeholder whose `.task` never runs —
on top of an environmental iCloud stall.
**Changes:** added `BoundedFileRead` (NotoVault) + bounded both read paths in
`NoteEditorSession`; rebased `DelayedLoadingPlaceholder` on a non-empty view; made the
failure state actionable with Try Again. Tests as listed under Success Criteria.
**Result:** Fixed and verified live against the still-wedged vault — the exact
scenario that previously produced a permanent blank pane now shows spinner → error.
