# Bug 013: iPad launch dark screen crash

## Status: FIXED — verified 2026-05-02

## Description

On iPad launch, the app can appear to sit on a dark blank screen for a long time before the editor becomes functional. Expected behavior is that launch shows an explicit loading state while the restored note is being read, then transitions to the editor when content is available.

## Steps to Reproduce

1. Build and launch Noto on an isolated iPad simulator.
2. Observe the first visible screen after launch.
3. Wait for the app to finish startup tasks.
4. Failure point: the visible UI can stay dark or blank while the restored note is still loading.

## Root Cause

`VaultWorkspaceView` restores the last opened note immediately on iPad through `openInitialDocumentLinkOrRestore() -> restoreOrOpenToday() -> selectNote(...)`. `NoteEditorScreen` then renders `EditorContentView` while `NoteEditorSession.loadNoteContent()` runs asynchronously.

Before this fix, `EditorContentView` only showed special states for `downloadFailed` and `isDownloading`. While `session.hasLoaded == false` and `isDownloading == false`, it rendered `editorBody`, which has the app's dark editor background but no loaded note text yet. On a fast local read this is brief; on a slower iCloud/coordinated read it looks like a dark launch hang.

## Success Criteria

### 1. Restored note launch does not show a blank dark editor while content is still loading
- [x] Verified in build
- [x] Verified in simulator

**Verification:** Launch iPad simulator, restore/open a note, and confirm the app transitions into usable editor UI without crashing. Slow note loads should show explicit loading UI instead of an empty editor body.

## Investigation Log

### Attempt 1

**Hypothesis:** The iPad regular-size-class split-view launch path is crashing during startup.
**Changes:** None.
**Result:** On iPad mini simulator, cold relaunch did not crash. FlowDeck captured home screen at 13:46:53.961, launch screen at 13:46:54.858, and loaded editor UI at 13:46:55.626. Runtime log showed AttributeGraph cycle warnings and `NSMapGet` warning, but no process crash.

### Attempt 2

**Hypothesis:** The perceived dark screen is the editor's dark background rendering before the restored note content has loaded.
**Changes:** Added an explicit `Loading note...` state while `session.hasLoaded == false`.
**Result:** FlowDeck iPad simulator build succeeded. Relaunch on iPad mini simulator reached the restored editor without crashing. The local simulator read is fast, so the loading state is brief/not visible in the final screenshot; the blank-dark branch has been removed from the view logic.
