# Bug 006: Opening a note crashes the TextKit2 app

## Status: INVESTIGATING

## Description

On the `claude/markdown-rendering-analysis-vQM5x` branch, tapping into a note document to open it crashes the app. The app should open the selected note and show its editor contents without terminating.

## Steps to Reproduce

1. Build and launch the `Noto` app from `claude/markdown-rendering-analysis-vQM5x` on an isolated iOS simulator.
2. Wait for the note list to appear.
3. Tap any existing note row to open it.
4. Observe the app crash instead of presenting the note editor.

## Root Cause

`TextKit2EditorView.makeUIViewController(context:)` called `loadText(_:)` before the controller's view hierarchy had created `textView`. `TextKit2EditorViewController.loadText(_:)` immediately dereferenced an implicitly unwrapped `UITextView`, which triggered a Swift runtime assertion during note opening.

## Success Criteria

### 1. Opening an existing note no longer crashes the app
- [ ] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — [TextKit2EditorLifecycleTests.swift](/Users/eugenechan/dev/personal/Noto/NotoTests/TextKit2EditorLifecycleTests.swift) → `loadTextBeforeViewLoadsIsDeferred`

**Simulator verification:**
1. Launch `Noto` on an isolated simulator with `--launch-options='-notoUseLocalVault true'`
2. Tap `Daily Notes`
3. Tap the existing `2026-04-03` note
4. Observe the editor screen
5. **Expected:** the app stays alive and shows the `note_editor` text area

### 2. Initial note content is still applied after deferred load
- [ ] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — [TextKit2EditorLifecycleTests.swift](/Users/eugenechan/dev/personal/Noto/NotoTests/TextKit2EditorLifecycleTests.swift) → `loadTextBeforeViewLoadsIsDeferred`

**Simulator verification:**
1. Launch `Noto` on an isolated simulator with `--launch-options='-notoUseLocalVault true'`
2. Open `Daily Notes`
3. Open the existing note
4. Inspect the loaded editor view
5. **Expected:** the note screen appears immediately with the correct editor container instead of a blank or crashed state

## Investigation Log

### Attempt 1

**Hypothesis:** the TextKit 2 note-open crash was caused by editor initialization running before the UIKit text view existed.
**Changes:** buffered pending text in `TextKit2EditorViewController` and `TextKit2EditorViewController` (macOS), then applied it in `viewDidLoad`; added a lifecycle regression test for calling `loadText` before `loadViewIfNeeded`.
**Result:** reproduced the crash on an isolated simulator, confirmed the crash report pointed to `TextKit2EditorViewController.loadText(_:)`, patched the lifecycle path, and verified the note opens successfully in Simulator.
