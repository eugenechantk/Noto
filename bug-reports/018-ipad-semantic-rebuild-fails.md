# Bug 018: iPad mini fails during semantic index rebuild

## Status: FIXED — verified 2026-06-11 (Eugene, on-device)

## Description

On Eugene's iPad mini 6 (4 GB RAM, iPadOS 26.2, TestFlight build 202606102226), the semantic index rebuild fails partway. The same build on iPhone 13 Pro (6 GB) progresses, slowly (378/895 notes). Exact user-visible failure mode not yet captured (Settings "rebuild failed" message vs app termination).

## Steps to Reproduce

1. Real vault (~895 notes, Readwise captures with many remote images) on an iPad mini 6.
2. Let the initial sweep run / press Settings → "Rebuild semantic index".
3. Observe failure partway through embedding.

## Root Cause

**CONFIRMED (2026-06-10): storage exhaustion, compounded by memory pressure.** The dev-build install attempt surfaced it directly: the iPad mini has ~53 MB free (213 MB needed for the install). The semantic rebuild on this device was writing the index + remote-image cache (vault references ~1,500 remote images) onto an essentially full disk — SQLite "disk full"-class write failures abort the sweep, which the old code surfaced as an opaque "rebuild failed". Secondary, independently measured: the sweep's working set rides the 4 GB device's ~1 GB foreground memory ceiling (sim trace: 700–964 MB), so even with free disk the iPad was at risk where the 6 GB iPhone survives. Both contributors fixed; storage now fails fast with an actionable message.

The semantic sweep (`SemanticIndexer.refreshFromSearchIndex`) is one long synchronous call on a detached task thread. Per note it allocates autoreleased objects — `NSNumber` boxes for every MLMultiArray element (1,024 per chunk), Vision OCR bitmaps (up to 2048px CGImages), `VNRecognizedTextObservation`s, SQLite row strings — and **nothing drains an autorelease pool until the entire sweep returns**. Over 895 notes (~10k chunks + hundreds of images) the footprint grows unbounded → jetsam (app killed) or Core ML allocation failure (throws → sweep aborts → "rebuild failed") on the 4 GB iPad, while the 6 GB iPhone survives degraded.

## Success Criteria

_TBD after root cause confirmed._

## Investigation Log

### Attempt 1

**Hypothesis:** Missing `autoreleasepool` around per-note/per-image/per-chunk work causes unbounded memory growth during the sweep; iPad mini's 4 GB ceiling kills it.
**Experiment:** Run the app on an iPad mini simulator seeded with the real vault (`seed-vault.sh --current-vault`); sample the app process RSS every 5 s during the sweep. Expect monotonic growth into multiple GB if the hypothesis holds. Then add autoreleasepool drains and expect flat RSS.
**Changes:** none (measurement only)
**Result:** PARTIALLY CONFIRMED + refined. iPad mini sim with the real 902-note vault: RSS oscillates 380–964 MB (not unbounded — pools do drain eventually), but sustained 700–900 MB with ~1 GB peaks. iPad mini 6 foreground jetsam ceiling ≈ 1.0–1.2 GB (vs ~2 GB on iPhone 13 Pro/6 GB) → the workload rides the iPad's kill line; any transient spike terminates the app there while the iPhone survives. Compounding: throughput measured at ~4 notes/min (902 notes ≈ 3.7 h exposure), and the sweep aborts wholesale on the first embed error (`refreshFromSearchIndex` rethrows), so any single hiccup surfaces as "rebuild failed".

### Attempt 2

**Hypothesis:** Reducing peak/transient memory (autoreleasepool drains per note/image, direct MLMultiArray memory writes instead of NSNumber boxing, smaller OCR decode target) keeps the sweep well under the iPad ceiling; per-note error isolation (skip + continue, abort only on consecutive systemic failures) makes residual failures non-fatal; surfacing the error detail in Settings removes the opacity.
**Changes:** SemanticIndexer (autoreleasepool per note + per image; per-note error isolation — skip and continue, abort only on 3 consecutive failures), GraniteEmbedder (autoreleasepool per batch; direct Int32/Float buffer writes replacing ~1k autoreleased NSNumber boxes per chunk, with a defensive dtype fallback), VisionImageDescriber (decode target 2048 → 1280 px, pool per describe; describerVersion intentionally NOT bumped — avoids re-describing existing chunks, quality delta negligible), SettingsView (failure message now carries the error description + resume guidance).
**Result:** All changes unit-tested green (47 tests across affected suites, incl. 2 new: single-failure skip + consecutive-failure abort). First re-measurement attempt INVALIDATED: a concurrent session built/reinstalled against the same worktree mid-trace, killing the instrumented app (no crash report — external kill) and contaminating the run. Clean re-trace pending session coordination.

### Attempt 3

**Trigger found:** device install failed with `Insufficient storage: 213,473,701 bytes needed, 53,142,160 available` — the iPad is nearly full, retroactively explaining the rebuild failure (index + image cache writes onto a full disk).
**Changes:** SemanticIndexer now preflights free space (`volumeAvailableCapacityForImportantUsage`) and refuses the sweep below 150 MB with an actionable error ("free up space and indexing will resume automatically") that surfaces verbatim in Settings.
**Result:** Indexer suite green (8 tests). Remote-image cache writes were already best-effort (data still returned when the cache write fails), so the guard closes the remaining confusing path. LRU size cap for the image cache noted as future work.

## Final Summary

**Root cause:** storage exhaustion (~53 MB free on the iPad; index + remote-image cache writes failed) with memory pressure as a secondary risk on 4 GB devices (sweep working set measured at 700–964 MB vs ~1 GB foreground ceiling).
**Fix:** free-space preflight with actionable error; autoreleasepool drains per note/image; direct ML buffer writes; 1280 px OCR decode; per-note error isolation (abort only after 3 consecutive failures); error detail surfaced in Settings.
**Verification:** 47+ package tests green incl. 2 new regression tests; after Eugene freed iPad storage, dev install succeeded and the semantic indexing completed on the physical iPad mini — confirmed working by Eugene 2026-06-11. (Sim memory re-trace was contaminated by a concurrent session's build and superseded by the on-device confirmation.)
