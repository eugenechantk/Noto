# Inbox selects a removed capture after Undo

Status: FIXED. Candidate26's native recheck selects an existing Inbox row after capture Undo.

## Reproduce

In candidate22, open Inspector, switch to Capture, file a draft, then Undo. Enter Inbox before the list snapshot refreshes. The deleted capture can remain selected without a matching row. Its card says “Downloading from iCloud…” and disables actions.

## Cause and change

The library snapshot refreshes after a short delay. Selection trusted that snapshot after a known deletion. Pending removals now disappear from visible rows immediately. Refresh also reconciles Inbox selection. Undo restores a discarded row, while refiling an undone draft unhides its path. Removing a capture that is open in the editor suppresses its final save, preventing recreation.

## Evidence

Independent reproduction: `.codex/evidence/noto-mac-20261018-visual-design-verify/round-11-candidate22-880/inspector-capture-inbox-sequence.jpg` and its AX record.

The Mac capture regression test now refreshes the snapshot before Undo, enters Inbox immediately, and verifies that refiling makes the note visible again.

The 31-check Mac regression suite passes. Independent candidate26 checks cover Inspector → Focus → Capture → File → Undo → Inbox. The list remains present, selection points to an existing row, and the card keeps its normal height. No download spinner appears. Evidence: `.codex/evidence/noto-mac-20261018-visual-design-verify/round-12-candidate26-1440/capture-undo-inbox-sequence.jpg` and its AX record.
