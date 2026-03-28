# Bug 003: Remaining typing latency after incremental formatting fix

## Status: INVESTIGATING

## Description

Despite the incremental formatting fix (bug 002), typing still has perceptible latency on iPhone 13 Pro. Multiple O(n) operations still run on every keystroke.

## Steps to Reproduce

1. Open a note with 20+ lines of content
2. Type continuously
3. Observe lag between key press and character appearing

## Success Criteria

- [ ] No perceptible typing lag on iPhone 13 Pro equivalent simulator
- [ ] `markdownContent()` no longer called on every keystroke
- [ ] Per-keystroke work is O(1), not O(n)
- [ ] All 53 existing tests pass
- [ ] Visual verification: formatting still renders correctly

## Investigation Log

### Attempt 1

**Hypothesis:** Six remaining O(n) operations per keystroke:

1. `markdownContent()` enumerates all bullet markers to reverse `•` → `-` (O(n) on every keystroke)
2. `isFirstHeading()` scans from document start on every line format
3. `frontmatterEndOffset()` scans full text on every keystroke
4. `backing.string` copies the full string on access
5. `setActiveLine` triggers begin/endEditing even when line doesn't change
6. `MarkdownNote.titleFrom(content)` parses frontmatter on every keystroke
