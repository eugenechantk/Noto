# Bug 033: Noto 2 editor dock is not needed

## Status: FIXED — verified 2026-09-22

## Description

Noto 2's restored editor options currently include a bottom dock with Today, Search, and New Note. The corrected scope is the original editor's More-menu actions only; Noto 2 should not show or retain the dock.

## Steps to Reproduce

1. Launch Noto 2 with a configured vault.
2. Open Browse and select a note.
3. Observe the bottom of the note editor.
4. The Today, Search, and New Note dock is visible even though the corrected design does not include it.

## Root Cause

The initial feature inventory treated the original Noto editor dock as part of the requested options. The revised requirement excludes that chrome and its navigation routes.

## Success Criteria

### 1. Noto 2 exposes only the restored More-menu actions
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `MODIFIED` — `Noto2Tests/NoteEditorOptionsTests.swift` → `exposesEveryRequestedEditorOption()`

**Simulator verification:**
1. Build and launch Noto 2 on the isolated simulator.
2. Seed the Noto 2 vault and open a note from Browse.
3. Confirm no bottom editor dock is visible.
4. Open More and confirm Search in Note, Properties, Move Note, Delete Note, and word/character counts remain available.

### 2. Dock-only routing and components are removed
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `MODIFIED` — the exact option-inventory test excludes Today, vault Search, and New Note.

**Simulator verification:** The editor has no Today, Search, or New Note dock controls to invoke.

## Investigation Log

### Attempt 1

**Hypothesis:** The dock can be removed without touching editor-session or More-menu behavior because its callbacks are separately threaded through Noto 2 navigation.
**Changes:** Removed the shared Noto 2 dock view, its editor modifier, Today/Search/New Note option cases, route types, and callback plumbing through Browse, Search, and the root tab view.
**Result:** The Noto 2 build and full 97-test suite pass. Isolated-simulator inspection confirms the editor has no bottom dock and the restored More menu remains intact.

## Final Summary

The dock came from an overly broad initial option inventory. Noto 2 now restores only Search in Note, Properties, Move Note, Delete Note, and word/character counts; no dock-only code remains.
