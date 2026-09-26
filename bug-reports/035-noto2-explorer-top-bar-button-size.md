# Bug 035: Noto 2 explorer top-bar buttons do not match editor buttons

## Status: FIXED — independently verified 2026-09-26

## Description

The file explorer's custom Settings and More controls appeared at a different visual size from the note editor's native top-bar action. The explorer now uses native SwiftUI toolbar controls so sizing, grouping, hit targets, and Liquid Glass treatment come from the navigation system.

## Steps to Reproduce

1. Launch Noto 2 with a seeded vault.
2. Open Browse and observe the Settings and More controls in the root directory top bar.
3. Open a note and observe the More control in the note editor navigation bar.
4. Compare the visible glass circles and symbol scale.
5. **Observed:** the explorer controls do not visually match the editor control size.

## Root Cause

The explorer built its own safe-area top bar, custom glass shapes, and explicit sizing constants, while the editor used native navigation toolbar controls. Those separate implementations drifted in visible diameter, grouping, alignment, and backdrop behavior.

## Success Criteria

### 1. Explorer controls use native navigation toolbar geometry
- [x] Verified by source inspection
- [x] Verified in simulator

**Implementation:** Browse uses native `ToolbarItem` buttons and `Menu`; the custom glass container, size constants, and manual hit-target geometry were removed.

**Simulator verification:**
1. Launch Noto 2 and open Browse.
2. Capture the root explorer top bar.
3. Open a note and capture the editor top bar.
4. Compare the visible More circles.
5. **Expected:** nested Back/More and editor Back/More use the same native circular geometry; root Settings/More use the native iOS grouped treatment.

### 2. Explorer uses the editor-style seamless top fade
- [x] Verified by shared fade implementation
- [x] Verified in simulator

**Implementation:** Browse reuses `Noto2TopChromeFade` and hides the rectangular navigation-bar background through `NoteEditorNavigationBarBackdropVisibility`.

**Simulator verification:**
1. In Browse root, verify there is no hard separator beneath the system toolbar.
2. Open a folder and compare the top transition with the note editor.
3. **Expected:** root, nested folder, and editor content blend under the same soft fade without a rectangular seam.

## Investigation Log

### Attempt 1

**Hypothesis:** The explorer's custom 38-point glass circle diverges from the native navigation-toolbar geometry used by the editor.

**Changes:** None yet.

**Result:** Reproduced on the isolated iPhone 17 simulator. The explorer screenshot shows a 38-point visible circle inside each 44-point accessibility frame; the editor reference shows a 44-point visible circle. Evidence: `035-before-explorer-buttons.png` and `035-editor-button-reference.png`.

### Attempt 2

**Hypothesis:** Matching the editor's native 44-point visible diameter, 8-point control spacing, and 16-point edge insets will remove the visual size and alignment mismatch without shrinking the hit target.

**Changes:** Added shared explorer top-bar metrics, enlarged the visible glass circle from 38 to 44 points, changed control spacing from 10 to 8 points, changed horizontal insets from 8 to 16 points, and added a geometry regression test.

**Result:** PASS. Root Settings/More frames are 44×44 at x=290 and x=342. Nested Back/More frames are 44×44 at x=16 and x=342. These match the editor's visible More circle and navigation edge alignment. Evidence: `035-after-root-buttons.png` and `035-after-nested-buttons.png`.

### Attempt 3

**Hypothesis:** Using native SwiftUI toolbar items removes custom sizing drift entirely and lets the explorer inherit the same system button treatment as the note editor.

**Changes:** Replaced the explorer's custom top bar and glass controls with native toolbar items, removed custom sizing/glass code, and reused the editor-style top fade and hidden native backdrop.

**Result:** PASS. Independent audit verified the native root grouped Settings/More treatment, native nested circular Back/More geometry matching the editor, preserved New Note/New Folder actions, and no hard top-bar seam. Evidence: `.codex/evidence/20260925-235640-ios-visual-audit/evidence.md`.

## Final Summary

The mismatch came from maintaining a custom explorer toolbar alongside the editor's native toolbar. Browse now uses native SwiftUI navigation toolbar controls and the editor's seamless fade treatment. The Noto 2 suite passed 117/117 before the final path-helper cleanup, both app targets build, and the independent visual audit passed with runtime screenshots and interaction evidence.
