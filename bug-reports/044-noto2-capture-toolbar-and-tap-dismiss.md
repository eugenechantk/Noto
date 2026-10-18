# Bug 044: Noto 2 Capture lost its keyboard toolbar, and a tap on blank space does not dismiss the keyboard

## Status: FIXED — verified 2026-10-18

## Description

Reported by Eugene on TestFlight 0.2.0 (screenshot: keyboard up, no toolbar above it).

1. The Capture editor shows no keyboard toolbar. Before 0.2.0 it showed the floating
   glass pill (todo, indent, outdent, formatting, image, hide keyboard).
2. There is no way to dismiss the keyboard by tapping. A tap on the blank space outside
   the card (for example the gap between the card and the keyboard) does nothing.

Expected: the floating toolbar is back, and a tap anywhere outside the card and the
toolbar hides the keyboard.

## Steps to Reproduce

1. Launch Noto 2. Capture opens and focuses the editor; the keyboard appears.
2. Observe: no toolbar above the keyboard.
3. Tap the blank area between the card's bottom edge and the keyboard.
4. Observe: the keyboard stays up.

## Root Cause

1. Commit `f704b3a` (0.2.0 redesign) changed the Capture editor from
   `keyboardToolbarStyle: .floating` to `.hidden`, following a brief line "No formatting
   toolbar: you write Markdown". `.hidden` sets `inputAccessoryView = nil`, so the
   toolbar — including its hide-keyboard button — disappeared. Eugene now wants it back.
2. `CaptureScreen.content` never had a tap-to-dismiss target. The blank area only carries
   the card's swipe `DragGesture`, so a tap there has no handler.

## Success Criteria

### 1. The Capture editor shows the floating glass toolbar above the keyboard
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `Noto2Tests/CaptureActionsTests.swift` → `captureEditorKeepsTheFloatingToolbar`

**Simulator verification:** launch Noto 2 → Capture focuses the editor → the pill
(todo, indent, outdent, strikethrough, link, image, hide keyboard) sits above the
software keyboard. Evidence: `044-evidence/01-launch-keyboard-up.png`.

### 2. A tap on blank space outside the card hides the keyboard
- [ ] Verified in unit test (pure gesture wiring; no unit seam)
- [x] Verified in simulator

**Simulator verification:** with the software keyboard up, tap the gap between the card
and the toolbar (200, 460) → keyboard and toolbar go away, the card grows, and the swipe
hint returns. Evidence: `044-evidence/02-after-blank-tap.png`. Also passes below the card
in hardware-keyboard mode (200, 700): `04-blank-tap-hardware-kb.png`.

### 3. Inverse: a tap inside the card keeps the editor focused
- [x] Verified in simulator

Typed "Tap test thought", tapped inside the card → the editor stays first responder
(the system edit menu appears; toolbar still up). Evidence: `03-tap-inside-card-keeps-keyboard.png`.

### 4. Inverse: the toolbar's own hide-keyboard button works
- [x] Verified in simulator

Tapped the keyboard glyph at the right of the pill → toolbar gone. Evidence: `06-toolbar-hide-button.png`.

### 5. Inverse: a swipe that starts in the blank area still files the capture
- [x] Verified in simulator

Swipe up from (200, 700) to (200, 300) → "Filed to Inbox" toast, Inbox badge 1,
`inbox/2026-10-18-c863ec3f.md` contains the text. Evidence: `07-swipe-from-blank-files.png`.

### Regression suite
Full `Noto2Tests`: 203/204 on the first run. The one failure,
`FilingKeyboardLayoutTests.addSearchStaysAboveKeyboardAfterDismissingFloatingEditor`,
passes on its own (8/8) but fails in every full-suite run. **Correction (later the same
day):** it is not caused by hardware-keyboard mode, as first guessed. It fails the same way on
commit 417a351, before any of this work, so it is a pre-existing test-order failure, unrelated
to this fix.

## Investigation Log

### Attempt 1

**Hypothesis:** see Root Cause — both are direct code facts, not inferences.
**Changes:** restore `.floating` for the live Capture editor (the context-menu preview
stays `.hidden`); add a hit-testable background layer behind the card that resigns the
first responder on tap. The card sits above it, so taps inside the card never reach it.
**Result:** Fixed. All five criteria pass in the simulator (iPhone 17 Pro, iOS 26.3).

## Summary

The 0.2.0 redesign set the Capture editor's toolbar to `.hidden`, which also removed its
hide-keyboard button, and Capture never had a tap target outside the card. The fix restores
`.floating` (pinned by a unit test) and adds a clear background layer behind the card whose
tap resigns the first responder. Swipes from the blank area still reach the card's drag gesture.
