# Feature: Keyboard Toolbar (Indent/Outdent)

## User Story

As a note writer, I want indent and outdent buttons above the keyboard so I can quickly adjust list nesting depth without manually typing spaces.

## User Flow

1. User opens a note and taps to edit
2. Keyboard appears with a toolbar above it containing two buttons: Indent (→) and Outdent (←)
3. User places cursor on a bullet line (`- Item`)
4. User taps Indent → line becomes `  - Item` (nested one level)
5. User taps Outdent → line returns to `- Item`
6. Works on any line: plain text gets 2 spaces added/removed, bullets nest/unnest

## Success Criteria

- [x] Toolbar appears above keyboard with Indent and Outdent buttons
- [x] Indent adds 2 spaces at the beginning of the current line
- [x] Outdent removes up to 2 leading spaces from the current line
- [x] Outdent does nothing if the line has no leading spaces
- [x] Cursor position adjusts correctly after indent/outdent
- [x] Toolbar uses standard UIKit inputAccessoryView styling
- [x] All existing tests pass (53/53)

## Steps to Test in Simulator

1. Build and launch app
2. Open any note → tap to edit
3. Verify toolbar appears above keyboard with two buttons
4. Place cursor on a bullet line → tap Indent → verify 2 spaces added
5. Tap Outdent → verify spaces removed
6. Place cursor on a plain text line → tap Indent → verify 2 spaces added
7. On a line with no leading spaces → tap Outdent → verify nothing happens

## Bugs

_None yet._
