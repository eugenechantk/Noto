# Bug 001: First-level bullets not indenting 12px from left margin

## Status: FIXED — verified 2026-03-23

## Description

First-level bullet list items (`- Item`) were reported as not visually indented 12px from the left margin despite unit tests passing.

## Success Criteria

- [x] Level 1 bullets (`- Item`) visually indent 12px from the left text margin
- [x] Level 2 bullets (`  - Item`) visually indent 24px
- [x] Existing unit tests still pass (53/53)
- [x] Visual verification on simulator confirms the indent

## Root Cause

The indent attribute was correctly set at 12px (confirmed via runtime logging). The bullet regex was hardened to also match `•` (rendered bullet character) to protect against edge cases where re-formatting passes run after `-` has been replaced with `•`.

## Fix

- Updated bullet regex to match `[*\-•]` instead of `[*-]` in `MarkdownTextStorage.formatLine`
