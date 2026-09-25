# Bug 034: Noto 2 editor top bar has a hard translucent edge

## Status: FIXED — VERIFIED

## Description

The Noto 2 note editor's translucent top bar ends at a visibly sharp horizontal boundary. It should blend into the editor content with the soft glass-to-background fade used by LFG's session top chrome.

## Steps to Reproduce

1. Launch Noto 2 on an iPhone simulator with a seeded vault.
2. Open Browse, navigate into a directory, and open a note.
3. Observe the transition between the translucent navigation region and the editor background.
4. **Failure:** a clear horizontal border marks where the translucent background ends instead of fading smoothly into the editor.

## Root Cause

`NoteScreen` let the iOS 26 system navigation-bar backdrop render above an editor that already extends behind the top safe area. The system backdrop ends as a rectangular material plane at the bar's lower boundary. LFG avoids that seam by hiding the system backdrop and drawing a full-width Liquid Glass layer whose mask and background-coloured scrim fade below the toolbar row. Noto 2 had neither part of that treatment.

## Success Criteria

1. The Noto 2 editor hides the rectangular system navigation backdrop on iOS 26 and replaces it with the same measured glass-and-scrim fade geometry used by LFG.
   - Unit: `NoteEditorTopChromeTests.matchesLFGFadeGeometryForStandardNavigationChrome` verifies the LFG stop positions and tail height.
   - Simulator: open the seeded long note and confirm there is no horizontal seam below the toolbar.
2. Invalid measured heights cannot produce invalid gradient stops.
   - Unit: `NoteEditorTopChromeTests.clampsNegativeChromeHeightAndKeepsStopsOrdered` verifies the defensive clamp.
   - Simulator: rotate/reopen the editor and confirm the fade remains stable.
3. Existing editor controls and behavior remain intact.
   - Unit: run the full Noto 2 test suite, including `NoteEditorOptionsTests`.
   - Simulator: confirm Back and More remain visible and tappable, then scroll the note underneath the fade.

## Investigation Log

### Attempt 1

**Hypothesis:** Noto 2 relies on the system navigation-bar material without LFG's full-width masked glass-and-scrim fade, so the system material terminates at a hard lower edge.

**Changes:** None yet.

**Result:** Confirmed in the isolated iPhone simulator. The editor content already extends under the navigation region; the sharp boundary belongs to the system navigation backdrop. Direct comparison with LFG confirmed its two-part fix: a masked full-width glass fade plus a hidden system backdrop.

### Attempt 2

**Hypothesis:** Porting LFG's fade geometry to the Noto theme and hiding the iOS 26 navigation backdrop will remove the seam without changing editor layout or controls.

**Changes:** Added a measured `NoteEditorTopChromeFade` overlay, background-coloured scrim, oversized glass mask, iOS 26 backdrop visibility modifier, and pure layout regression tests.

**Result:** Fixed and verified. `flowdeck test -s Noto2` passed all 111 tests. A fresh Noto 2 build was installed on the isolated iPhone 17 simulator, the vault was reseeded, and the long note was checked both at rest and after scrolling text directly underneath the toolbar. The glass now eases into the editor without a horizontal boundary. Back navigation and the More menu remained tappable; the menu exposed all expected actions and live counts.

## Evidence

- Before: `.codex/evidence/20260925-noto2-editor-top-bar-blend/before.jpg`
- After opening: `.codex/evidence/20260925-noto2-editor-top-bar-blend/after-open.jpg`
- After scrolling content beneath the toolbar: `.codex/evidence/20260925-noto2-editor-top-bar-blend/after-scrolled.jpg`
- More menu interaction: `.codex/evidence/20260925-noto2-editor-top-bar-blend/more-menu.jpg`
