# Bug 028: Noto 2 cold launch delays Quick Capture

## Status: FIXED — verified 2026-08-26

## Description

Noto 2 does not become usable on the Quick Capture tab immediately after a cold launch. Quick Capture should render and accept input before Browse, Search, indexing, and vault-wide observation work begins.

## Steps to Reproduce

1. Install a Release build of Noto 2 on an isolated iPhone simulator.
2. Configure and seed its local vault.
3. Terminate Noto 2 so the next launch creates a fresh process.
4. Launch Noto 2 and measure from launch request to the visible, editable Quick Capture surface.
5. Observe startup work and the first usable frame.

## Root Cause

`RootTabView.init` constructed `VaultController` before SwiftUI could build the Capture tab. `VaultController` immediately began a user-initiated root-vault enumeration. Once the root appeared, `RootTabView` also started file watching and search-status polling, then its startup task replayed the search queue, synchronously enumerated the root a second time, and swept the search index. For external vaults, `VaultLocationManager` also resolved the security-scoped bookmark and performed a write probe synchronously during app initialization. None of that work is required to display or type into Quick Capture.

The fix allows Capture to render from its durable local draft while an external vault bookmark resolves asynchronously. The Browse/Search controller is created without root autoload after a three-second launch window or immediately when either dependent tab is selected. Browse loads its root on demand. Search maintenance and file watching start once, at utility priority, after the same trigger. Search-index status polling now runs only while Search is visible.

## Success Criteria

### 1. Cold launch presents an editable Quick Capture before vault-wide services start
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `Noto2Tests/Noto2StartupTests.swift` → `captureDoesNotRequireWorkspace`

**Simulator verification:**
1. Install the Noto 2 Release build on the isolated iPhone simulator.
2. Terminate Noto 2 before every sample.
3. Start FlowDeck UI capture, then cold launch Noto 2.
4. Find the first accessibility snapshot containing `note_editor` and verify the editor accepts input.
5. **Result:** five Release launches reached the milestone in 1,166, 943, 605, 893, and 529 ms: median 893 ms, down from 987 ms (94 ms / 9.5%).

### 2. Creating Noto 2's shared workspace does not enumerate the root until Browse needs it
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `Noto2Tests/Noto2StartupTests.swift` → `vaultControllerCanDeferRootEnumerationUntilBrowseNeedsIt`

**Simulator verification:**
1. Cold launch on Capture with the 3,000-note vault.
2. Tap Browse.
3. Wait for the root note/folder list to appear.
4. **Expected:** Capture launches independently; Browse still loads the seeded root on demand.

### 3. Search initializes on demand and remains usable
- [x] Verified in existing/full Noto 2 test suite
- [x] Verified in simulator

**Unit test:** `EXISTING` — `Noto2Tests/SearchIntegrationTests.swift`

**Simulator verification:**
1. Cold launch on Capture.
2. Tap Search.
3. Enter a seeded-note query after indexing becomes available.
4. **Expected:** Search initializes and returns seeded results; no startup-only dependency was removed.

## Investigation Log

### Attempt 1

**Hypothesis:** Noto 2 eagerly constructs vault-wide Browse/Search dependencies and starts indexing/file-observation work from `RootTabView`, although Quick Capture only needs the vault URL and editor.

**Changes:** None. Establishing the cold-start baseline first.

**Result:** Five local-vault Release launches reached the visible, keyboard-ready `note_editor` in 987, 1,131, 594, 1,006, and 642 ms: median 987 ms, range 594–1,131 ms, mean 872 ms. Measurement used FlowDeck's `LAUNCH_APP` timestamp and the first UI-session accessibility snapshot containing `note_editor`; effective capture cadence was roughly 0.4–0.5 seconds, so the result is a coarse simulator comparison rather than a production launch metric.

### Attempt 2

**Hypothesis:** Removing controller construction and all root enumeration from the Capture launch path will reduce contention and make startup independent of vault size.

**Changes:** Added a non-autoloading `VaultController` mode; made Noto 2's workspace, file watcher, index maintenance, and search-status polling lazy/deferred; moved external bookmark resolution and its write probe off the app-initialization path; added startup regression tests.

**Result:** Five equivalent Release launches reached `note_editor` in 1,166, 943, 605, 893, and 529 ms: median 893 ms, range 529–1,166 ms, mean 827 ms. The median improved by 94 ms (9.5%). The full Noto 2 suite passed 26/26. With 3,000 seeded notes, Capture accepted text and deferred Browse/Search both loaded successfully; Search reported all 3,000 notes indexed and returned the seeded query.

The attempted large-vault cold-launch comparison was discarded because `flowdeck run` reinstalled the app and rotated its data container before the measurement. The 3,000-note run is therefore recorded only as functional workload validation, not as benchmark evidence.

An independent simulator audit passed cold launch, immediate typing, deferred Search, and deferred Browse. Evidence is in `.codex/evidence/20260825-1814-ios-visual-audit/`.
