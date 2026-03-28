# Bug 002: Typing lag that worsens with document length

## Status: FIXED — verified 2026-03-23

## Description

Typing latency increased as document length grew. Each keystroke triggered a full-document reformat that scales linearly with content.

## Success Criteria

- [x] Typing feels instant — per-keystroke formatting is O(1) not O(n)
- [x] Existing formatting (headings, bullets, bold, italic, code) still renders correctly
- [x] Existing unit tests pass (53/53)
- [x] Visual verification on simulator confirms all formatting intact

## Root Cause

Three compounding performance issues:

1. **Double formatting per keystroke**: `processEditing` reformatted the entire document, then `textViewDidChangeSelection` called `setActiveLine` which reformatted the entire document again.
2. **O(n) full-document reformat**: Every keystroke reset all attributes on the full document, then re-parsed and re-formatted every line.
3. **Regex recompilation**: `NSRegularExpression` was created fresh inside `applyPattern` on every formatting pass.

## Fix

- **Incremental formatting**: `processEditing` now only reformats the edited paragraph and its immediate neighbors via `applyFormattingToRegion(around:)`. Full-document formatting only runs on initial `load()`.
- **Targeted `setActiveLine`**: Only re-formats the old and new heading lines (to toggle prefix visibility), not the entire document.
- **Pre-compiled regexes**: All `NSRegularExpression` instances are now static properties, compiled once.
- **Cached body attributes**: `bodyParagraphStyle` and `bodyAttributes` are static, not recreated per call.
