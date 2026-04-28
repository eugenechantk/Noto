# Vault Controller Rearchitecture

## Goal

Make vault access easier to reason about by separating:

- `NotoVault`: vault correctness, file operations, metadata, and platform-neutral domain behavior.
- App target: lifecycle, UI state, navigation, presentation, and platform chrome.
- One app-facing `VaultController`: the only interface SwiftUI views use for vault-related behavior.

## Proposed Shape

```text
SwiftUI views
  -> VaultController
    -> NotoVault package
      -> filesystem adapter
        -> FileManager / NSFileCoordinator
    -> NotoSearch package
    -> app lifecycle hooks
```

`NotoVault` should own non-UI file manager logic:

- directory enumeration
- note/folder create, read, save, rename, move, delete
- coordinated file reads/writes/moves/deletes
- frontmatter, stable IDs, title resolution
- vault-relative path resolution
- lookup by note ID or relative path
- daily note file creation
- attachment import storage/pathing

The app target should keep UI/lifecycle concerns:

- SwiftUI navigation and selection state
- editor screen/session presentation state
- scene phase handling
- vault picker UI and settings UI
- command/menu routing
- platform-specific chrome
- user-visible conflict banners and sheets

## VaultController Interface Sketch

Intent-level methods instead of exposing raw storage details to views:

```swift
@MainActor
@Observable
final class VaultController {
    var rootItems: [VaultItem]
    var selectedNote: NoteHandle?
    var isLoading: Bool

    func loadRoot()
    func loadFolder(_ folder: FolderHandle)
    func openNote(_ handle: NoteHandle) async throws -> LoadedNote
    func createNote(in folder: FolderHandle?) async throws -> NoteHandle
    func save(_ note: LoadedNote, text: String) async throws -> SaveResult
    func renameIfNeeded(_ note: LoadedNote) async throws -> NoteHandle
    func delete(_ item: VaultItem) async throws
    func move(_ item: VaultItem, to folder: FolderHandle) async throws
    func todayNote() async throws -> LoadedNote
    func pageMentions(matching query: String, excluding note: NoteHandle?) async -> [PageMention]
    func search(query: String, scope: SearchScope) async throws -> [VaultSearchResult]
}
```

Internally this should stay composed, not become a god object:

```text
VaultController
  - noteRepository
  - folderRepository
  - dailyNoteService
  - attachmentService
  - searchService
  - vaultWatcher
```

## Package Boundary

`NotoVault` can contain filesystem protocols and implementations:

```text
VaultFileSystem protocol
CoordinatedVaultFileSystem implementation
VaultRepository
DailyNoteService
AttachmentStore
VaultPathResolver
```

The package should not import SwiftUI, UIKit, or AppKit for presentation. Foundation filesystem APIs are acceptable. If platform-specific APIs are needed, wrap them behind narrow abstractions.

## Migration Plan

1. Add a filesystem abstraction inside `NotoVault`.
2. Move coordinated read/write/move/delete logic out of app target.
3. Move non-UI `MarkdownNoteStore` behavior into package repositories/services.
4. Introduce app-target `VaultController` as the single UI-facing facade.
5. Replace direct view calls to `MarkdownNoteStore` with `VaultController` calls.
6. Keep `MarkdownNoteStore` temporarily as a compatibility wrapper, then delete or reduce it.

## Risks

- Over-centralizing into a controller that becomes another large store.
- Accidentally moving app lifecycle or UI state into `NotoVault`.
- Regressing iCloud/security-scoped behavior if coordinated file access changes.
- Large migration touching editor, sidebar, search, daily notes, and tests at once.

## Recommendation

Do this incrementally. Start by moving filesystem primitives and pure repository operations into `NotoVault`, then add `VaultController` as a facade. Avoid rewriting all UI at once.
