# Cross-Cutting Behaviours

Behaviour that spans screens. These are the rules a screen-by-screen reading misses, and
they are where a rewrite is most likely to silently diverge.

Sourced from `main` @ `bd09d1d`: `NotoApp.swift`, `NoteEditorSession`, `TextKit2EditorView`,
`VaultLocationManager`, `MarkdownNoteStore`, `VaultFileWatcher`, `NoteSyncCenter`,
`ReadwiseSyncController`, and the runtime rules in `CLAUDE.md`.

---

## 1. Storage model

**The filesystem is the source of truth.** There is no content database.

```
Vault/
  Daily Notes/2026-08-03.md
  Projects/Project Alpha.md
  Captures/Some Article.md
```

Every note is a `.md` file with YAML frontmatter:

```yaml
---
id: 550e8400-e29b-41d4-a716-446655440000
created: 2026-03-16T09:30:00Z
modified: 2026-03-16T14:22:00Z
---
```

Rules that must survive migration:

- **The frontmatter UUID is permanent identity.** Filenames change freely; the `id` does not.
  Never key anything on path.
- **Title is derived from the first line**, not stored. `MarkdownNote.titleFrom(content)`.
  Editing the H1 renames the file.
- Frontmatter is **hidden in the editor** but present in the buffer and round-tripped on save.
  Capture notes carry much richer frontmatter (source URL, author, tags, `capture_status`)
  and it must be preserved byte-for-byte through an edit.
- Folders are real directories. Creating a folder is `mkdir`.

---

## 2. Note lifecycle

`NoteEditorSession` owns one open note: load, edit, autosave, rename, move, delete, conflict.

### Load

`.task(id: note.id)` calls `session.switchTo(note:store:isNew:)` then `loadNoteContent()`.

The ordering is load-bearing and was fixed by hand: on macOS the task can restart **before**
`.onChange(of: note)` has switched the session, so `switchTo` is called inside the task so the
load decision always sees the incoming note. `switchTo` is a no-op when already matched.

### Loading placeholder

`DelayedLoadingPlaceholder` shows a spinner and "Loading note…" — but only after a **300 ms**
delay, so fast loads never flash.

There is a comment in the source worth carrying over verbatim as a lesson: the base view must
be a real (if invisible) `Color.clear`, not conditional-empty content, because SwiftUI skips
`.task` on a view that resolves to nothing — which meant the placeholder could never appear and
users got a blank pane instead of loading feedback.

### Autosave

Debounced on edit; `persistFinalSnapshotIfNeeded` runs on `.onDisappear`. Closing an editor
mid-edit must not lose the tail of the buffer.

### Delete

`.onDisappear` checks `externallyDeletingNoteID` so a note deleted from elsewhere does not get
re-persisted on the way out.

---

## 3. Sync — three independent paths

`CLAUDE.md` is explicit that these must not be conflated.

| Path | Mechanism | Covers |
|---|---|---|
| **In-process** | `NoteSyncCenter` → `NoteSyncSnapshot` notifications | One window updating another in the same running app (macOS multi-window) |
| **Filesystem** | `VaultFileWatcher` (debounced) | True external change — iCloud, Finder, another process |
| **iCloud download** | Coordinated read, `ubiquitousItemDownloadingStatus` | Dataless files not yet materialised |

> Do **not** rely on the debounced file watcher for same-process editor sync. It is too slow
> and can miss same-file writes.

### Conflict — remote update banner

When a remote snapshot arrives while the local buffer is dirty, `pendingRemoteSnapshot` is set
and a banner appears above the editor: **"Updated in another window"** with **Keep Mine**
(`discardRemoteConflict`) and **Reload** (`reloadRemoteSnapshot`, ⌘⇧R).

Never silently overwrite. *(State documented from source; not captured — needs two windows.)*

### iCloud readability

> Do not gate note opening only on `ubiquitousItemDownloadingStatus`. **Try a coordinated read
> first.** If the file is readable, open it immediately; use the download flow only when it is
> genuinely unreadable.

Root-level notes fail differently from notes in subfolders when the app over-trusts metadata.
Two visible states result: `isDownloading` → spinner + "Downloading from iCloud…";
`downloadFailed` → `ContentUnavailableView` "Note Not Available" with a **Try Again** button
(`editor_retry_load_button`).

**Prefer real filesystem outcomes over inferred metadata** — actual write success on macOS,
actual read success on iOS.

---

## 4. macOS sandbox and vault access

> External vault access is a **sandbox permission problem first**, not an editor problem first.

- `NSCocoaErrorDomain Code=513` on a user-picked vault means vault access, not a code bug.
- Entitlement must be `com.apple.security.files.user-selected.read-write`.
- **The saved security-scoped bookmark is the real access token** — not the path.
- A stale bookmark produces a convincing fake-working state: the vault opens, notes load,
  **writes fail**.
- Do not silently reopen from a remembered raw path if writability cannot be re-established —
  force a clean folder re-pick.

`VaultLocationManager` keys: `vaultBookmarkData`, `vaultDirectPath`, `vaultIsDirect`,
`vaultIsLocal`. When `vaultIsLocal` is true the app uses its own container Documents/Noto and
needs no bookmark at all.

---

## 5. App lifecycle

`MainAppView.task` on launch, in order:

1. `SemanticSearch.configureAtStartup()` — wire the on-device embedding model **before** any
   index work, or the sweeps it triggers cannot embed.
2. `drainPendingQueue` — replay writes queued before a previous quit or crash. Drains **first**
   so files the sandbox enumerator cannot see (recently-written iCloud files) still index via
   their direct path.
3. `store.loadItemsInBackground()`
4. `tagController.load()` + `rebuildMembership()`
5. `dailyNotePrewarmer.start()`
6. Readwise `refreshSavedTokenState()` + `startAutomaticSync()`
7. `refreshSearchIndex()`

On `scenePhase == .active`: refresh store, re-prewarm daily note, restart Readwise sync, drain
and refresh index. On `.background`: stop the prewarmer.

On `fileWatcher.changeCount` change: reload items, rebuild tag membership, and refresh the
index — **for the single changed URL when known**, full sweep otherwise.

---

## 6. Search

Two indexes fused at query time:

- **Keyword** — FTS5 (`NotoSearch`)
- **Semantic** — on-device CoreML embeddings (`NotoEmbedding`)

Fusion is why [SEARCH-04](01-screens-and-states.md#search-04--semantic-fallback) returns
results for a nonsense query. Both indexes build in the background, resume automatically, and
can be rebuilt independently from Settings. Index writes go through a **crash-safe queue** so
an interrupted sync replays on next launch.

---

## 7. Navigation

| Platform | Model |
|---|---|
| iPhone (compact) | `NavigationStack` with a `NoteRoute` path; push/pop |
| iPad (regular) | `NavigationSplitView`, selection binding, sidebar overlays detail |
| macOS | `NavigationSplitView`, permanent sidebar, multi-window |

Ownership is layered and should be preserved:

- `MainAppView` owns app runtime lifecycle, **not** routing.
- `VaultWorkspaceView` owns navigation and presentation, **not** filesystem logic.
- UI surfaces emit `VaultWorkspaceIntent` — they never mutate selection, `NavigationPath`, or
  vault files directly.
- `NotoSplitView` is a layout shell only: it does not construct editors, create notes, or
  resolve document links.

Also present: note history (back/forward through visited notes, distinct from the nav stack),
restore-last-note on launch, and `NotoDeepLink` routing via `onOpenURL`.

---

## 8. Theming

Dark mode is **forced** — `.environment(\.colorScheme, .dark)` at the app root. There is no
light theme. Backgrounds: `AppTheme.background` (`#0A0A0A`) for app chrome,
`NotoTheme.background` (`#0E1116`) for the editor body and the macOS window.

Accent is a warm orange used for the new-note button, selection highlight, folder dots, and
destructive-adjacent affordances.

---

## 9. Conventions to carry over

- **Logging** — `os_log` / `Logger`, never `print()`. Subsystem is the bundle id; category is
  the type name.
- **Accessibility identifiers** — the `.maestro/` E2E flows depend on them. Preserve the
  identifiers listed in [01-screens-and-states.md](01-screens-and-states.md) so those flows
  keep working as migration regression tests.
- **Non-UI logic lives in packages** — `NotoVault`, `NotoSearch`, `NotoEdit`, `NotoTags`,
  `NotoChat`, `NotoEmbedding`, `NotoReadwiseSync`. Each is independently testable via
  `swift test` with no simulator.
