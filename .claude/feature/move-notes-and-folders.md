# Feature: Move Notes and Folders

## User Story

As a user, I want to move notes and folders between directories in my vault so that I can organize my notes.

## User Flow

1. (Data layer only — no UI in this iteration)
2. Call `store.moveNote(note, to: destinationURL)` or `store.moveFolder(folder, to: destinationURL)`
3. File/folder is moved on disk to the destination directory
4. Source store's items list is updated (item removed)
5. If filename conflicts, append `(N)` to disambiguate

## Success Criteria

- [x] `moveNote(_:to:)` moves a .md file to a different directory
- [x] `moveFolder(_:to:)` moves a folder to a different directory
- [x] Source store removes the item from its items list after move
- [x] Filename conflict: appends `(2)`, `(3)`, etc. to disambiguate
- [x] Moving a note preserves file content (frontmatter, body)
- [x] Moving a folder preserves all contents inside it
- [x] Moving to the same directory is a no-op (returns original item)
- [x] Moving creates destination directory if it doesn't exist

## Tests (all passing)

### Move Note (7 tests)
1. Move note to subfolder — file at destination, removed from source
2. Move note between subfolders
3. Filename conflict — appends `(2)`
4. Multiple conflicts — appends `(3)`, `(4)`
5. Same directory — no-op
6. Content preserved after move
7. Creates destination directory automatically

### Move Folder (3 tests)
8. Move folder with contents — folder and inner files preserved
9. Name conflict — appends `(2)`
10. Same directory — no-op

## Bugs

_None._
