# Bug 020: Index rebuild on iPad only covers part of the notes, then ends

## Status: FIX DEPLOYED — installed on Eugene's iPad mini 2026-06-11 (launch pending unlock); awaiting on-device confirmation

## Description

On Eugene's iPad mini, pressing "Rebuild index" in Settings rebuilds the index for only part of the notes and then ends. Expected: the rebuild covers the whole vault (or clearly says why it can't yet).

## Steps to Reproduce

1. Vault on iCloud Drive; device where iOS has evicted most note files from local storage (the iPad mini was at ~53 MB free yesterday — eviction is certain).
2. Settings → Search → "Rebuild index" (keyword), or "Rebuild index" (semantic — its candidate list is the FTS catalog, so it inherits the same gap).
3. The rebuild finishes quickly, reporting/indexing only a fraction of the ~900 notes.

## Root Cause

`MarkdownSearchIndexer.scanDocuments()` skips every file whose `ubiquitousItemDownloadingStatus != .current` (it kicks off a download and returns nil) — and `SearchIndexStore.rebuild(documents:)` then **deletes the entire index and re-inserts only that downloaded subset**. On a device with most of the vault evicted:

- The rebuild "ends" after indexing only the locally available files.
- Worse, previously indexed notes that are currently evicted are **dropped from the index** (DELETE all + re-insert subset).
- The kicked-off downloads complete later, but nothing tells the user this; the rebuild just looks like it ended early.
- The semantic rebuild embeds only what's in the FTS catalog, so it shows the same partial coverage.

The iPhone behaves differently only because its files happen to be downloaded.

## Success Criteria

### 1. A rebuild never drops notes it cannot currently read
- [x] Verified in unit test
- [ ] Verified on device (simulator cannot evict iCloud files)

**Unit test:** `NEW` — `Packages/NotoSearch/Tests/NotoSearchTests/SearchIndexRebuildRetentionTests.swift` → `rebuildRetainsRowsForUnavailablePaths`

**Verification:** store with notes A, B, C → rebuild with documents [A'] retaining [B] → A replaced, B kept (same noteID), C deleted.

### 2. Full-replace behavior unchanged when nothing is retained
- [x] Verified in unit test

**Unit test:** `NEW` — same file → `rebuildWithoutRetentionReplacesEverything`

### 3. Local (non-iCloud) vault rebuild is unaffected
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — same file → `localVaultRebuildReportsNoSkippedFiles` (skipped == 0, all files indexed)

**Simulator verification:** Settings → Search → Rebuild index on the seeded 775-note vault → footer reads "Indexed 775 notes." ✅ 2026-06-11

### 4. Evicted files get a download kick and a bounded wait; whatever stays unavailable is reported
- [x] Code path (rebuild polls availability up to 60 s, indexes files as they land, returns `skippedUnavailable`)
- [ ] Verified on Eugene's iPad mini (the only environment with real evictions)

**Settings message:** "Indexed N notes. K more are still downloading from iCloud — they keep their existing index entries and re-index automatically once downloaded."

### 5. Files that download later re-index automatically
- [x] EXISTING behavior — file watcher fires when a download materializes → per-file refresh; scene-active refresh sweeps the rest (`refreshChangedFiles` already retains-and-kicks unavailable files).

## Investigation Log

### Attempt 1

**Hypothesis (initial):** app suspension / jetsam during the hours-long semantic sweep (no idle-timer hold).
**Result:** Plausible contributor for the *semantic* rebuild, but doesn't explain a keyword rebuild ending in seconds with partial coverage. Superseded by the eviction finding below.

### Attempt 2

**Hypothesis:** `scanDocuments()` skips undownloaded iCloud files and `store.rebuild` replaces the whole index with the subset — partial index, dropped evicted notes.
**Evidence:** Code path `MarkdownSearchIndexer.rebuild()` → `scanDocuments()` (skips `!isAvailableForIndexing`) → `SearchIndexStore.rebuild` (DELETE all tables, insert only scanned docs). No await on the `startDownloadingUbiquitousItem` calls, no skipped-count surfaced anywhere.
**Fix:** (1) rebuild retains existing index rows for files that exist on disk but are not downloaded; (2) rebuild waits a bounded time for kicked-off downloads and indexes files as they land; (3) the skipped count is returned in `SearchIndexRefreshResult` and surfaced in the Settings message; (4) files that download later are picked up by the existing file-watcher / foreground refresh paths.

**Changes:**
- `Packages/NotoSearch/Sources/NotoSearch/SearchIndexStore.swift` — `rebuild(documents:retainingRelativePaths:)`
- `Packages/NotoSearch/Sources/NotoSearch/MarkdownSearchIndexer.swift` — partition available/evicted, download kick + ≤60 s poll, fresh metadata snapshots for landed files, `skippedUnavailable` in the result
- `Packages/NotoSearch/Sources/NotoSearch/SearchIndexCoordinator.swift` — live `rebuildIndex` no longer destroys the store up front (that dropped retained rows); destroy is now only the corrupt-store fallback
- `Packages/NotoSearch/Sources/NotoSearch/SearchTypes.swift` — `skippedUnavailable` field
- `Noto/Views/SettingsView.swift` — rebuild message reports the still-downloading count
- `Packages/NotoSearch/Tests/NotoSearchTests/SearchIndexRebuildRetentionTests.swift` — 3 new tests

**Test runs:** NotoSearch suite (minus the 9-min LiveVaultSearch): 115 tests, all pass except one pre-existing flaky debounce-timing test that passes in isolation. New retention tests 3/3. Simulator E2E: rebuild on a 775-note local vault → "Indexed 775 notes."

**Note (separate follow-up, not this bug):** the *semantic* rebuild remains an hours-long foreground sweep with no idle-timer hold — auto-lock suspends it, and a cancelled sweep reports progress as total/total (looks finished). Filed as a candidate follow-up; today's "ends after part of the notes" matched the keyword-rebuild eviction path.
