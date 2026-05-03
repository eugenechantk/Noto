# Feature: Unified Crash-Safe Indexing Queue

## User Story

As a Noto user, I want every change to a note (in-app create, edit, rename, move, delete, and Readwise import) to land in the search index reliably and survive an app quit mid-indexing, so the mention menu and search find new documents the next time I look — not "eventually, after the file watcher and vault enumerator catch up."

## User Flow

1. Make a change in any way that adds, edits, renames, moves, or deletes a `.md` file in the vault: in-app create, in-app edit, in-app rename/move, in-app delete, or Readwise sync writing capture files.
2. Search for the changed note by typing a query in `@`-mention or the search panel.
3. The new/updated/removed state appears in results immediately for the immediate paths, or within ~900 ms for the editor-debounced path.
4. If the app quits at any point during indexing — including after the file write but before the index commits — the next launch indexes everything that was in flight before doing anything else.

## Success Criteria

- [x] All write sites (`createNote`, `save`, `renameFileIfNeeded`, `moveNote`, `deleteNote`, Readwise per-URL) call exactly one of two unified entry points: `SearchIndexCoordinator.refresh(vaultURL:fileURL:)` (immediate) or `scheduleRefresh(vaultURL:fileURL:)` (debounced). MarkdownNoteStore continues to use the existing `refreshFile`/`scheduleRefreshFile`/`replaceFile`/`removeFile` shims, which now pass through to the queue-backed methods.
- [x] Every entry sits in `pending-index.json` from before the SQLite call until after commit. Implemented via `runQueued` in `SearchIndexCoordinator` — enqueue → run → consume.
- [x] An entry interrupted by a crash is replayed by `drainPendingQueue(vaultURL:)` at next launch and indexed correctly. Verified by `drainReplaysQueuedEntriesFromDiskAfterCrash` in `SearchIndexCoordinatorTests` and `crashSimulationDrainReplaysQueuedAction` in `PendingIndexQueueTests`.
- [x] `MainAppView.task` calls `drainPendingQueue` BEFORE the whole-vault sweep. Also added on `scenePhase == .active`.
- [x] `MainAppView.onChange(of: fileWatcher.changeCount)` routes a known `lastChangedFileURL` to `refresh(vaultURL:fileURL:)`; nil falls back to the existing whole-vault sweep.
- [x] `SourceNoteSyncResult` and `SourceLibrarySyncResult` expose `writtenURLs: Set<URL>` covering each non-deleted book/document. Verified by `syncReportsWrittenURLsForEveryNonDeletedBook` and `dryRunSyncReportsNoWrittenURLs`.
- [x] `ReadwiseSyncController` enqueues each `result.writtenURLs` entry via `refresh(vaultURL:fileURL:)` after a successful sync. Verified by `syncFansEveryWrittenURLToTheSearchIndex` using a `ReadwiseSyncIndexRefresher` probe.
- [x] Editor-save debounce (900 ms) collapses 5 rapid calls into one indexer run, but each call leaves the URL in the queue immediately. Verified by `scheduledFileRefreshDebouncesRepeatedRequests` and `scheduledRefreshQueuesImmediately`.
- [x] Rename/move enqueues `.delete(oldURL)` then `.refresh(newURL)`; the index ends with the new row and no row at the old `relative_path`. Verified by `replaceRemovesOldFileThenRefreshesNewFile`.
- [x] All existing `swift test` suites in `Packages/NotoSearch` and `Packages/NotoReadwiseSync` pass. Final counts: NotoSearch 40/40, NotoReadwiseSync 30/30.
- [x] `flowdeck build` succeeds for `Noto-iOS` and `Noto-macOS`. Both rebuilt clean.

## Platform & Stack

- **Platform:** iOS + macOS (single codebase, app target uses both)
- **Language:** Swift
- **Key frameworks:** SwiftUI (app), SQLite (search index), `os.log` Logger, Swift Testing (`@Test` / `#expect`), Foundation (`FileManager`, atomic JSON writes)
- **Packages touched:**
  - `Packages/NotoSearch` — owns the queue + coordinator + indexer
  - `Packages/NotoReadwiseSync` — extended to expose `writtenURLs`
- **App-target shim:** `Noto/SearchIndexController.swift` re-exports the new methods; the app must not contain business logic.

## Steps to Verify

1. `cd Packages/NotoSearch && swift test` — must pass with new `PendingIndexQueue` + `SearchIndexCoordinator` tests.
2. `cd Packages/NotoReadwiseSync && swift test` — must pass with the new `writtenURLs` test.
3. `flowdeck build` — Noto-iOS builds clean.
4. `flowdeck build --scheme Noto-macOS -S none` — Noto-macOS builds clean.
5. (Optional, owner-driven) Run macOS app, perform a Readwise sync, confirm new captures show in `@`-mention immediately. Quit mid-sync, relaunch, confirm the dropped files index on next launch via the queue drain.

## Implementation Phases

### Phase 1: PendingIndexQueue (foundation)

- Scope:
  - New `Packages/NotoSearch/Sources/NotoSearch/PendingIndexQueue.swift` — actor with `enqueue(_:)`, `consume(_:)`, `pending() -> [PendingIndexEntry]`, `drain(handler:)`. Persists `[PendingIndexEntry]` to `<indexDir>/pending-index.json` via atomic write.
  - `PendingIndexEntry`: `{ id: UUID, url: URL, action: .refresh | .delete, queuedAt: Date }`. Codable.
- Success criteria covered: durability for all subsequent phases.
- Verification gate: `swift test --filter PendingIndexQueue` covers enqueue/consume/persist/load/atomic-write/concurrent-enqueue/crash-replay.

### Phase 2: SearchIndexCoordinator unification

- Scope:
  - Update `SearchIndexCoordinator` so every per-URL operation flows through the queue: `refresh(vaultURL:fileURL:)`, `scheduleRefresh(vaultURL:fileURL:)`, `drainPendingQueue(vaultURL:)`. Mark old per-op methods (`refreshFile` / `scheduleRefreshFile` / `replaceFile` / `removeFile`) as thin shims OR delete in favor of the new entry points — whichever yields cleaner call sites.
  - Existing `refresh(vaultURL:)` (whole-vault sweep) untouched.
- Success criteria covered: unified entry points, queue lifecycle, drain semantics, debounce behavior.
- Verification gate: `swift test --filter SearchIndexCoordinator` covers refresh-queues-then-drains, scheduleRefresh-debounce, rename = delete+refresh, drain-from-disk-after-relaunch.

### Phase 3: App-target shim + write site routing

- Scope:
  - `Noto/SearchIndexController.swift` exposes the new methods.
  - `MarkdownNoteStore` rewires its private helpers (`refreshSearchIndexFileImmediately`, `scheduleSearchIndexRefresh`, `replaceSearchIndexFile`, `removeSearchIndexFile`) to the new coordinator API.
  - `MainAppView.task` runs `drainPendingQueue` before the existing sweep.
  - `MainAppView.onChange(of: fileWatcher.changeCount)` consults `fileWatcher.lastChangedFileURL` to route per-URL when available.
- Success criteria covered: every in-app write path goes through the queue.
- Verification gate: app builds clean (iOS + macOS); existing `NotoTests` pass.

### Phase 4: Readwise integration

- Scope:
  - Extend `SourceNoteSyncResult` (and `SourceLibrarySyncResult` convenience) to carry `writtenURLs: Set<URL>`. Track URLs in `SourceNoteSyncEngine.sync(books:)` and `syncReaderDocuments(...)` after each successful `markdown.write(to:)`.
  - `ReadwiseSyncController` iterates `result.writtenURLs` after a successful sync, enqueuing `refresh(vaultURL:fileURL:)` for each.
- Success criteria covered: Readwise imports go through the same queue as in-app changes.
- Verification gate:
  - `swift test` in `Packages/NotoReadwiseSync` covers `sync(books:)` returning `writtenURLs`.
  - `swift test` (NotoTests) covers `ReadwiseSyncController` routing each URL through `SearchIndexController.refresh` via a fake runner.

## Bugs

_None yet._
