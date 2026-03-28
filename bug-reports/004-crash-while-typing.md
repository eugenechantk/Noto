# Bug 004: Crash while typing in editor

## Status: FIXED — verified 2026-03-23

## Description

App crashed frequently while typing in an existing note. Crash point varied — sometimes mid-sentence, sometimes when typing `-` for a bullet.

## Success Criteria

- [x] Can type 30+ lines continuously without crash (verified on simulator)
- [x] Can create new lines with Enter without crash
- [x] All 53 existing tests pass
- [x] Visual formatting still renders correctly

## Root Cause

Two compounding issues introduced in the performance optimization:

1. **`backing.replaceCharacters` during `processEditing`**: The bullet replacement (`-` → `•`) mutated the NSMutableAttributedString's backing text during `processEditing`. Even with lines collected into an array first, the mutation could trigger nested editing cycles in the layout manager, causing crashes.

2. **Debounced `DispatchWorkItem` race condition**: The 300ms debounced save created a `DispatchWorkItem` that captured `[weak self]` and ran `self.text = content`. This triggered SwiftUI re-rendering asynchronously, which could call `updateUIView` → `load()` while the text storage was in an inconsistent state from an ongoing edit.

## Fix

1. **Removed bullet character replacement entirely**: Instead of replacing `-` with `•`, the raw marker character is shown and dimmed with `tertiaryLabel` color. No text mutations happen during formatting. `markdownContent()` simplified to just return `backing.string` (O(1), no enumeration needed).

2. **Removed debounced save**: Reverted to synchronous `textViewDidChange` since `markdownContent()` is now O(1). Added `isUpdatingText` guard to prevent `updateUIView` from re-loading content when the binding changes from our own save.
