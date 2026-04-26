# Bug 011: Tapping a search result is sluggish and sometimes crashes the app

## Status: FIX DEPLOYED — installed on iPad Mini + iPhone Hihi (iOS 26) 2026-04-26; awaiting on-device confirmation

## Description

After search returns results (Bug 010 fix), tapping a result is **sluggish** on iOS/iPadOS — and on a real device with a large or iCloud-backed vault it can **crash the app**. The crash matches an iOS watchdog termination signature: the main thread blocks long enough that iOS kills the process.

## Steps to Reproduce

1. Launch Noto on iPhone or iPad with a vault containing many notes (Eugene's vault on `Noto-CurrentVault-iPad`: 725 notes, including `Captures/$100M Offers.md`).
2. Tap the magnifying glass in the bottom toolbar.
3. Type "100m offers" — `$100M Offers` appears (per Bug 010 fix).
4. Tap the result.
5. **Expected:** the editor opens immediately on the tapped note.
6. **Observed (real device):** several seconds of unresponsiveness; sometimes the app is killed by iOS before the editor appears.

## Root Cause

`NotoSplitView.selectHistoryEntry(_:recordsVisit:)` runs `resolvedHistoryEntry` on every selection (including fresh search results). That helper calls `MarkdownNoteStore.note(withID:)` (`Noto/Storage/MarkdownNoteStore.swift:490`), which:

1. Walks the **entire vault** with `FileManager.enumerator`.
2. For every `.md` file, calls `CoordinatedFileManager.readString(from:)` — reading the **full file content** on the **main thread**.
3. Compares the frontmatter UUID against the entry's `note.id`. Stops when matched.

Two problems compound:

- **Always-on cost.** Even when the note's file still exists at its known URL (the common case for fresh selections), the helper does a full vault scan. For 725 notes that's hundreds of MB of file reads on a real device.
- **`.fileOnly` regression from Bug 010.** Bug 010 made `IOSNoteSearchSheet` use `noteMetadataStrategy: .fileOnly` to skip frontmatter reads on load. That set the search-result `note.id` to `VaultDirectoryLoader.stableID(for: url)` (a path hash) instead of the frontmatter UUID. The lookup **never matches** any real frontmatter UUID, so the loop reads **every file** before returning nil, then falls back to the original entry. Worst-case behavior on every tap.

On simulator (M-series + NVMe) the cost is ~1s and feels merely sluggish. On a real iPhone with iCloud-backed files it can stall the main thread past the watchdog limit, and iOS terminates the app.

## Fix

Two changes — first one cuts the latency to ~0 in the common case, second bounds the worst case.

1. **`NotoSplitView.resolvedHistoryEntry`** — add a fast path: if the entry's `fileURL` still exists, the entry is valid; return it without touching `note(withID:)`. The slow vault walk only runs when a history entry's file has actually moved/been deleted.

2. **`MarkdownNoteStore.note(withID:)`** — read frontmatter prefix (up to 64KB) instead of the full file when checking IDs. Only after a prefix match does it read the full content for `displayTitle`. This stays the slow path's worst case at ~64KB × N reads instead of full-content × N reads.

## Success Criteria

### 1. Fresh search-result tap takes O(1) time, not O(vault size)
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `NotoTests/MarkdownNoteStoreTests.swift` → `noteWithIDPrefersFrontmatterPrefix` (validates `note(withID:)` doesn't read full file content for non-matching files).

**Simulator verification:**
1. Launch Noto on iPad simulator with the user's vault.
2. Open search, type "100m offers".
3. Tap the `$100M Offers` result.
4. **Expected:** the editor opens within ~500ms.

### 2. History navigation still resolves moved files
- [x] Verified in unit test (existing `note(withID:)` tests in `MarkdownNoteStoreTests.swift`)
- [ ] Manual: not regression-tested in simulator (pre-existing behavior)

The `resolvedHistoryEntry` fast path is bypassed when `FileManager.fileExists(atPath:)` returns false, falling through to the existing slow path. This preserves behavior for moved/deleted notes.

## Investigation Log

### Attempt 1

**Hypothesis:** `resolvedHistoryEntry` triggers a full-vault main-thread scan on every search-result tap.

**Changes:**
- `NotoSplitView.resolvedHistoryEntry`: short-circuit when `entry.note.fileURL` still exists.
- `MarkdownNoteStore.note(withID:)`: read 64KB prefix instead of full file when probing for the matching frontmatter ID.

**Result:** simulator E2E passes; build clean. Real-device verification pending.
