# Bug 036: "Keep editing" sometimes opens Digest instead of the capture note on a cold launch

## Status: FIXED — verified 2026-09-26

## Description

From the share sheet's **Link captured** sheet, "Keep editing" should open Noto 2 on the capture note it just staged. On a cold launch (Noto 2 not running) it sometimes lands on the Digest tab with the capture on top instead. Found by the independent audit of the share-sheet restyle (`.codex/evidence/20260926-015825-ios-visual-audit/`, screenshot `07-keep-editing-cold-launch-opens-digest.png`): 1 of 3 cold runs.

## Steps to Reproduce

1. Simulator booted, Noto 2 not running.
2. Share a page to Noto 2, close with ✕ (a second staged capture makes the drain slower).
3. Share another page; wait ~15 s on the sheet.
4. Tap Keep editing.
5. **Expected:** the capture note opens. **Actual (intermittent):** Digest tab. The log shows two drains running at once, then `Shared capture … not filed this session; showing Digest`.

## Root Cause

`RootTabView.drainSharedCaptures()` is called from three places that all fire during a cold launch through the `noto2://capture?shared=<id>` link: the launch `.task(id: vaultURL)`, `.onChange(of: scenePhase)` → active, and `.onChange(of: launchRouter.requestRevision)`. Nothing serialised them, so two drains ran concurrently (each in a detached task over the same App Group files). Each drain ends with `openRequestedSharedCaptureIfNeeded()`, which **consumes** the open request. When the drain that did *not* record the requested capture finished first, `sharedCaptureNotes[id]` was still empty, so it cleared the request and fell back to Digest — while the other drain was about to record the note.

Pre-existing (not introduced by the share-sheet restyle); the restyle's audit surfaced it.

## Fix

`Noto2/SharedCaptureDrainQueue.swift`: runs the drain one at a time. A call while a drain is running asks for exactly one more pass after it (a capture staged mid-drain still gets filed) and every caller returns only when no pass is left. `RootTabView` drains through the queue and resolves the "Keep editing" request only after the queue has settled, so the request is never consumed before the note that answers it is recorded.

## Success Criteria

### 1. Drains never overlap
- [x] Verified in unit test
- [x] Verified in simulator (re-audit: one drain pass per cold launch; previously 2–3 overlapping)

**Unit test:** `NEW` — `Noto2Tests/SharedCaptureDrainQueueTests.swift` → `concurrentCallsNeverOverlap`

### 2. A call during a drain triggers exactly one more pass, and every caller waits for it
- [x] Verified in unit test

**Unit test:** `NEW` — `SharedCaptureDrainQueueTests` → `callsDuringARunCoalesceIntoOneMorePass`, `everyCallerReturnsAfterTheLastPass`

### 3. Keep editing opens the capture note on a cold launch (primary case)
- [x] Verified in simulator — 6/6 cold runs, including the stress shape and a first launch after a simulator reboot

**Simulator verification:**
1. Terminate Noto 2. Share a page to Noto 2, close with ✕. Share a second page, wait ~15 s.
2. Tap Keep editing. **Expected:** Noto 2 opens on that capture note. Repeat 5 times (cold each time).
3. Log: no `not filed this session; showing Digest`.

### 4. Inverse: a warm app still opens the note; a capture filed by an earlier launch still falls back to Digest
- [x] Verified in unit test (routing suite green) / simulator (warm run opened the note; earlier-launch fallback unchanged code path, not re-exercised)

**Unit test:** `EXISTING` — `Noto2Tests` routing suite (`Noto2QuickCaptureRoutingTests`) stays green.

## Investigation Log

### Attempt 1

**Hypothesis:** concurrent drains race on consuming the open request (log shows two drains, then the Digest fallback).
**Changes:** serialise drains with `SharedCaptureDrainQueue`; open the requested capture only after the queue settles.
**Result:** First test version was too timing-dependent (calls issued before the first pass started are correctly folded into it, but the tests expected an extra pass); rewrote the tests with a gate that holds the first pass open. `SharedCaptureDrainQueueTests` 4/4, `Noto2Tests` otherwise green. Simulator self-check: cold launch opened the note, one drain in the log.

## Verification

- Independent re-audit **PASS**: `.codex/evidence/20260926-023946-ios-visual-audit/evidence.md` — 6/6 cold runs + 1 warm run opened the requested note (~1.0–1.3 s after the tap), no "showing Digest" log line, 15 shares → 15 notes with no duplicates; ✕, Close and swipe down still close the sheet. Cosmetic note: a cold launch shows the Capture tab (keyboard up) for under a second before switching to the note — existing launch behaviour.

## Summary

Root cause: three launch-time triggers drained shared captures concurrently, and a pass that had not recorded the requested capture consumed the "Keep editing" open request. Fix: `SharedCaptureDrainQueue` runs one pass at a time (a call mid-pass queues exactly one more) and `RootTabView` resolves the open request only after the queue settles.
