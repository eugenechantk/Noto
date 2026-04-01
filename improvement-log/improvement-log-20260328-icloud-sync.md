# Improvement Log — Session 20260328-icloud-sync

## Tracker

- [ ] 2026-03-28 — Created redundant CoordinatedFileManagerTests when existing store tests already covered the same operations

## Log

### 2026-03-28 — Created redundant CoordinatedFileManagerTests
**What happened:** Created a 13-test file for CoordinatedFileManager that tested read/write/delete/move/directory/download status — all operations already exercised by the 58 existing MarkdownNoteStoreTests. Eugene caught the duplication.
**Why this was wrong:** CoordinatedFileManager is an internal implementation detail of MarkdownNoteStore. The store tests already serve as integration tests for the coordinator. Adding unit tests for the wrapper was redundant — it tested the same filesystem operations at a lower level with no additional coverage.
**What better looks like:** Before writing new tests, check whether existing tests already cover the code path. When refactoring internals (swapping FileManager for CoordinatedFileManager), the right test strategy is to verify existing tests still pass, not to add a parallel test suite for the new abstraction.

### 2026-04-01 — Tried 2 broken approaches for macOS window restoration before researching
**What happened:** Tried `WindowGroup(id:)`, then `NSWindow.setFrameAutosaveName` via NSViewRepresentable, then `applicationShouldHandleReopen` — none worked for the hide/reopen-on-dock-click case. Only after the user told me to research did I find the correct pattern (hide-on-close via `windowShouldClose` returning false).
**Why this was wrong:** I was guessing at platform behavior instead of researching the established macOS pattern. Two failed attempts wasted time.
**What better looks like:** After the first failed attempt at a platform-specific behavior, stop and research via web search. Platform APIs (especially macOS window management) have specific correct patterns that aren't deducible from SwiftUI docs alone.
