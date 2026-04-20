# Bug 008: Bottom-bar New Note opens without edit focus

## Status: FIXED — verified 2026-04-20

## Description

Tapping the bottom-bar New Note button creates and navigates to a root note, but the editor opens without focus. The screen appears as a blank note with only `#`, which makes the action feel like it did not work.

## Steps to Reproduce

1. Launch Noto on iOS with a configured vault.
2. Open the root note list.
3. Tap the bottom toolbar New Note button.
4. Observe the editor.

## Root Cause

The bottom toolbar root-note creation path passed `isNew: false` when pushing/selecting the newly created note. `NoteEditorScreen` uses `isNew` to decide whether `TextKit2EditorView` should autofocus, so the editor opened with no active insertion point.

## Success Criteria

### 1. Bottom toolbar New Note creates a root note and focuses the editor
- [ ] Verified in unit test
- [x] Verified in simulator

**Unit test:** `N/A` — this is private SwiftUI navigation state and focus wiring. Covered by simulator verification.

**Simulator verification:**
1. Build and launch the app on the isolated simulator.
2. Seed the vault.
3. Tap the bottom toolbar New Note button from the root note list.
4. **Expected:** a new root note editor opens and the `note_editor` text area is focused.

### 2. Top-right directory toolbar keeps native toolbar composition
- [ ] Verified in unit test
- [x] Verified in simulator

**Unit test:** `N/A` — native toolbar composition is visual/platform behavior. Covered by build and simulator inspection.

**Simulator verification:**
1. Open the root note list.
2. Inspect the top-right actions.
3. **Expected:** Settings, New Note, and More are native `ToolbarItemGroup` actions, not a custom `HStack` toolbar component.

## Investigation Log

### Attempt 1

**Hypothesis:** The bottom toolbar creates the note but passes the wrong `isNew` flag into `NoteEditorScreen`.

**Changes:** None yet.

**Result:** Reproduced in FlowDeck session `00EE4F9F-E46C-4F2C-9038-13DB15908724`. Tapping the visible bottom New Note control opened a root editor, but the `note_editor` text area was not focused.

### Attempt 2

**Hypothesis:** Marking bottom-bar-created notes as new will trigger the existing editor autofocus path. The directory top-right controls should also be moved from a custom `HStack` inside one toolbar item to a native `ToolbarItemGroup`.

**Changes:** Updated `createRootNoteAndPush()` and `createRootNoteAndSelect()` to pass `isNew: true`. Replaced the compact directory top-right custom `HStack` with `ToolbarItemGroup(placement: .navigationBarTrailing)`.

**Result:** Build passed. In FlowDeck session `92F888EC-5EC3-4387-9A7B-0A98EECB5D32`, the directory top-right actions render as a native toolbar group. Tapping bottom New Note opened a new root editor; typing `Test` immediately inserted text, confirming the editor had input focus.

## Final Summary

Bottom-bar-created notes were passed to the editor as existing notes, so the editor intentionally avoided autofocus. The fix marks root notes created from the bottom toolbar as new notes and replaces the compact directory top-right custom `HStack` toolbar with native `ToolbarItemGroup` composition.
