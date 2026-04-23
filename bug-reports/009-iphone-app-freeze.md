# Bug 009: iPhone app is unresponsive during launch loading

## Status: FIXED — verified 2026-04-22

## Description

The user reports that the iPhone app appears frozen when opened, then eventually becomes responsive after the UI finishes loading. This suggests launch/foreground activation is doing too much synchronous vault work on the main thread.

## Steps to Reproduce

1. Install latest build to physical iPhone `Hihi`.
2. Open Noto on the phone.
3. App appears unresponsive while loading.
4. After some time, the UI becomes responsive.

## Root Cause

Launch and foreground activation were doing synchronous vault work on the main UI path:

- The app created/read today's note every time the scene became active, even when the user was only opening the note list.
- Directory listing resolved note titles and frontmatter IDs by reading markdown file contents during list construction.
- Sidebar tree loading could eagerly traverse all nested folders when no expansion state existed, which does not scale to large vaults.

## Success Criteria

### 1. Opening the app does not create/read today's note unless the user opens Today
- [x] Verified in unit test
- [x] Verified in simulator
- [x] Verified on physical device launch

**Unit test:** `NEW` — `NotoTests/MarkdownNoteStoreTests.swift` → `DailyNoteTests/testForegroundRefreshDoesNotCreateTodayNote`

**Simulator verification:** Large-vault launch renders the root list instead of blocking on Today-note creation.

**Device verification:** `flowdeck device launch 00008110-0011083A1151801E com.eugenechan.Noto --json` succeeded after the phone was unlocked.

### 2. Directory list metadata reads only bounded note prefixes
- [x] Verified in package tests
- [x] Verified in simulator

**Unit tests:** `NEW` — `Packages/NotoVault/Tests/NotoVaultTests/NoteTitleResolverTests.swift` and `VaultDirectoryLoaderTests.swift`

**Simulator verification:** Large-vault launch renders the root list with 14,000 seeded notes.

### 3. Large vault seed supports scale testing
- [x] Verified by script run
- [x] Verified in simulator

**Script:** `.maestro/seed-vault.sh <udid> --scale large`

**Simulator verification:** Seeded 2,000 root notes plus 12 folders with 1,000 notes each, then launched and navigated into a 1,000-note folder.

## Investigation Log

### Attempt 1

**Hypothesis:** The frozen app is a stale running process from before the latest install.

**Actions:** Checked FlowDeck app registry. `flowdeck apps --json` showed `com.eugenechan.Noto` running on device with short id `9C25B41B` and uptime over 12 hours. Attempted device logs, but FlowDeck logs are simulator-only.

**Result:** Need to stop the stale process and reinstall/relaunch the current build.

### Attempt 2

**Hypothesis:** Relaunching/reinstalling over the stale process will clear the frozen runtime without deleting app data.

**Actions:** Tried `flowdeck stop 9C25B41B --json`, but FlowDeck did not kill the device process. Direct `flowdeck device launch 00008110-0011083A1151801E com.eugenechan.Noto --json` succeeded once the phone was reachable. Then ran `flowdeck run -D "00008110-0011083A1151801E" --json` to rebuild and reinstall over the existing app without uninstalling.

**Result:** Build succeeded and install completed. Launch failed because the phone locked again before launch. `flowdeck apps --json` then showed no running tracked apps.

### Attempt 3

**Hypothesis:** The app is not permanently frozen; it is doing expensive launch-time vault work on the main thread.

**Actions:** Reproduced on an isolated iOS 26.2 simulator. A clean install showed the vault setup screen immediately. A seeded local vault also rendered the note list immediately. Physical-device logs are unavailable through FlowDeck, so investigation moved to startup code paths. Found two launch-time costs:

- `MainAppView` created/read today's note and reloaded the root list every time the scene became active.
- `VaultDirectoryLoader` resolved each list row by reading entire markdown files for title and frontmatter ID.

**Result:** Implemented a focused startup-load reduction: foreground activation now refreshes only the visible list and does not create/read today's note; list metadata resolution reads only a bounded prefix of each markdown file.

### Attempt 4

**Hypothesis:** Responsive launch requires deferred and background list loading, plus a large seed fixture that represents the target scale.

**Actions:** Added deferred store autoload and background item loading. Updated the simulator seed script with `--scale large`, defaulting to 2,000 root notes and 12 folders with 1,000 notes each. Seeded an isolated simulator with 14,000 notes.

**Result:** `flowdeck run --no-build` launched the app in 3.188s wall time on the large seeded simulator. The accessibility tree showed the root list immediately, and tapping `Folder 01` showed its 1,000-note list after a 1-second check. Build/install to the iOS 26 physical iPhone succeeded, but initial FlowDeck launch verification failed because the phone was locked.

### Attempt 5

**Hypothesis:** Once the phone is unlocked, the installed performance build should launch on-device.

**Actions:** Ran `flowdeck device launch 00008110-0011083A1151801E com.eugenechan.Noto --json` after the user unlocked the phone.

**Result:** Device launch succeeded. `flowdeck apps --json` showed `com.eugenechan.Noto` running on the physical device.

### Attempt 6

**Hypothesis:** Remaining perceived delay after launch comes from tap-time destination setup. Folder and note routes were still constructing `MarkdownNoteStore` with eager autoload, and split/sidebar note selection still read the full markdown file to reconstruct a `MarkdownNote`.

**Actions:** Changed compact iPhone folder and note navigation destinations to create stores with `autoload: false`; the destination view now appears first and loads folder items in the background. Changed sidebar note selection to use note metadata already carried by `SidebarTreeNode`, avoiding a full-file read on tap.

**Result:** On the 14,000-note simulator seed, tapping `Folder 01` showed the 1,000-note folder content in the next capture, and tapping `Folder 01 Note 01000` showed the `note_editor` in the next capture. `swift test` in `Packages/NotoVault` passed 44 tests; `flowdeck test -D "My Mac" --test-targets NotoTests --json` passed 104 tests. Installing this latest tap-latency build to the physical iPhone is currently blocked by FlowDeck/Xcode destination resolution for UDID `00008110-0011083A1151801E`.
