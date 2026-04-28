# Feature: Ownership Rearchitecture

## Goal

Refactor Noto's vault, navigation, editor, and search ownership into a simpler architecture without breaking existing behavior.

Target model:

```text
MainAppView owns app runtime.
VaultWorkspaceView owns workspace navigation.
VaultController owns app-facing vault operations.
SearchIndexController owns app-facing search-index lifecycle.
NoteEditorSession owns one open note's editing lifecycle.
NotoVault and NotoSearch own platform-neutral mechanics.
```

Source brainstorms:

- `.codex/brainstorm/simplified-architecture.md`
- `.codex/brainstorm/vault-controller-rearchitecture.md`
- `.codex/brainstorm/view-hierarchy-refactor.md`
- `.codex/brainstorm/search-index-controller-refactor.md`
- `.codex/brainstorm/noto-architecture-lifecycle.md`

## Success Criteria

- Existing user-facing behavior remains unchanged during each phase.
- SwiftUI views stop reaching into raw file-manager or store details.
- `VaultWorkspaceView` becomes the single owner of workspace routing, search presentation, settings presentation, Today routing, and platform navigation shells.
- `VaultController` becomes the single app-facing interface for vault operations.
- `SearchIndexController` replaces app-target `SearchIndexRefreshCoordinator` naming and owns app lifecycle side effects.
- Non-UI filesystem/search mechanics move into `NotoVault` and `NotoSearch`.
- `NoteListView` and sidebar components become rendering surfaces that emit intents.
- `NoteEditorSession` stays note-scoped and delegates persistence side effects to `VaultController`.
- Each implementation phase has tests and E2E checks before the next phase begins.

## Non-Goals

- Do not redesign the UI.
- Do not rewrite the editor rendering engine.
- Do not change note file format, vault layout, search result semantics, or Readwise sync semantics.
- Do not delete compatibility wrappers until their replacements are adopted and verified.
- Do not combine unrelated cleanup with migration phases.

## Architectural Invariants

- UI surfaces emit intents; controllers execute them.
- Views should not use `FileManager`, `NSFileCoordinator`, raw URL mutation rules, or search-index internals directly.
- `NotoVault` must remain UI-free and platform-neutral where practical.
- `NotoSearch` must own search mechanics without SwiftUI, scene phase, or app notification knowledge.
- `VaultController` can compose services, but should not become a god object with all implementation details inline.
- `VaultWorkspaceView` owns navigation state, not persistence.
- `NoteEditorSession` owns editor-local state, not vault-wide list/search behavior.
- `TextKit2EditorView` owns text input, cursor, selection, native rendering, and keyboard/input chrome.

## Target Components

### VaultWorkspaceView

Owns workspace-level presentation and routing:

- compact iPhone `NavigationStack`
- iPad/macOS split selection
- note navigation history
- restore last-opened note
- Today route
- global search sheet
- settings sheet
- document-link routing
- bottom bar / workspace chrome

It receives intents from list, sidebar, search, and editor surfaces:

```text
openFolder
openNote
openToday
openSearch
openSettings
openDocumentLink
createNote
deleteItem
goBack
goForward
```

### VaultController

Owns app-facing vault operations:

- load root/folder contents
- create/read/save/rename/move/delete notes and folders
- open and prewarm daily notes
- resolve document links
- provide page mention candidates
- coordinate search queries through search services
- publish app-facing vault changes
- bridge to file watcher, note sync, and search-index refresh side effects

Internally it should compose repositories and services from `NotoVault`, `NotoSearch`, and app adapters.

### SearchIndexController

Owns app-runtime search index behavior:

- decide when refreshes happen
- call package-level `NotoSearch.SearchIndexCoordinator`
- post app notifications or observable state after refreshes
- connect saves, renames, deletes, watcher events, app startup, scene activation, and search sheet open to index maintenance

`NotoSearch.SearchIndexCoordinator` should own the package-level mechanics:

- single-flight full refresh
- debounced file refresh
- replace/remove file refresh behavior
- cancellation and task-key management
- follow-up refresh after a running full refresh

## Package Change Plan

This refactor moves real behavior out of the app target. The app should end up coordinating user intent and lifecycle, while packages own deterministic vault/search mechanics.

### NotoVault

Current useful package surfaces:

- `VaultDirectoryLoader`
- `SidebarTreeLoader`
- `VaultListItem`, `FolderSummary`, `NoteSummary`
- `NoteTitleResolver`
- `Frontmatter`
- `NoteFile`
- `WordCounter`
- older/simple `VaultManager`

Package changes needed:

- Add a package-level filesystem abstraction:
  - `VaultFileSystem` protocol for read/write/move/delete/create/list operations.
  - `CoordinatedVaultFileSystem` implementation that absorbs app-target `CoordinatedFileManager` behavior.
  - Keep iCloud/readability helpers close to this layer so app/editor code does not call them directly.
- Add repository/service layer:
  - `VaultRepository` for root/folder listing and note lookup.
  - `NoteRepository` for note read/create/save/rename/move/delete.
  - `FolderRepository` for folder create/move/delete and child enumeration.
  - `DailyNoteService` for date-based pathing, idempotent creation, and template application.
  - `AttachmentStore` for attachment import, stable destination paths, and relative markdown paths.
  - `VaultPathResolver` for vault-relative paths, document links, stable IDs, and URL containment checks.
- Move non-UI parts of `MarkdownNoteStore` into these services:
  - loading notes from file URLs
  - resolving notes by vault-relative path
  - resolving notes by frontmatter ID
  - filename/title rules
  - daily-note creation
  - folder and note move/delete mechanics
  - attachment import storage
- Define package result/error types that preserve current app behavior:
  - note not found
  - unreadable or provider-backed file
  - write denied
  - move/delete failed
  - conflict or stale file state where currently observable
- Keep app-only behavior out:
  - SwiftUI navigation
  - sheets/banners/toasts
  - scene phase
  - user-visible conflict presentation
  - `NotificationCenter` app events
  - `VaultFileWatcher` lifecycle ownership

Recommended package shape:

```text
Packages/NotoVault/Sources/NotoVault/
  VaultFileSystem.swift
  CoordinatedVaultFileSystem.swift
  VaultRepository.swift
  NoteRepository.swift
  FolderRepository.swift
  DailyNoteService.swift
  AttachmentStore.swift
  VaultPathResolver.swift
  VaultOperationTypes.swift
```

`VaultManager` should either be retired or reduced to a compatibility layer over the new repository/services. It should not remain the main package abstraction if it only models the older flat UUID-file vault.

### NotoSearch

Current useful package surfaces:

- `MarkdownSearchIndexer`
- `MarkdownSearchEngine`
- `MarkdownSearchDocumentExtractor`
- `SearchIndexStore`
- `SearchTypes`
- `SearchUtilities`

Package changes needed:

- Add `SearchIndexCoordinator` actor to own package-level async mechanics:
  - one running refresh per vault
  - scheduled/debounced file refresh
  - refresh file
  - remove file
  - replace file
  - follow-up single-file refresh after an overlapping full refresh
  - cancellation and task cleanup
- Keep `MarkdownSearchIndexer` as the lower-level synchronous indexer/store adapter.
- Add deterministic timing seams for tests:
  - injectable debounce duration
  - injectable sleep/clock if practical
  - injectable indexer factory so coordination tests do not need expensive real vault scans
- Keep app-only behavior out:
  - `.notoSearchIndexDidChange`
  - `NotificationCenter`
  - scene phase decisions
  - search sheet open decisions
  - UI-friendly loading/error state
- Optionally add small package result types if the app needs richer status:
  - refresh started/joined existing task
  - file refresh scheduled
  - refresh completed with stats
  - refresh skipped because file is outside vault or unavailable

Recommended package shape:

```text
Packages/NotoSearch/Sources/NotoSearch/
  SearchIndexCoordinator.swift
  SearchIndexCoordinatorTypes.swift
```

`SearchIndexController` in the app target should be thin: decide when to call this actor, then publish app-facing changes.

### App Target After Package Moves

The app target should retain only the platform/runtime pieces:

- `VaultController`
  - composes `NotoVault` repositories/services.
  - calls `SearchIndexController` after mutations.
  - exposes UI-facing async methods and observable state.
- `SearchIndexController`
  - wraps `NotoSearch.SearchIndexCoordinator`.
  - posts `.notoSearchIndexDidChange` or exposes observable state.
  - decides lifecycle triggers.
- `VaultFileWatcher`
  - remains app-owned unless later moved behind a narrow app adapter.
  - should call `VaultController` or `SearchIndexController`, not package internals directly.
- `MarkdownNoteStore`
  - temporary compatibility wrapper only.
  - should shrink as package repositories and `VaultController` take over.

## Implementation Strategy

This should be a facade-first migration, not a big-bang rewrite.

The safest order is:

1. Add test coverage and baseline evidence for current behavior.
2. Introduce new app-facing facades while they still wrap current behavior.
3. Move internals behind those facades one concern at a time.
4. Migrate view call sites to intents and controllers.
5. Delete old wrappers only after all call sites and regression tests pass.

Each phase should be landed as its own reviewable commit when implementation starts.

## Phase Plan

### Phase 0: Baseline Characterization

Scope:

- Document current call sites for `MarkdownNoteStore`, `SearchIndexRefreshCoordinator`, `VaultFileWatcher`, direct `FileManager`, navigation route state, and editor session persistence.
- Add or identify Swift tests that lock down current note open, edit/save, search, Today, and navigation behavior.
- Write end-to-end Swift sequence/integration tests that align to current Noto behavior before changing architecture. These tests should encode what the app does today, not the desired future abstraction.
- Capture current iPhone, iPad, and macOS smoke evidence only for residual UI/runtime risks that Swift tests cannot prove.

Expected files/modules touched:

- Tests only, fixtures/helpers if needed, plus this feature doc updates.
- No production behavior changes.

Acceptance gate:

- Relevant package tests pass.
- App-target Swift tests pass for the characterization suites.
- Baseline end-to-end Swift sequence tests pass against fixture vaults and a current-vault snapshot.
- Focused UI smoke evidence is saved under `.codex/evidence/ownership-rearchitecture/baseline/` for platform-specific navigation/search/editor behavior that Swift tests cannot prove.
- A dependency map exists for migration call sites.

Baseline end-to-end Swift coverage to create:

- `workspaceNavigationBaseline`
  - load root/folder contents from the current store/repository path
  - resolve a root note
  - resolve a nested folder and nested note
  - model current route/selection state where app-target seams already exist
  - resolve/open Today through the current daily-note code path
- `noteMutationBaseline`
  - create a scratch note through the current store/session path
  - edit note content
  - exercise current autosave/save sequencing where test seams exist
  - rename via first heading/title behavior if that is current behavior
  - reload and verify persistence
  - delete the scratch note and verify current post-delete navigation behavior
- `searchBaseline`
  - query known current-vault content
  - resolve a result back to the note/store path the app currently uses
  - create or edit a scratch note
  - verify search index freshness after current create/save/rename/delete behavior, matching current timing and refresh semantics
- `editorInteractionBaseline`
  - load a scratch note through `NoteEditorSession`
  - exercise page mention lookup and markdown link insertion through app-target editor/session seams where possible
  - exercise current editor command transforms that already have deterministic test seams
  - verify edited content persists after autosave

Baseline end-to-end Swift rules:

- Use Swift Testing/app-target tests first. Do not reach for Maestro or FlowDeck to prove behavior that can be covered through deterministic Swift tests.
- Test the model and current collaborators, not rendered pixels.
- Use real temp directories and real file I/O for persistence/search/vault flows.
- Prefer merged sequence tests over many tiny E2E tests. The goal is to preserve user workflows with low runtime and low maintenance cost.
- Name characterization cases with `current behavior:` or equivalent naming in the suite/test display name.
- Do not rewrite app architecture to make Phase 0 tests pass.
- Record any current behavior that seems awkward as baseline behavior, not as a Phase 0 bug, unless it is already broken.
- State residual UI risks explicitly. Swift tests do not prove visual layout, keyboard behavior, gesture behavior, actual navigation stack presentation, sheets, or scene lifecycle.

UI automation role:

- UI automation is a secondary smoke layer, not the primary Phase 0 E2E strategy.
- Use FlowDeck or Maestro only for the small set of runtime behaviors Swift tests cannot prove:
  - compact iPhone navigation stack presentation
  - iPad/macOS split-view presentation
  - keyboard toolbar visibility/focus behavior
  - global search sheet presentation and result tap wiring
  - mention popover/sheet presentation
- If UI automation needs identifiers, add only minimal behavior-neutral identifiers and record them as automation contracts.

Baseline vault modes:

- Fixture mode:
  - deterministic seeded vault
  - safe for destructive create/edit/delete flows
  - used in CI and repeatable Swift tests
- Current-vault mode:
  - uses Eugene's actual current Noto vault for realism
  - prefer copying the current vault to a temp snapshot before mutation tests
  - read-only tests may point at the live current vault when they do not modify files
  - validates real folder depth, real note sizes, real search data, real iCloud/provider behavior, and real index performance
  - should be used for Phase 0 local baseline evidence and before landing major migration phases

Current-vault safety rules:

- Read-only flows can open, navigate, search, and inspect existing notes.
- Mutation flows should run against a temp snapshot of the current vault whenever possible.
- If a mutation flow must run against the live current vault, it must create notes only inside a clearly named scratch area, for example `.codex-e2e/` or `E2E Scratch/`.
- Scratch note titles should include a unique run token, for example `E2E Baseline 2026-04-27 1430`.
- Tests must only delete notes/folders they created in the same run.
- Tests must never edit or delete pre-existing user notes.
- If a scratch cleanup fails, the test should report the created paths explicitly.
- Current-vault tests should support a dry-run/read-only mode for quick local checks.

### Phase 1: Introduce VaultController As A Compatibility Facade

Scope:

- Add app-target `VaultController`.
- Initially wrap existing `MarkdownNoteStore`, watcher, note sync, daily note, and search refresh behavior.
- Do not move filesystem internals yet.
- Add tests around controller intent methods using temp vaults and fakes where needed.

Why first:

This creates the destination API before moving internals, which lets future phases migrate one caller at a time.

Acceptance gate:

- `VaultController` can load/list/open/create/save/rename/delete a note through existing behavior.
- Existing UI still uses old paths unless migration is explicitly in scope.
- No behavioral change in manual smoke tests.

### Phase 2: Introduce SearchIndexController And Package SearchIndexCoordinator

Scope:

- Move package-worthy refresh mechanics into `NotoSearch.SearchIndexCoordinator`.
- Replace app-target `SearchIndexRefreshCoordinator` with `SearchIndexController`.
- Keep app notifications and scene/lifecycle decisions in the app target.
- Route search-index side effects from `VaultController` where possible.

Acceptance gate:

- Package tests cover single-flight refresh, file refresh, replace/remove, and debounce behavior with deterministic timing seams where practical.
- App tests cover notification or observable-state behavior.
- Search sheet still returns current-vault results.
- Create, save, rename, delete, and Today-note flows update search results.

### Phase 3: Move Non-UI Vault Mechanics Into NotoVault

Scope:

- Add package-level abstractions such as `VaultFileSystem`, `CoordinatedVaultFileSystem`, repositories, path resolver, daily note service, and attachment storage as needed.
- Move non-UI `MarkdownNoteStore` behavior into package services gradually.
- Keep `MarkdownNoteStore` as a compatibility wrapper until final cleanup.
- Preserve coordinated file access, iCloud readability behavior, and security-scoped bookmark assumptions.

Acceptance gate:

- `NotoVault` package tests cover CRUD, folder traversal, title resolution, path resolution, daily notes, attachments, and expected error mapping.
- macOS external-vault save/delete behavior still works.
- iOS iCloud readable-file behavior still trusts actual read success over metadata inference.
- No SwiftUI/UIKit/AppKit presentation code enters `NotoVault`.

### Phase 4: Extract VaultWorkspaceView

Scope:

- Extract workspace routing from current `NoteListView` into `VaultWorkspaceView`.
- Preserve current compact iPhone `NavigationStack` behavior.
- Preserve iPad/macOS split selection behavior.
- Move global search, settings, Today routing, restore-last-opened-note, and note history ownership into the workspace shell.
- Keep `NotoSplitView` temporarily if it helps reduce risk.

Acceptance gate:

- `NoteListView` no longer creates `NoteEditorScreen`.
- Search result taps route through `VaultWorkspaceView`.
- Editor document links route through `VaultWorkspaceView`.
- Bottom bar belongs to `VaultWorkspaceView`.
- iPhone, iPad, and macOS navigation smoke tests pass.

### Phase 5: Convert List, Sidebar, And Search Surfaces To Intent Emitters

Scope:

- Make `NoteListView`, `NotoSidebarView`, `FolderContentView`, and search result surfaces render data and emit workspace intents.
- Remove embedded workspace routing decisions from those views.
- Keep platform-specific shell logic in `VaultWorkspaceView`, not duplicated inside row/list components.

Acceptance gate:

- List/sidebar components can be tested with supplied data and captured intents.
- Folder open, note open, create, delete, search open, settings open, and Today actions still work.
- iPad/macOS split selection stays synchronized with route state.

### Phase 6: Route Editor Persistence Through VaultController

Scope:

- Change `NoteEditorSession` persistence calls from direct store/file/search collaborators to `VaultController`.
- Keep editor-local state in the session:
  - current content
  - latest editor text
  - last persisted text
  - pending local edits
  - autosave and rename timers
  - conflict/download/delete state
- Keep `TextKit2EditorView` focused on native text editing and markdown rendering.
- Page mention lookup can call `VaultController.pageMentions(...)`; mention UI remains editor-owned.
- Keyboard toolbar remains editor-owned.

Acceptance gate:

- Load, edit, autosave, manual save, rename, delete, conflict, same-process sync, and external-change behavior remain intact.
- Editor does not know about search-index refresh implementation.
- TextKit behavior, cursor behavior, keyboard toolbar, and mention menu still work.

### Phase 7: Cleanup And Enforcement

Scope:

- Remove or shrink compatibility wrappers.
- Delete obsolete coordinator names once call sites are migrated.
- Add lint-like search checks or lightweight tests for forbidden direct dependencies where practical.
- Update architecture docs and lifecycle diagrams to reflect the new ownership.

Acceptance gate:

- No UI view directly depends on raw vault filesystem mechanics.
- No app call site uses obsolete `SearchIndexRefreshCoordinator`.
- `MarkdownNoteStore` is either deleted or clearly reduced to a package/internal adapter with no UI-facing role.
- Architecture docs match the implemented shape.

## Per-Phase Verification Gates

Every phase should complete this sequence before moving on:

1. Run targeted Swift/package tests for touched modules.
2. Run broader package sweep if package code changed.
3. Run app tests through FlowDeck when app-target behavior changed.
4. Run focused E2E smoke for affected workflows.
5. Record exact commands, result, and residual risks in this doc.
6. Save UI evidence when navigation, search, editor, or platform chrome changes.

Apple-platform build/test/run rules:

- Use FlowDeck for app builds, tests, simulator runs, screenshots, and logs.
- Check `flowdeck config get --json` before any FlowDeck build/test/run command.
- Use isolated simulators for simulator validation.
- Seed simulator vaults with `.maestro/seed-vault.sh <simulator-udid>` before note-list or editor UI validation.
- Prefer `scripts/run_maestro_isolated.sh` for Maestro flows.

## Automated Test Plan

### Package Tests

Run or add focused package tests for:

- `Packages/NotoVault`
  - vault path resolution
  - note/folder CRUD
  - coordinated reads/writes/moves/deletes
  - daily note creation and idempotency
  - title resolution and metadata/frontmatter handling
  - attachment storage/pathing
  - readable-file behavior when metadata is misleading
- `Packages/NotoSearch`
  - full index refresh
  - file refresh
  - scheduled/debounced file refresh
  - replace/remove file refresh
  - search result freshness after CRUD
  - cancellation/single-flight behavior
- `Packages/NotoReadwiseSync`
  - only if vault-facing contracts change

### App Tests

Add or update app-target tests for:

- `VaultControllerTests`
  - load root
  - load folder
  - open note
  - create note in root/folder
  - save note
  - rename note from title
  - delete note/folder
  - resolve document link
  - open/prewarm Today note
  - page mention candidates
  - search integration
- `SearchIndexControllerTests`
  - startup refresh decision
  - search-sheet refresh decision
  - save/create/delete/rename refresh decision
  - notification or observable-state publication
  - duplicate-refresh suppression
- `VaultWorkspaceNavigationTests`
  - compact iPhone note route
  - split-view selection route
  - search result route
  - document-link route
  - Today route
  - restore last-opened note
  - back/forward history
- `NoteEditorSessionTests`
  - load through controller
  - autosave through controller
  - title rename through controller
  - pending local edit protection
  - external update handling
  - delete handling

### Dependency Checks

After cleanup, add cheap checks that fail if ownership regresses:

- Views should not introduce direct `FileManager` vault operations.
- Views should not instantiate `MarkdownNoteStore`.
- Views should not call `SearchIndexCoordinator` directly.
- `NotoVault` should not import SwiftUI/UIKit/AppKit for presentation.
- `NotoSearch` should not post app notifications.

## E2E Regression Plan

Run the matrix below for major UI/navigation phases and final cleanup:

```text
iPhone compact simulator
iPad mini simulator
macOS app
```

Use seeded vault fixtures that include:

- root notes
- nested folders
- markdown headings
- todo lists
- note links
- enough content for search
- at least one daily note conflict/non-conflict case
- at least one attachment/image note if attachment code is touched

### Launch And Workspace

- Fresh launch opens the configured vault without a blank or stuck state.
- Root list/sidebar loads expected notes and folders.
- Last-opened note restores when expected.
- App foreground/background does not lose selection.
- Empty/loading/error states still render when simulated.

### Navigation

- Open root note from list.
- Open nested folder.
- Open nested note.
- Navigate back from note to list on iPhone.
- Navigate back from nested folder to parent folder.
- On iPad/macOS, selecting notes updates detail without losing sidebar selection.
- Open note from document link inside editor.
- Use note history back/forward if available.
- Delete the currently open note and verify route returns to a valid workspace state.

### Create, Edit, Save

- Create a root note.
- Type body text and verify autosave persists after debounce.
- Add first heading and verify title/filename update behavior.
- Reopen the note and verify content is still present.
- Create note in nested folder.
- Edit an existing note and verify list/sidebar title updates.
- Trigger manual save if exposed.
- Close/reopen app and verify content persists.

### Daily Notes

- Tap Today from the workspace bottom bar.
- If today's note does not exist, it opens without a visible first-open delay after startup prewarm is implemented.
- Tapping Today repeatedly is idempotent.
- Today's note appears in search and list/sidebar as expected.
- Midnight/day-boundary behavior is covered by controller tests with an injectable clock; manual E2E only needs one current-day smoke unless scheduler code changes.

### Search Sheet

- Open global search from bottom bar or command.
- Search by title.
- Search by body content.
- Search nested-folder content.
- Tap a search result and verify workspace routes to the note.
- Verify empty state for a query with no results.
- Dismiss with Escape/cancel/outside click where supported.
- Verify search results update after create/save/rename/delete.

### Mention Menu

- Type the mention trigger in the editor.
- Query by title.
- Query by body/sidebar-visible title if supported.
- Select a mention result.
- Verify the markdown link is inserted at the cursor.
- Verify selecting/opening the inserted document link routes through the workspace.
- Verify dismissal preserves editor focus and cursor position.

### Keyboard Toolbar And Editor Chrome

- Show keyboard on iPhone simulator.
- Verify keyboard toolbar appears and remains visually correct.
- Use todo, indent/outdent, formatting, link, image, or other current toolbar actions that exist.
- Verify actions modify only the active note.
- Verify bottom bar does not overlap editor input or keyboard toolbar.

### File And Sync Behavior

- Modify a note externally and verify list/search/editor updates when there are no pending local edits.
- Modify externally while local edits are pending and verify conflict protection behavior.
- On macOS, verify external-vault save/delete still works with sandbox/security-scoped access.
- Open the same note in multiple windows if supported and verify same-process sync behavior.
- Verify `VaultFileWatcher` remains a fallback for external changes, not the same-window save path.

### Search Index Freshness

- Create note, then search title/body.
- Save existing note, then search new content.
- Rename note, then search new title and verify old title behavior.
- Delete note, then verify search no longer opens stale result.
- Move note/folder if supported, then verify search result opens the moved item.
- Open search sheet immediately after a save and verify refresh behavior is not stale.

### Platform-Specific Checks

- iPhone: compact navigation stack, bottom bar, keyboard toolbar, search sheet, mention UI.
- iPad: split view/sidebar, note detail selection, bottom bar placement, keyboard toolbar.
- macOS: split/sidebar, multi-window behavior if applicable, menu/keyboard shortcuts, search overlay/sheet dismissal, external-vault behavior.

### Evidence To Capture

Save evidence under `.codex/evidence/ownership-rearchitecture/<phase>/`:

- iPhone root list
- iPhone editor with keyboard toolbar visible
- iPad split view with selected note
- macOS workspace with sidebar and editor
- global search with results
- global search after opening result
- mention menu before and after insertion
- any failure screenshots and logs

## Rollback Strategy

- Keep each phase small enough to revert independently.
- Prefer adding new types and migrating call sites over editing every caller at once.
- Keep compatibility wrappers until replacement behavior has tests and E2E coverage.
- Do not delete old code in the same phase that introduces a new abstraction unless the deleted code has no remaining callers.
- If a phase breaks a previous acceptance gate, stop and fix before continuing.

## Implementation Notes

- Introduce injectable clocks/debounce schedulers for daily-note and search-index timing behavior.
- Prefer temp-directory integration tests for vault filesystem behavior.
- Preserve current app notifications while migrating; replace notification plumbing only after the controller boundary is stable.
- Keep UI-bound controllers `@MainActor`.
- Keep package coordinators/actors independent from SwiftUI app lifecycle.
- Add accessibility identifiers only when needed to make new or changed E2E paths stable.

## Phase Completion Log

Use this section during implementation.

```text
Phase: 0 - Baseline Characterization
Date: 2026-04-27
Commit:
Scope completed:
- Added dependency map for current store, file coordination, search, navigation, and editor ownership.
- Added Swift end-to-end characterization tests for workspace resolution, note mutation, search freshness, editor interactions, and current-vault snapshot behavior.
- Captured focused iPhone current-vault UI smoke evidence for root list, search sheet, note open, and keyboard toolbar.
Tests run:
- `swift test` in `Packages/NotoVault` - passed, 47 tests.
- `swift test` in `Packages/NotoSearch` - passed, 27 tests.
- `flowdeck test --only OwnershipRearchitecturePhase0BaselineTests --json` - passed, 5 tests.
E2E evidence:
- `.codex/evidence/ownership-rearchitecture/baseline/iphone-current-vault-root.png`
- `.codex/evidence/ownership-rearchitecture/baseline/iphone-current-vault-search.png`
- `.codex/evidence/ownership-rearchitecture/baseline/iphone-current-vault-after-note-tap.png`
- `.codex/evidence/ownership-rearchitecture/baseline/iphone-current-vault-editor-keyboard.png`
Residual risks:
- Swift tests do not prove exact SwiftUI layout, animation, gesture behavior, or full iPad/macOS runtime presentation.
- Phase 0 iPad/macOS UI smoke is still optional residual evidence; behavior is covered through deterministic Swift/package tests first.

Phase: 1 - Introduce VaultController As A Compatibility Facade
Date: 2026-04-27
Commit:
Scope completed:
- Added app-target `VaultController`.
- Kept it as a facade over current `MarkdownNoteStore` and `NotoSearch` behavior.
- Did not migrate view call sites or move filesystem internals.
- Added focused facade tests for root/folder loading, note mutation, Today/page mentions, and search.
Tests run:
- `flowdeck test --only VaultControllerTests --json` - passed, 4 tests.
- `flowdeck test --only OwnershipRearchitecturePhase0BaselineTests --json` - passed, 5 tests.
E2E evidence:
- Reused Phase 0 baseline evidence; no user-facing UI behavior changed in Phase 1.
Residual risks:
- `VaultController` is not yet used by views or `NoteEditorSession`.
- It still delegates to `MarkdownNoteStore`, so package extraction has not started.

Phase: 2 - Introduce SearchIndexController And Package SearchIndexCoordinator
Date: 2026-04-27
Commit:
Scope completed:
- Added package-level `NotoSearch.SearchIndexCoordinator` with injectable indexing client, single-flight full refresh, debounced file refresh, replace, remove, and follow-up file operations.
- Added app-target `SearchIndexController` that wraps the package coordinator and owns `.notoSearchIndexDidChange` notification posting.
- Removed app-target `SearchIndexRefreshCoordinator`.
- Migrated app call sites in `NotoApp`, `MarkdownNoteStore`, `NoteListView`, and baseline tests to `SearchIndexController`.
Tests run:
- `swift test` in `Packages/NotoSearch` - passed, 31 tests.
- `flowdeck test --only 'NotoTests/SearchIndexControllerTests/refreshPublishesNotification()' --json -S "Noto-OwnershipRearch-Phase0"` - passed, 1 test.
- `flowdeck test --only 'NotoTests/SearchIndexControllerTests/scheduledRefreshPublishesAfterDebounce()' --json -S "Noto-OwnershipRearch-Phase0"` - passed, 1 test.
- `flowdeck test --only 'NotoTests/SearchIndexControllerTests/replaceAndRemovePublishNotifications()' --json -S "Noto-OwnershipRearch-Phase0"` - passed, 1 test.
- `flowdeck test --only VaultControllerTests --json -S "Noto-OwnershipRearch-Phase0"` - passed, 4 tests.
- `flowdeck test --only 'NotoTests/OwnershipRearchitecturePhase0BaselineTests/workspaceNavigationBaseline()' --json -S "Noto-OwnershipRearch-Phase0"` - passed, 1 test.
- `flowdeck test --only 'NotoTests/OwnershipRearchitecturePhase0BaselineTests/noteMutationBaseline()' --json -S "Noto-OwnershipRearch-Phase0"` - passed, 1 test.
- `flowdeck test --only 'NotoTests/OwnershipRearchitecturePhase0BaselineTests/searchBaseline()' --json -S "Noto-OwnershipRearch-Phase0"` - passed, 1 test.
- `flowdeck test --only 'NotoTests/OwnershipRearchitecturePhase0BaselineTests/editorInteractionBaseline()' --json -S "Noto-OwnershipRearch-Phase0"` - passed, 1 test.
- `flowdeck test --only 'NotoTests/OwnershipRearchitecturePhase0BaselineTests/currentVaultSnapshotBaseline()' --json -S "Noto-OwnershipRearch-Phase0"` - passed, 1 test.
E2E evidence:
- Reused Phase 0 baseline evidence; Phase 2 changed search-index plumbing and app notifications, not visible UI layout.
Residual risks:
- FlowDeck/xcodebuild hung when running some multi-test `--only` filter combinations together. The same tests passed when run individually or by reliable suite filter, so this is recorded as harness risk rather than app behavior risk.
- `SearchIndexController.scheduleRefreshFile` depends on the package callback to publish after debounce completion; future package API changes should preserve that app notification contract.

Phase: 3 - Move Non-UI Vault Mechanics Into NotoVault
Date: 2026-04-27
Commit:
Scope completed:
- Added package-level `VaultFileSystem` and `CoordinatedVaultFileSystem`.
- Added package-level `VaultMarkdown`, `VaultPathResolver`, `DailyNoteService`, `NoteRepository`, `FolderRepository`, and `AttachmentStore`.
- Converted app `CoordinatedFileManager` into a compatibility wrapper over `NotoVault.CoordinatedVaultFileSystem`.
- Converted app `DailyNoteFile` and major `MarkdownNoteStore` note/folder/path/attachment methods to delegate to package services while preserving current app-facing types.
Tests run:
- `swift test` in `Packages/NotoVault` - passed, 52 tests.
- `flowdeck test --only VaultControllerTests --json -S "Noto-OwnershipRearch-Phase0"` - passed, 4 tests.
- `flowdeck test --only 'NotoTests/OwnershipRearchitecturePhase0BaselineTests/noteMutationBaseline()' --json -S "Noto-OwnershipRearch-Phase0"` - passed, 1 test.
- `flowdeck test --only 'NotoTests/OwnershipRearchitecturePhase0BaselineTests/searchBaseline()' --json -S "Noto-OwnershipRearch-Phase0"` - passed, 1 test.
E2E evidence:
- Reused Phase 0 baseline evidence; Phase 3 changed non-UI vault internals.
Residual risks:
- `MarkdownNoteStore` remains a compatibility wrapper and still owns app-facing list mutation/search side effects.
- Page mention indexing and UI routing are still app-layer concerns until later phases.

Phase: 4 - Extract VaultWorkspaceView
Date: 2026-04-27
Commit:
Scope completed:
- Renamed the root workspace shell from `NoteListView` to `VaultWorkspaceView`.
- Updated `MainAppView` to render `VaultWorkspaceView`.
- Kept compact iPhone `NavigationStack` behavior and iPad/macOS split behavior in the extracted workspace shell.
- Left `NotoSplitView` in place as a temporary platform split renderer.
Tests run:
- `flowdeck test --only NoteListViewTests --json -S "Noto-OwnershipRearch-Phase0"` - passed, 1 test.
- `flowdeck test --only 'NotoTests/OwnershipRearchitecturePhase0BaselineTests/workspaceNavigationBaseline()' --json -S "Noto-OwnershipRearch-Phase0"` - passed, 1 test.
E2E evidence:
- Reused Phase 0 baseline evidence; no visual redesign was intended.
Residual risks:
- `NotoSplitView` still constructs the split editor detail as a compatibility step.

Phase: 5 - Convert Workspace Surfaces Toward Intent Emitters
Date: 2026-04-27
Commit:
Scope completed:
- Moved global search presentation state ownership up to `VaultWorkspaceView`.
- Passed search state into `NotoSplitView` so split/sidebar surfaces render from workspace-owned state.
- Left row/list/sidebar mutation APIs intact where changing them would exceed the phase's safety budget.
Tests run:
- Covered by Phase 4 workspace navigation and NoteListView bottom toolbar tests.
E2E evidence:
- Reused Phase 0 baseline evidence.
Residual risks:
- Sidebar/list components still use bindings and store calls for some mutations; they are not pure intent-only renderers yet.

Phase: 6 - Route Editor Persistence Through VaultController
Date: 2026-04-27
Commit:
Scope completed:
- Added `VaultController` methods for editor metadata, attachment import, read, save, rename, move, and delete operations.
- Updated `NoteEditorSession` to keep editor-local state while routing persistence through `VaultController`.
- Updated `NoteEditorScreen` delete behavior to use the session/controller path.
Tests run:
- `flowdeck test --only NoteEditorSessionTests --json -S "Noto-OwnershipRearch-Phase0"` - passed, 7 tests.
E2E evidence:
- Reused Phase 0 editor evidence.
Residual risks:
- `NoteEditorSession` still receives a `MarkdownNoteStore` because `MarkdownNoteStore` remains the compatibility adapter.

Phase: 7 - Cleanup And Enforcement
Date: 2026-04-27
Commit:
Scope completed:
- Removed the old `SearchIndexRefreshCoordinator` production file and migrated app call sites.
- Added ownership dependency tests for obsolete search coordinator naming, package notification boundaries, and NotoVault presentation imports.
- Added implementation summary at `.codex/feature/ownership-rearchitecture-implementation-summary.md`.
Tests run:
- `flowdeck test --only OwnershipDependencyTests --json -S "Noto-OwnershipRearch-Phase0"` - passed, 3 tests.
- `swift test` in `Packages/NotoVault` - passed, 52 tests.
- `swift test` in `Packages/NotoSearch` - passed, 31 tests.
E2E evidence:
- Reused Phase 0 baseline evidence.
Residual risks:
- A follow-up can further shrink `MarkdownNoteStore`, make sidebar/list components stricter intent emitters, and move split editor construction entirely into `VaultWorkspaceView`.
```
