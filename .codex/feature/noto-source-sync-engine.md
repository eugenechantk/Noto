# Feature: Noto Source Sync Engine

## User Story

As Eugene, I want Noto to sync my Readwise and Reader library into my vault so that saved sources, full content, and highlights become one coherent set of source notes in `Captures/` without duplicate notes or manual cleanup.

## User Flow

1. Eugene opens Noto.
2. Noto reads the Readwise token from secure platform storage. If secure storage is empty and the private build includes a bundled default token, Noto seeds secure storage from that bundled value first.
3. Noto starts background incremental sync through `Packages/NotoReadwiseSync`.
4. The sync engine fetches changed Reader documents and changed Readwise sources using saved `updatedAfter` cursors.
5. The sync engine reconciles Reader documents and Readwise highlight groups into canonical source-note identities.
6. The sync engine writes or updates markdown files under `Captures/` and updates `.noto/sync/readwise.json`.
7. Noto’s existing vault filesystem watcher observes the file changes and refreshes the note list/sidebar through the normal vault-loading path.
8. Eugene can also trigger the same sync manually with `Sync now` in settings.
9. Eugene can input the Readwise token in settings and save it to secure platform storage so that the Noto app can read it.

## Success Criteria

- [x] Sync orchestration lives in `Packages/NotoReadwiseSync`, not in app UI code.
- [x] Sync logic is implemented independently from the CLI so the app does not depend on CLI entry points or shell-oriented behavior.
- [x] Reader documents sync into `Captures/` with full content when `html_content` exists.
- [x] Readwise export sync writes highlights into source notes.
- [x] Reader-backed Readwise sources reconcile onto the same `reader:<reader_document_id>` note instead of creating duplicate `readwise-book:*` notes.
- [x] Readwise-only sources use `readwise-book:<readwise_user_book_id>` as canonical identity.
- [x] Incremental sync uses saved timestamps in `.noto/sync/readwise.json` rather than re-fetching the full library every run.
- [x] Sync state stores a canonical-key-to-file map so reruns can find existing notes quickly.
- [x] Source notes may contain user-authored content outside generated regions, but sync modifies only importer-owned blocks and frontmatter fields.
- [x] Deleted Readwise highlights are removed from the generated highlights block on the next sync.
- [x] Deleted Reader documents / deleted Readwise sources do not delete local notes.
- [x] Sync runs off the main thread and does not block app launch rendering.
- [x] Noto note list/sidebar refresh through existing vault filesystem observation after sync writes files.
- [x] Noto settings provide `Set Token`, `Test Connection`, and `Sync now`.
- [x] Readwise token is stored in platform secure storage, never in the vault.
- [x] Private builds can optionally bundle a default Readwise token from untracked local build config and seed secure storage when no token exists.

## Platform & Stack

- **Platform:** Swift package shared by CLI and Apple app targets
- **Language:** Swift
- **Key frameworks:** Foundation, Swift Package Manager, Swift Testing, SwiftUI app integration, Keychain on Apple platforms

## Architecture

### Ownership Boundary

`Packages/NotoReadwiseSync` should own:

- Reader API client
- Readwise export API client
- canonical-key reconciliation
- source-note rendering
- sync-state read/write
- incremental cursor handling
- highlight delete handling
- high-level sync orchestration

The Noto app should own only:

- secure token storage access
- settings UI
- app-launch sync trigger
- `Sync now` trigger
- lightweight sync status (`idle`, `syncing`, `last synced`, `error`)

The CLI should own only:

- argument parsing
- reading token from env / shell
- calling the package entry point
- printing human-readable results

### Package Surface

The package should expose reusable sync components and orchestration, but it does not need one mandatory top-level entry point shared by the CLI and app. The important boundary is that sync logic lives in the package, while CLI and app remain thin callers.

Possible shape:

```swift
public struct ReaderSyncEngine { ... }
public struct ReadwiseSyncEngine { ... }
public struct SourceNoteSyncEngine { ... }
public struct SyncStateStore { ... }
```

The CLI may compose these differently from the app.

## Data Model

### Source Note Identity

- Reader document: `reader:<reader_document_id>`
- Readwise-only source: `readwise-book:<readwise_user_book_id>`

### Reader/Readwise Reconciliation

If a Readwise export item has:

- `source == "reader"`
- `external_id == ReaderDocument.id`

then it belongs to the Reader document note:

```text
reader:<reader_document_id>
```

That note should contain:

- content block from Reader
- highlights block from Readwise
- frontmatter with both `reader_document_id` and `readwise_user_book_id`

### Source Note Shape

Notes live under:

```text
Captures/
```

Body shape:

```md
# Title

<!-- readwise:highlights:start -->
...
<!-- readwise:highlights:end -->

<!-- readwise:content:start -->
...
<!-- readwise:content:end -->
```

Frontmatter owns:

- `canonical_key`
- `reader_document_id`
- `readwise_user_book_id`
- `source_url`
- `reader_url`
- `readwise_url`
- `readwise_bookreview_url`
- `reader_location`
- `tags`
- `updated`

## Sync State

Stored in:

```text
<vault>/.noto/sync/readwise.json
```

State must include:

- `lastSuccessfulSyncAt`
- `lastSuccessfulReaderSyncAt`
- `sources[canonical_key]` with:
  - `relativePath`
  - `noteID`
  - `generatedBlockHash`
  - `readerDocumentID`
  - `readwiseUserBookID`
  - `updatedAt`

Purpose:

- support incremental upstream fetches
- persist last successful upstream sync timestamps across launches
- find existing notes quickly by `canonical_key`
- avoid duplicate note creation on reruns

The source note frontmatter is the durable source of truth for identity:

- `canonical_key`
- `reader_document_id`
- `readwise_user_book_id`

The sync-state map is the primary lookup path for performance. If a stored path is stale or missing, sync should recover by scanning existing notes for `canonical_key` and rebuilding the map entry.

## Sync Pipeline

### Reader Sync

1. Fetch Reader documents from `GET /api/v3/list/` with:
   - `withHtmlContent=true`
   - `withRawSourceUrl=true`
   - optional `id`, `location`, `category`, `tag`, `updatedAfter`
2. Skip child documents.
3. Convert `html_content` to Markdown.
4. Compute canonical key `reader:<id>`.
5. Always fetch Readwise export and join matching Reader-backed highlights by `external_id`.
6. Write/update the source note.

### Readwise Sync

1. Fetch Readwise export from `GET /api/v2/export/` with:
   - `includeDeleted=true`
   - optional `updatedAfter`
2. For each book:
   - skip if upstream source deleted, but do not delete local note
   - choose canonical key:
     - `reader:<external_id>` when `source == "reader"`
     - otherwise `readwise-book:<user_book_id>`
3. Filter deleted highlights out of the rendered highlights block.
4. Update the existing note or create a new one if no note exists.
5. Preserve any existing Reader content block when applying Readwise highlight updates.

### Incremental Sync

1. On app launch/open, run sync in the background.
2. Also allow manual `Sync now` in settings.
3. Run Reader sync first.
4. Then run Readwise sync.
5. Reader fetch uses:

```text
updatedAfter=<lastSuccessfulReaderSyncAt>
```

6. Readwise fetch uses:

```text
updatedAfter=<lastSuccessfulSyncAt>
```

7. Replace only importer-owned frontmatter fields and generated blocks.
8. Save new successful sync timestamps after a successful run.

## Delete Behavior

Default behavior should remain non-destructive:

- deleted Readwise highlight -> remove from highlights block
- deleted Reader document -> keep local note
- deleted Readwise source -> keep local note

Do not add hard-delete behavior for source notes.

## Secret Storage

The Readwise token must never be stored in:

- the vault
- frontmatter
- `.noto/sync/readwise.json`
- `.obsidian/`
- any other iCloud-synced file

Storage model:

- macOS: Keychain
- iPhone/iPad: iOS Keychain

Runtime model:

- The app reads the token from secure storage at runtime and passes it to the sync package.
- For private builds, `Config/LocalSecrets.xcconfig` can define `NOTO_READWISE_TOKEN`.
- The Xcode build phase writes `ReadwiseDefaultToken.txt` into the app bundle only when `NOTO_READWISE_TOKEN` is present.
- On launch, if Keychain is empty, Noto reads the bundled default token and stores it into Keychain.
- If Keychain already has a token, the bundled value does not overwrite it.

## Threading / Runtime Model

- token lookup, network calls, JSON decoding, HTML-to-Markdown conversion, rendering, and file writes run off the main thread
- app launch should render immediately from local vault state
- sync runs in background
- sync writes files only
- note list/sidebar refresh should happen through the existing vault filesystem watcher path

The sync engine should not directly mutate note-list UI collections.

## Resolved Decisions

1. Full-library incremental sync runs Reader first, then Readwise.
2. Reader sync always fetches matching Readwise highlights.
3. Deleted upstream sources do not need frontmatter markers.
4. `Captures/` is the single canonical directory.

## Steps to Verify

1. `cd Packages/NotoReadwiseSync && swift test`
2. `cd Packages/NotoReadwiseSync && swift run noto-readwise-sync --help`
3. Run fixture-based Reader and Readwise syncs against a temp vault.
4. Verify Reader-backed Readwise sources update one `reader:<id>` note instead of creating duplicates.
5. Verify notes in `Captures/` update only frontmatter and generated blocks.
6. Verify deleting a Readwise highlight removes it from the note on the next sync.
7. Verify app launch remains responsive while sync runs in background.
8. Verify new/updated notes appear in the note list through filesystem observation.

## Bugs

_None yet._
