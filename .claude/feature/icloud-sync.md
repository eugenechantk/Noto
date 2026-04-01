# Feature: iCloud Drive Sync

## User Story

As a user with multiple Apple devices, I want my notes to sync between my iPhone and Mac so that I can access and edit notes on either device.

## Design

**Approach:** Use iCloud Drive as the sync transport for markdown files. No custom sync server. The sidecar index (when it exists) is rebuilt per-device, not synced.

**Three changes required:**

1. **File coordination** — Wrap all file writes in `NSFileCoordinator` so iCloud Drive (and other file providers) can safely sync without data corruption.

2. **External change detection** — Use `NSFilePresenter` to watch the vault directory. When iCloud downloads new/updated/deleted files, reload the note list and refresh any open editor.

3. **Download on demand** — iCloud Drive may evict files to save space. When opening a note that isn't fully downloaded, trigger a download and show a loading state.

## Success Criteria

- [x] All file writes (save, create, delete, move, rename) use NSFileCoordinator
- [x] A VaultFileWatcher class monitors the vault and detects external changes
- [x] MarkdownNoteStore reloads items when external changes are detected
- [x] NoteEditorScreen reloads content when the current note is modified externally
- [x] Opening a not-yet-downloaded iCloud file triggers download with loading indicator
- [x] Existing tests continue to pass (no regressions) — 58/58 pass
- [x] New tests cover file coordination wrapper and download status checking — 13 new tests pass

## Steps to Test in Simulator

1. Build and launch app on simulator
2. Set vault to a local directory (iCloud Drive not available on simulator)
3. Verify all existing functionality still works (create, edit, delete, navigate)
4. External change detection can be tested by modifying files on disk while app is running

## Bugs

_None yet._
