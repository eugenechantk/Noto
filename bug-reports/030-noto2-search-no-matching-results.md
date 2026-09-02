# Bug 030: Noto 2 search does not show notes that match the query

## Status: PARTIAL FIX DEPLOYED — root cause needs one datapoint from the device

**Reported on:** iPhone, real iCloud vault (`~/Library/Mobile Documents/com~apple~CloudDocs/Noto`,
1131 `.md` files). Failing queries: plain English words and multi-word phrases.

## Description

**What happens:** Noto 2's Search tab shows no results (or not the right notes) for a query
that plainly matches existing notes, and tells the user to "check the spelling".

**What should happen:** The hybrid (FTS keyword ∪ semantic) search returns every note whose
title or body contains the query term — and when it genuinely cannot, it should say why.

## What was ruled out

The search engine itself is healthy. Verified against Eugene's **real corpus**, not a toy vault:

| Check | Method | Result |
|---|---|---|
| FTS query construction + tokenizer | Ran `MarkdownSearchEngine.ftsQuery`-shaped `MATCH` queries directly against the live macOS index (1059 notes) | `workout*` → 36, `coaching*` → 48, `workout* coaching*` → 10, `vibe* coding*` → 72 |
| Keyword leg at real scale | Copied 742 of the real vault's notes into the Noto 2 simulator container, let the index build | `Steve Jobs` → 78 results, `Disrupting Class` → 86 results |
| Subfolder notes | `Consumer ai` against seeded vault | 3 results incl. `Captures/` with breadcrumb |
| Title-only match | `Shopping` | 1 result |
| Semantic fusion doesn't starve keyword hits | Re-ran `Roadmap` after the semantic index finished | still returned, unchanged |
| Capture → index → search loop | Captured a note, swiped right to file it, searched a unique word | found within ~5s |
| `HybridSearchFusion.fuse` | Code read | keyword hits always survive up to `limit`; RRF cannot drop them |

So this is **not** a query-parsing, tokenizer, ranking, or fusion bug.

## Root Cause

**The index, not the search.** Noto 2 has its own app container, so it maintains a search
index entirely separate from Noto's (`MarkdownSearchIndexer.defaultIndexDirectory` keys the
index directory by a hash of the vault path, under the app's own Application Support). On a
phone it must build all 1131 notes itself, and two things make that slow to complete:

1. **Throughput.** Measured ~3 notes/sec in the simulator, so ~6 minutes of foreground time
   for 1131 notes — and iOS suspends the sweep whenever the app is backgrounded. It resumes
   (the sweep is incremental) but may never have finished.
2. **iCloud eviction.** `MarkdownSearchIndexer.refreshChangedFiles()` skips any file whose
   `ubiquitousItemDownloadingStatus != .current`, kicks a download, and moves on. On a phone
   with an iCloud vault most note bodies start evicted, so they are scanned but not indexed.

Either way the index sits well below the vault total, and every un-indexed note is invisible
to search.

**The reason this reads as "search is broken" rather than "still indexing" is a real UI bug:**
`SearchScreen` rendered `ContentUnavailableView.search(text:)` for an empty result set, which
says *"Check the spelling or try a new search"* — even when the index holds 3 of 1131 notes.
The empty-state line also printed the bare indexed count with no denominator, so a stalled
index looked identical to a complete one.

## Fix

1. `Noto2/Search/SearchIndexCoverage.swift` (new) — coverage wording, testable without a view.
2. `Noto2/Search/SearchScreen.swift` — the empty result set now distinguishes the two cases:
   **"Still Indexing — Only 3 / 1131 notes are searchable so far, so "<query>" may be in a note
   that has not been indexed yet"** plus a **Resume Indexing** button, versus the honest
   **"No Results … check the spelling"** when the index has caught up. The idle empty state
   now shows `indexed / total` whenever the two differ.
3. `Packages/NotoSearch/.../MarkdownSearchIndexer.swift` — `refreshChangedFiles()` now counts
   and reports `skippedUnavailable` (it was always 0 before, so evicted-file skips were
   invisible to every caller).
4. `Noto2/RootTabView.swift` — logs each sweep's shape
   (`scanned / upserted / deleted / skippedUnavailable / indexedNotes`).

This makes the failure legible and recoverable in-app. **It does not yet address whichever of
the two mechanisms is actually starving the device's index** — that needs the number below.

## Outstanding

Open Noto 2 → Search on the iPhone with an empty query and read the line under
"Search your notes". It now reads `<indexed> / <total> notes indexed`.

- `X / 1131` with X small and climbing → throughput; fix is to finish the sweep in the
  background (BGProcessingTask) instead of only while foregrounded.
- `X / 1131` with X stuck → iCloud eviction; fix is to make the download-and-index loop
  durable instead of one-shot per sweep.
- `1131 / 1131` → the index is fine and the root cause is elsewhere; reopen the investigation
  with the exact query and the note that should have matched.

## Success Criteria

### 1. An empty result set caused by an incomplete index says so, and never blames spelling
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `Noto2Tests/SearchIndexCoverageTests.swift` → `partialIndexIsNotPresentedAsAMiss`

**Simulator verification:**
1. Inflate the simulator vault to 6142 notes so the sweep is observably slow; delete the index
2. Launch, open Search, query a term that only exists in a late-sorting folder
3. **Expected:** "Still Indexing — Only 0 / 6142 notes are searchable so far…" + Resume Indexing
4. **Actual:** matched; the count climbed live (0 → 195 → …) — `scratchpad/late-2.jpg`, `late-8.jpg`

### 2. A genuine miss against a complete index keeps the honest wording and offers no resume action
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `Noto2Tests/SearchIndexCoverageTests.swift` → `completeIndexIsPresentedAsAGenuineMiss`

**Simulator verification:**
1. Let the 742-note index finish (empty state reads "742 notes indexed", no denominator)
2. Search `zzqqxxnothinghere`
3. **Expected:** "No Results — No notes match … Check the spelling", no Resume button
4. **Actual:** matched — `scratchpad/final-genuine-miss.jpg`

### 3. A note indexed late in the sweep becomes findable once the sweep completes
- [x] Verified in simulator

**Simulator verification:**
1. After the sweep finishes, search `Quixotrell` (only in `zzz-late/Late Note.md`)
2. **Expected:** 1 result
3. **Actual:** matched — `scratchpad/final-late-note.jpg`

### 4. Real-corpus search is unregressed
- [x] Verified in unit test — 129/129 `swift test` in `Packages/NotoSearch`, 38/38 `flowdeck test -s Noto2`
- [x] Verified in simulator — `Steve Jobs` → 78 results, `Disrupting Class` → 86 results

## Investigation Log

### Attempt 1 — reproduce on the seeded simulator vault

**Hypothesis:** search is broken for all queries in Noto 2.
**Changes:** none (observation only).
**Result:** Not reproduced. Five query shapes (body word, title word, multi-word, subfolder,
post-semantic-build) all returned correct results; a freshly captured note was searchable in
~5s. Search, fusion, and the capture→index loop are healthy in a clean environment.

### Attempt 2 — validate against the real corpus

**Hypothesis:** the failure is scale- or content-specific to the 1131-note vault.
**Changes:** none. Queried the live macOS index by SQL; copied 742 real notes into the Noto 2
simulator container and searched through the UI.
**Result:** Not reproduced. Both the raw FTS layer and the full Noto 2 UI returned large,
correct result sets. Rules out the engine; leaves index population on the device.

### Attempt 3 — make the failure legible

**Hypothesis:** the device's index is incomplete, and the UI misreports that as a failed match.
**Changes:** the four listed under **Fix**.
**Result:** Confirmed the misreporting half. With a deliberately slow sweep (6142 notes) the
old UI would have said "check the spelling" at 0/6142 indexed; it now reports the shortfall and
offers a resume. Which mechanism starves the device index is still open — see **Outstanding**.
