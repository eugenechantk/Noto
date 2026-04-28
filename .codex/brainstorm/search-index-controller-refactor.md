# Search Index Controller Refactor

## Problem

`SearchIndexRefreshCoordinator` currently lives in the app target and mixes two concerns:

- package-worthy search index mechanics
- app-runtime side effects and UI notifications

The name also differs from the emerging architecture language where UI-facing app services are called controllers.

## Proposed Shape

```text
SwiftUI / app lifecycle
  -> SearchIndexController      app target
    -> SearchIndexCoordinator   NotoSearch package
      -> MarkdownSearchIndexer
      -> SearchIndexStore
```

## Move Into `NotoSearch`

Package-level, non-UI logic:

- single-flight full index refresh per vault
- debounced single-file refresh
- replace-file and remove-file coordination
- follow-up single-file refresh after a running full refresh
- task cancellation and task-key management
- no SwiftUI
- no app notifications
- no scene-phase knowledge

Candidate package type:

```swift
public actor SearchIndexCoordinator {
    public func refresh(vaultURL: URL) async throws -> SearchIndexRefreshResult
    public func refreshFile(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats
    public func scheduleRefreshFile(vaultURL: URL, fileURL: URL)
    public func replaceFile(vaultURL: URL, oldFileURL: URL, newFileURL: URL) async throws -> SearchIndexStats
    public func removeFile(vaultURL: URL, fileURL: URL) async throws -> SearchIndexStats
}
```

## Keep In App Target

App-runtime, side-effectful logic:

- deciding when to refresh:
  - app startup
  - scene active
  - file watcher change
  - note save/create/delete/rename/move
  - search sheet open
  - daily note prewarm
- posting `.notoSearchIndexDidChange`
- exposing UI-friendly state if needed later
- connecting search refreshes to `VaultController` / workspace lifecycle

Candidate app type:

```swift
@MainActor
@Observable
final class SearchIndexController {
    func refresh(vaultURL: URL) async
    func refreshFile(vaultURL: URL, fileURL: URL)
    func scheduleRefreshFile(vaultURL: URL, fileURL: URL)
    func replaceFile(vaultURL: URL, oldFileURL: URL, newFileURL: URL)
    func removeFile(vaultURL: URL, fileURL: URL)
}
```

Internally it calls `NotoSearch.SearchIndexCoordinator`, then publishes app notifications or observable state.

## Naming

- `SearchIndexCoordinator`: package-level mechanical coordination.
- `SearchIndexController`: app-level lifecycle/controller surface.

This keeps "controller" reserved for UI/app-facing services and "coordinator" for lower-level async coordination.

## Migration Plan

1. Add `SearchIndexCoordinator` to `Packages/NotoSearch`.
2. Move single-flight/debounce/follow-up logic out of `Noto/SearchIndexRefreshCoordinator.swift`.
3. Replace the app actor with `SearchIndexController`.
4. Keep `.notoSearchIndexDidChange` in the app target.
5. Update `MarkdownNoteStore`, `MainAppView`, `NoteSearchSheet`, and daily-note prewarm call sites.
6. Add package tests for single-flight/debounce behavior where practical.
7. Add app tests for notification/UI-facing controller behavior.

## Risks

- Search refresh call sites are spread across app lifecycle, storage, search sheet, and daily notes.
- Moving async task ownership can introduce duplicate refreshes or missed notifications.
- Package tests need deterministic timing seams for debounce behavior.

## Recommendation

Do this before or alongside the `VaultController` work. The end state should be that vault writes call one app-facing controller/service, and package-level index mechanics stay reusable and UI-free.
