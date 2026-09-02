# Bug 031: Noto 2's AI summary intermittently falls back to note snippets

## Status: FIX DEPLOYED — verified 2026-08-31 (simulator); device confirmation pending

## Description

**What happens:** The Summary above the search results sometimes shows sentences copied out
of the top matching notes instead of a written summary.

**What that actually is:** `ExtractiveSearchSummary` — the offline fallback added by bug 027.
It is working as designed; the question is why the remote call it replaces keeps failing.

**What should happen:** The AI summary should complete. When it genuinely can't, the fallback
should say *why*, not silently degrade.

## Root Cause

**The summary was being cancelled by its own screen, not failing.**

`SearchScreen` re-runs the search whenever the index changes:

```swift
.onReceive(NotificationCenter.default.publisher(for: .notoSearchIndexDidChange)) { _ in
    if !trimmedQuery.isEmpty, path.isEmpty { model.refresh() }
}
```

`model.refresh()` calls `queryChanged(immediate: true)`, which unconditionally did
`summaryTask?.cancel()` — even though the query had not changed. So every index-change
notification killed the in-flight LLM stream and started it over.

`SearchIndexController` posts that notification after *every* refresh, per-file refresh,
queue drain and rebuild, and `RootTabView` triggers a per-file refresh on every
`VaultFileWatcher` change. On a vault whose notes are still arriving from iCloud — which is
exactly bug 030's situation on the phone — those fire continuously. Search results recompute
in milliseconds so they always looked fine; a multi-second summary stream repeatedly lost the
race and the user only ever saw the offline highlights.

This also explains "sometimes": on a settled index the notifications stop and the summary
completes, which is why it never reproduced on a freshly-indexed simulator.

**Second, smaller defect:** the fallback rendered `· Offline highlights` with no cause. An
expired key, an out-of-credit account, a rate limit and a dropped connection all produced a
byte-identical screen, so there was nothing to act on — which is why this was reported as
"the AI summary doesn't work" rather than a specific failure.

## Fix

1. `Noto2/Search/SearchModel.swift`
   - `queryChanged` only cancels the summary when the **query itself** changed.
   - New `startSummaryIfNeeded` / `shouldStartSummary(...)`: a summary is left alone when it is
     already streaming or done for this exact query **and** the same note set. A changed result
     set (the index filled in and new notes match) still re-summarizes.
   - New `summaryFallbackReason` + `shortReason(for:)`: maps failures to a few actionable
     words — `key rejected`, `out of credits`, `rate limited`, `provider error 503`,
     `no network`, `timed out`, `empty response`, `interrupted`.
2. `Noto2/Search/SearchScreen.swift` — provenance line now reads
   `From the top 8 notes · Offline highlights (rate limited)`.

## Success Criteria

### 1. An index-change refresh does not restart an in-flight or finished summary
- [x] Verified in unit test
- [x] Verified in simulator

**Unit tests:** `NEW` — `Noto2Tests/SearchSummaryStabilityTests.swift` →
`sameQueryAndNotesDoesNotRestartAStreamingSummary`, `sameQueryAndNotesDoesNotRestartAFinishedSummary`

**Simulator verification:**
1. Search `startup` against the 742-note real-vault copy
2. While the summary streams, `touch` 20 vault files once a second for 12s (drives
   `VaultFileWatcher` → index refresh → `notoSearchIndexDidChange` → `model.refresh()`)
3. **Expected:** the prose summary completes
4. **Actual:** completed — multi-paragraph AI summary, 79 results

### 2. A genuinely new query, or the same query over a changed note set, still summarizes
- [x] Verified in unit test
- [x] Verified in simulator

**Unit tests:** `NEW` — `newQueryStartsASummary`, `changedResultSetStartsASummary`,
`idleAndFailedStatesAlwaysStart`

**Simulator verification:** consecutive searches (`productivity`, `startup ideas`,
`writing habits`, `artificial intelligence`, `health routine`, `money`) each produced a fresh
AI summary; log capture showed zero `summary route failed` entries.

### 3. A fallback states its cause
- [x] Verified in unit test
- [ ] Verified in simulator — **not** verified on screen

**Unit tests:** `NEW` — `httpStatusesMapToActionableReasons`,
`networkAndProtocolErrorsMapToActionableReasons`

**Why not simulator-verified:** forcing a remote failure needs an invalid key or an
unreachable base URL, and the settings sheet is only reachable *from* the fallback UI. The
reason mapping is unit-tested and the provenance string is a single concatenation, but the
rendered line has not been photographed. Bug 027 has prior simulator evidence that the
offline path renders (`offline-fallback.jpg`).

## Investigation Log

### Attempt 1 — reproduce the fallback

**Hypothesis:** the OpenRouter route is failing (region block, rate limit, provider error).
**Changes:** none. Ran six varied searches under `start_sim_log_cap`.
**Result:** Not reproduced — all six returned AI summaries, no `summary route failed` in the
log. Ruled out a persistently broken route and pointed at something environment-dependent.

### Attempt 2 — read the cancellation path

**Hypothesis:** the summary is being cancelled rather than failing.
**Changes:** the two listed under **Fix**.
**Result:** Confirmed by code path and by the churn test above. `refresh()` cancelled the
summary on every index notification; the notification rate is high exactly when the vault is
still filling, which is the reported device condition.

## Related

- Bug 030 (Noto 2 search index starved on device) is the *same underlying condition* seen from
  a different angle: an index that never settles. Fixing 030's indexing will also reduce the
  notification churn that caused this.
- Bug 027 introduced the offline fallback this bug was mistaking for a failure.
