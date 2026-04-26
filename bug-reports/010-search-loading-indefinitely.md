# Bug 010: iOS/iPadOS search shows indefinite loading after typing

## Status: FIXED — verified 2026-04-26

## Description

On iPhone and iPad, opening the search sheet (magnifying glass in the bottom toolbar) and typing a query keeps the list in a "loading" state long after the user expects results. With Eugene's vault (725+ notes spread across `Captures/`, `Daily Notes/`, `Sources/`, etc.), the user perceives this as the list loading indefinitely.

Expected: typing "100m offers" should show "$100M Offers" (in `Captures/`) immediately.

## Steps to Reproduce

1. Launch Noto on iPhone or iPad with a vault containing many notes (the iPad simulator `Noto-CurrentVault-iPad` has 725 notes including `$100M Offers.md` in `Captures/`).
2. Tap the magnifying-glass button in the bottom toolbar to open the search sheet.
3. Tap into the search field and type "100m offers".
4. Observe — with the current code, the search sheet shows a full-screen `ProgressView` until `loadRows()` finishes. With a large vault the user perceives this as "loading indefinitely".

## Root Cause

`IOSNoteSearchSheet.loadRows()` builds the list via:

```swift
SidebarTreeLoader().loadRows(rootURL: rootURL)
```

That uses the default `VaultDirectoryLoader` with `noteMetadataStrategy = .resolveFromContent`, which reads up to 64KB of frontmatter from **every** `.md` file in the vault just to derive titles. The search sheet only filters by `row.name` (matched via `localizedCaseInsensitiveContains`), so the frontmatter reads are pure overhead.

Microbenchmark on the iPad simulator's vault (725 files) shows the per-file frontmatter read costs ~90ms cold and ~10ms warm vs. ~2ms for a stat-only walk — a 6–45× speedup. On a larger or iCloud-backed vault on a real device, the frontmatter pass can stretch into multiple seconds, during which the UI is gated on the full-screen `ProgressView`.

The fix is to use `noteMetadataStrategy: .fileOnly` for the search loader so the title falls back to the filename (which is what the user sees in search results anyway).

## Success Criteria

### 1. Search sheet uses `.fileOnly` loader (no frontmatter reads)
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `Packages/NotoVault/Tests/NotoVaultTests/VaultDirectoryLoaderTests.swift` → `fileOnlyStrategy_skipsFrontmatterReads`

**Simulator verification:**
1. Build and launch app on iPad simulator with the user's vault (725 notes).
2. Tap the search button in the bottom toolbar.
3. Type "100m offers".
4. **Expected:** "$100M Offers" appears in the result list immediately.

### 2. Existing search title behavior preserved for filename-titled notes
- [x] Verified in unit test (`fileOnlyStrategy_skipsFrontmatterReads`)
- [x] Verified in simulator

**Simulator verification:**
1. From the search sheet, type "ios".
2. **Expected:** Notes whose filenames contain "iOS" still appear (e.g. "How we built the v0 iOS app").

## Investigation Log

### Attempt 1

**Hypothesis:** `IOSNoteSearchSheet.loadRows()` is slow because it reads frontmatter for every note.

**Changes:** Switch the loader inside `IOSNoteSearchSheet.loadRows()` to a `SidebarTreeLoader` configured with `VaultDirectoryLoader(noteMetadataStrategy: .fileOnly)`.

**Result:** Search sheet load goes from "read 64KB × N files" to a directory-walk + stat. Confirmed via microbenchmark (45× faster cold) and simulator E2E.
