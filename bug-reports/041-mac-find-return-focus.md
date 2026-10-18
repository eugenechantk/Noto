# Closing Find loses document focus

Status: FIXED. Independent candidate19 runtime checks pass for both Escape and Done.

## Reproduce

1. Open search in the Mac workspace.
2. Search for text and open a result at its first match.
3. Close Find with Escape or Done.
4. Type without clicking the document.

Build13 closes the bar but keeps focus on the window. Typing does nothing. A click in the document restores typing.

## Cause and change

Removing the native query field does not restore the editor as first responder. The Mac TextKit controller now restores its document when Find changes from visible to hidden. It only acts in its active window.

## Evidence

Independent reproduction: `.codex/evidence/noto-mac-20261018-visual-design-verify/round-8-480/behavior-checks.json` and the Find focus probe captures.

Regression test: `MacDesktopKeyboardTests.closingFindRestoresEditorFocus`.

Final proof: `.codex/evidence/noto-mac-20261018-visual-design-verify/round-10-candidate19-480/behavior-checks.json` and the two Find input probe captures. Both routes accepted text without an editor click. Undo restored the disposable note. Desktop and Pricing remained byte-identical.

## Escape after search

Candidate30 at 480 points exposed a second case. Open a note through search, then open another search palette and close it. Find remains visible but unfocused. A second Escape did not close it.

The native Done button now has the cancel shortcut. Candidate31 independently verifies that the first Escape closes only search, then the next closes Find. Direct Find Escape and Done also return actual typing to the document. Three disposable input probes were undone. Original Move, Desktop, and Pricing files remain byte-identical.

Evidence: `.codex/evidence/noto-mac-20261018-visual-design-verify/round-19-candidate31-480-find/`, including `body-preservation.json`.
