# Bug 030: Can't dismiss keyboard on AI chat by scrolling up or tapping

## Status: FIXED — verified 2026-06-25

## Description

On the NotoChat (AI chat) sheet, once the composer keyboard is up, scrolling up
through the conversation or tapping the conversation did **not** dismiss the
keyboard. The user had to dismiss it some other way.

## Steps to Reproduce

1. Open the AI chat sheet on a conversation with messages.
2. Tap the composer field → software keyboard appears.
3. Scroll up through the chat to read earlier messages → keyboard stays up.
4. Tap anywhere in the conversation → keyboard stays up.
5. **Expected:** either gesture dismisses the keyboard.

## Root Cause

In `ChatSheet.swift` `messageList`:
- `.scrollDismissesKeyboard(.interactively)` only dismisses when the scroll is
  dragged **toward** the keyboard (downward). Scrolling **up** to read history
  left the keyboard up.
- There was deliberately **no** tap gesture on the message list (a plain
  `.onTapGesture` would consume taps and swallow citation-link taps), so tapping
  the conversation did nothing.

## Fix

In `Noto/Views/Chat/ChatSheet.swift` (`messageList`):
- `.scrollDismissesKeyboard(.interactively)` → `.scrollDismissesKeyboard(.immediately)`
  so any scroll drag (either direction) dismisses the keyboard.
- Added `.simultaneousGesture(TapGesture().onEnded { Self.dismissKeyboard() })`.
  A *simultaneous* tap fires alongside citation-link taps rather than consuming
  them, so links still work.

## Success Criteria

### 1. Scrolling the chat dismisses the keyboard
- [x] Verified in simulator

**Simulator verification:** Loaded a seeded multi-turn transcript, focused the
composer (keyboard up), swiped the conversation → keyboard dismissed.

### 2. Tapping the conversation dismisses the keyboard
- [x] Verified in simulator

**Simulator verification:** Re-focused composer (keyboard up), tapped a message
in the conversation → keyboard dismissed.

### 3. (Inverse) Citation links still open notes
- [x] Verified in simulator

**Simulator verification:** Seeded a transcript with a `[1]: Meeting Notes.md`
citation, tapped the SOURCES row → chat dismissed and Meeting Notes opened in the
editor. The simultaneous tap gesture did not swallow the link.

## Notes

- Verified on a dedicated iPhone 16 Pro / iOS 26.2 simulator with software
  keyboard forced on.
- This file also carried a concurrent, unrelated in-flight edit (composer
  `maxInputHeight`/`sheetHeight` growth cap). It was half-wired (call site +
  body referenced `maxInputHeight` but the struct lacked the property and
  `sheetHeight` was never measured). Completed the wiring at Eugene's request so
  the build compiled: added the `maxInputHeight` property to `ComposerView` and
  the `SheetHeightKey` preference measurement. Both changes build and run.
