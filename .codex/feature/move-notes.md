# Feature: Move Notes

## User Story

As a Noto user, I want to move a note to another directory in my vault so that I can reorganize notes after creation.

## User Flow

1. iOS/iPadOS: Open a note, tap More, choose Move Note, pick a destination folder, and confirm the move.
2. macOS: Open a note, choose More > Move Note, pick a destination folder, and confirm the move.
3. macOS: Drag a note row in the sidebar onto a folder row to move the note into that folder.

## Success Criteria

- [x] More menus on iOS/iPadOS and macOS include a Move Note action.
- [x] The move destination picker includes the vault root and nested folders.
- [x] Moving keeps the note open and updates its path/breadcrumb/selection state.
- [x] Moving to an existing filename destination uses the store's conflict handling.
- [x] macOS sidebar note rows can be dragged onto folder rows to move notes.

## Test Strategy

- Reuse existing `MarkdownNoteStore` move tests for filesystem conflict and preservation behavior.
- Add Swift tests for reusable destination loading and drag payload validation.
- Build with FlowDeck and run relevant package/app tests.

## Tests

- `Packages/NotoVault`: existing move-note tests cover filesystem moves, destination creation, and filename conflicts.
- `NotoTests/NoteEditorSessionTests.swift`
  - `moveNoteFlushesPendingEditsAndUpdatesSessionFileURL` covers flushing editor edits before moving and updating the live session note URL.

## Implementation Details

- `NoteEditorScreen` presents a shared move destination picker from the platform More menu.
- `NoteEditorSession.moveNote(to:)` cancels pending background writes, persists dirty editor text, moves the file through `MarkdownNoteStore`, and updates the live note.
- `NotoSplitView` and compact iOS history now follow moved-note URLs so selection and breadcrumbs stay correct.
- `NotoSidebarView` adds macOS-only note drag providers and folder drop targets.

## Residual Risks

macOS drag/drop compiles, but AppKit drag gestures were not manually exercised in this pass.

## Bugs

_None yet._
