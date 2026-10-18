# Feature: noto2-library-cache

## User Story

As Eugene, when I open Library in Noto 2, I see my notes and folders at once. The
loading spinner shows only the very first time Library loads on a device. After that
the app shows the last known Library and refreshes it silently in the background.

Source: Eugene, 2026-10-18 — "the library loading page or the loading state should just
happen the first time it loads. after that it should already cache the library and it
doesn't have to load anymore or you can refresh it silently in the background".

## Why it loads every time today

`LibraryHome` keeps its `LibrarySnapshot` only in SwiftUI `@State`, and builds it with
`LibraryCatalog.load()`: a walk of the whole vault that reads a 64 KB prefix of every note
through coordinated (iCloud) reads. Nothing persists between launches, so every cold
launch shows the spinner until the full walk ends. `FolderListView` repeats the same full
walk per folder, and shows "Nothing here yet." while it runs.

## User Flow

1. First Library open on a device (no cache): spinner, full scan, list appears; the
   snapshot is saved to disk.
2. Any later open — same session or after a relaunch: the saved list shows at once; a
   silent scan runs in the background and swaps in changes without a spinner.
3. Folder pages: notes show at once from the same snapshot; the silent scan updates them.
4. Pull to refresh still works and shows the system refresh control only.
5. Returning to the app (scene becomes active) on Library triggers a silent refresh.
6. If a scan fails and a snapshot exists, keep showing it; show the error only when
   there is nothing to show.

## Success Criteria

- SC1 — A saved snapshot round-trips to disk unchanged.
- SC2 — The cache is ignored when missing, corrupt, from another schema version, or saved
  for a different vault path.
- SC3 — With a cache, `LibraryModel` publishes the cached snapshot without scanning, and
  the first-load state (spinner) is never shown.
- SC4 — Without a cache, the first-load state shows until the first scan publishes.
- SC5 — A refresh replaces the snapshot and saves the fresh one to disk.
- SC6 — A failed scan keeps the last snapshot and does not surface an error over it.
- SC7 — Refreshes that overlap a running scan coalesce into one extra pass, and a change
  made mid-scan is still picked up.
- SC8 — A late cache read never replaces a fresher scan result.
- SC9 — Folder pages list the snapshot's notes for exactly that directory.
- SC10 (simulator) — After a relaunch, Library shows the list with no spinner; a note
  added on disk while the app is closed appears after the silent refresh.
- SC11 — A scan reads notes with the plain local reader, never the coordinated one.
- SC12 — A rescan reads only notes that are new or whose modified date changed; an
  unchanged rescan reads nothing and returns an identical snapshot.
- SC13 — A rescan drops deleted notes.
- SC14 — A pin added outside the app (frontmatter edit, newer date) appears on rescan.
- SC15 — An offloaded (dataless) note is never downloaded to be listed: it keeps its saved
  title, preview and pin, sorts by its new date, and is read on a later scan once
  downloaded; a new offloaded note shows its filename.

## Test Strategy

Package-level Swift Testing in `Packages/NotoVault` (no simulator): the cache is a pure
file round-trip with temp directories; `LibraryModel` takes an injected loader so scans
can be counted, failed, and slowed. UI wiring is proven in the simulator (SC10).

## Tests

### Package Unit / Integration
- `Packages/NotoVault/Tests/NotoVaultTests/LibrarySnapshotCacheTests.swift`
  - `roundTripsSnapshot` — SC1
  - `missingFileReadsNil` — SC2
  - `corruptFileReadsNil` — SC2
  - `otherVaultReadsNil` — SC2
  - `otherSchemaReadsNil` — SC2
- `Packages/NotoVault/Tests/NotoVaultTests/LibraryModelTests.swift`
  - `cachedSnapshotShowsWithoutScanning` — SC3
  - `firstLoadShowsUntilFirstScan` — SC4
  - `refreshReplacesSnapshotAndPersistsIt` — SC5
  - `failedScanKeepsLastSnapshot` — SC6
  - `failedFirstScanSurfacesError` — SC6 (inverse)
  - `overlappingRefreshesCoalesceIntoOneExtraPass` — SC7
  - `lateCacheReadNeverReplacesFresherScan` — SC8
- `Packages/NotoVault/Tests/NotoVaultTests/LibraryCatalogTests.swift`
  - `snapshotListsNotesForExactlyOneDirectory` — SC9
  - `firstScanReadsEveryNoteWithThePlainReader` — SC11
  - `rescanReadsOnlyNewOrChangedNotes`, `unchangedRescanReadsNothing` — SC12
  - `rescanDropsDeletedNotes` — SC13
  - `pinAddedOutsideTheAppAppearsOnRescan` — SC14
  - `offloadedNoteKeepsSavedDetailsAndIsReadOnceDownloaded`, `newOffloadedNoteShowsItsFilename` — SC15
- `LibraryModelTests.scanStartsFromTheCurrentSnapshot` — each scan receives the snapshot on screen (SC12)

### Simulator
- SC10 via the visual evidence audit.

## Implementation Details

- `NotoVault`: `VaultNoteRecord`, `FolderSummary`, `LibraryNote`, `LibrarySnapshot` gain
  `Codable` (+ `Equatable` on the snapshot). New `LibrarySnapshotCache` (binary plist in
  `Caches/NotoLibrary/`, envelope with schema version + vault path). New `@MainActor
  @Observable LibraryModel` (cache-first, coalesced background scans, writes the cache
  after each changed scan). `LibrarySnapshot.notes(inDirectory:)`.
- `RootTabView` creates one `LibraryModel` per vault with the `VaultController`, starts
  the cache read right away, and injects the model with `.environment(library)` (so Search
  and Media, which reuse `BrowseDestinationView`, need no changes).
- `LibraryHome` / `FolderListView` read from the model; spinner only in the first-load
  state; `.task`, file-watcher and note-sync changes, pull to refresh and scene activation
  all call the silent `refresh()`.

## Incremental scan (added 2026-10-18, Eugene: "yes build that out")

`LibraryCatalog.load(previous:)` lists every visible note with its modified date (one
raw `contentsOfDirectory` per folder, dates prefetched) and reads only notes that are new,
changed, or marked stale. `LibraryModel` passes the snapshot on screen as `previous`.
Three costs found by measurement and removed:

1. `NSFileCoordinator` per note (coordinated reads) — replaced by the plain reader.
2. `ubiquitousItemDownloadingStatus` per note (the plain reader's offloaded check) — a
   file-provider round trip, ~1.7 ms per file. Replaced by one `lstat` and the
   `SF_DATALESS` flag in `CoordinatedVaultFileSystem.readLocalPreview` (also speeds up
   the macOS `VaultLibrary`). Prefetching that key with the listing was even slower.
3. Splitting each note's whole 64 KB prefix into lines for a one-line preview — now
   `split(maxSplits: 2)`.

Measured (`library scan:` info log in `LibraryModel`, and package benchmarks):

| Case | Before | After |
|---|---|---|
| Real iCloud vault, 1,182 notes (Mac), first scan | ~3.5 s | 0.48 s |
| Same, rescan with nothing changed | ~3.5 s | 0.056 s |
| Simulator, 8,008 notes, first scan in app | 11–16 s | 3.3 s |
| Simulator, rescan after relaunch (+1 note) | 11–16 s | 0.77 s |
| Simulator, rescan after an outside pin | — | 0.55 s |

Evidence: `.codex/evidence/20261018-library-cache/20-v2-first-open.png` … `23-v2-pin-from-outside.png`.

## Residual Risks

- `SF_DATALESS` is how macOS marks offloaded iCloud Drive files. If an iOS version marks
  them with hidden `.name.icloud` placeholders instead, those notes stay unlisted (the
  walk skips hidden files) — the same as before this change, and never a blocking read.
- Not yet measured on a physical iPhone.
- The cache lives in `Caches/`; iOS may purge it under storage pressure, which brings
  back one first-load spinner.

## Verification log

- 2026-10-18: `swift test` in `Packages/NotoVault` — 165/165 pass, including the 13 new or
  changed cases above (SC1–SC9).
- Full `Noto2Tests`: 204 pass, 1 fails (`FilingKeyboardLayoutTests.addSearchStays…`). It
  fails the same way on commit 417a351, before this work: pre-existing, test-order dependent.
- Simulator (iPhone 17 Pro, iOS 26.3, vault with 8,006 notes), evidence in
  `.codex/evidence/20261018-library-cache/`:
  - `01-first-open.png` — first open, no cache: spinner (expected).
  - `02-first-open-loaded.png` — list after the first scan; cache file 2.7 MB written.
  - `03-relaunch-instant.png` — after relaunch, with a note added on disk while closed:
    the saved list shows at once, no spinner, new note not yet listed.
  - `04-relaunch-after-silent-scan.png` — ~20 s later the silent scan adds
    "Added while closed" at the top of Recent (SC10).
  - `05-folder-instant.png` — the Bulk folder opens at once with all 8,000 notes (SC9).

- Independent visual audit (`ios_visual_evidence_auditor`): **PASS** on L1–L5 (Library) and
  I1–I2 (Inbox switch, bug 045). Report: `.codex/evidence/20261018-153051-ios-visual-audit/evidence.md`.
  Measured at 8k notes: first open shows the spinner ~11 s; relaunch shows the list at the
  first frame (0.5 s); the silent scan adds a note written while closed at ~11.5 s.

## Why the scan is slow (measured 2026-10-18)

Throwaway benchmark, 8,000 notes in a temp vault on the Mac (`swift test`):

| Step | Time |
|---|---|
| Directory listing (root + Bulk) | 0.36 s |
| Coordinated 64 KB prefix read ×8000 (`readPrefix`, what `LibraryCatalog` uses) | 7.89 s |
| Plain prefix read ×8000 (`readLocalPreview`) | 0.56 s |
| Full `LibraryCatalog.load()` | 8.44 s |

About 94% of the scan is one `NSFileCoordinator` handshake per note (~1 ms each), not
reading bytes. On a real iCloud vault it is worse: a coordinated read of an evicted
(not-downloaded) note waits for that note to download.

Fix candidate: use the existing `readLocalPreview` (uncoordinated, skips evicted notes; the
code already says "a list scan must not coordinate and materialize every cloud note"), and
carry forward the last snapshot's title, preview and pin for evicted notes.

## Follow-ups (not done)

- Folder count line shows "8000" while the Library row shows "8,000" (pre-existing).

## Bugs

_None yet._
