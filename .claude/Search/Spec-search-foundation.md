# Spec: Search Foundation

Based on [PRD-search-foundation.md](./PRD-search-foundation.md).

---

## User Stories

1. **As a developer**, I have a shared SQLite database for all search tables, isolated from SwiftData.
2. **As a user**, my edits are tracked for indexing without any lag while typing.
3. **As a user**, if the app crashes mid-edit, the search index self-repairs on next launch.
4. **As a developer**, I have a single markdown stripping function shared by both keyword and semantic pipelines.

---

## Acceptance Criteria

- [ ] `FTS5Database` creates `search.sqlite` with all required tables on first init
- [ ] `FTS5Database` opens existing database without recreating tables
- [ ] `FTS5Database` runs as an actor (no data races on concurrent access)
- [ ] `DirtyTracker.markDirty()` does not perform any SQLite writes (in-memory only)
- [ ] `DirtyTracker.flush()` persists all in-memory dirty blocks to `dirty_blocks` table
- [ ] `DirtyTracker.markDeleted()` writes to `dirty_blocks` immediately
- [ ] Idle timer fires after ~5 seconds and triggers flush
- [ ] Each `markDirty()` call resets the idle timer
- [ ] `PlainTextExtractor` strips bold, italic, strikethrough, inline code, and list prefixes
- [ ] `PlainTextExtractor` preserves unformatted text unchanged
- [ ] `SearchIndex` SwiftData model is removed from the schema
- [ ] UI testing mode uses a temporary directory for `search.sqlite`

---

## Technical Design

### Architecture Overview

```
ContentView / NodeView (block editing)
        │
        │ block changed → markDirty(blockId)
        ▼
┌─────────────────┐
│  DirtyTracker    │  In-memory Set<UUID> + idle timer
│  (@MainActor)    │
└────────┬────────┘
         │ flush triggers: focus loss, navigate, background, idle
         ▼
┌─────────────────┐
│  FTS5Database    │  Manages search.sqlite via C API
│  (actor)         │  Owns: dirty_blocks, index_metadata, vector_key_map,
│                  │        block_fts (created here, used by keyword search)
└─────────────────┘
```

### Component Details

#### 1. `FTS5Database` (Actor)

Location: `Noto/Search/FTS5Database.swift`

A Swift actor wrapping the SQLite C API. Owns the `search.sqlite` file lifecycle and provides type-safe query execution for all search tables.

```
actor FTS5Database {
    // Lifecycle
    init(directory: URL)          // opens or creates search.sqlite
    func close()                  // closes the database connection
    func destroy()                // deletes the .sqlite file (for rebuild)

    // DDL — called on init
    func createTablesIfNeeded()
    // Creates: block_fts, dirty_blocks, index_metadata, vector_key_map

    // Dirty tracking
    func markDirty(blockId: UUID, operation: DirtyOperation)
    func markDirtyBatch(blockIds: [UUID], operation: DirtyOperation)
    func fetchDirtyBatch(limit: Int) -> [(blockId: UUID, operation: DirtyOperation)]
    func removeDirty(blockIds: [UUID])
    func dirtyCount() -> Int

    // FTS5 operations (used by keyword search)
    func upsertBlock(blockId: UUID, content: String)
    func deleteBlock(blockId: UUID)
    func search(query: String) -> [(blockId: UUID, bm25Score: Double)]

    // Vector key mapping (used by semantic search)
    func getVectorKey(blockId: UUID) -> UInt64?
    func setVectorKey(blockId: UUID, key: UInt64)
    func removeVectorKey(blockId: UUID)
    func getBlockId(vectorKey: UInt64) -> UUID?

    // Metadata
    func getMetadata(key: String) -> String?
    func setMetadata(key: String, value: String)
}

enum DirtyOperation: String {
    case upsert
    case delete
}
```

**SQLite C API usage:**
- `sqlite3_open_v2` with `SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE`
- `sqlite3_prepare_v2` / `sqlite3_bind_text` / `sqlite3_step` / `sqlite3_finalize` for all queries
- Batch operations wrapped in `BEGIN TRANSACTION` / `COMMIT`
- All errors logged via `os_log` with `Logger(subsystem: "com.noto", category: "FTS5Database")`

**Database location:**
```swift
let searchDbUrl = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("search.sqlite")
```

For UI testing (`-UITesting` flag): use a temporary directory so tests are isolated.

#### 2. `DirtyTracker` (ObservableObject)

Location: `Noto/Search/DirtyTracker.swift`

Manages the in-memory dirty set and flush lifecycle. Shared between keyword and semantic indexing pipelines.

```
@MainActor
class DirtyTracker: ObservableObject {
    // In-memory tracking
    func markDirty(_ blockId: UUID)
    func markDeleted(_ blockId: UUID)

    // Flush to persistent dirty_blocks table
    func flush() async

    // Check state
    var hasDirtyBlocks: Bool { get }

    // Idle timer management
    func resetIdleTimer()
    func cancelIdleTimer()
}
```

**Internal state:**
- `changedBlockIds: Set<UUID>` — blocks with content changes, in-memory only
- `deletedBlockIds: Set<UUID>` — deleted blocks, flushed immediately
- `idleTimer: Task<Void, Never>?` — 5-second idle timer
- `fts5Database: FTS5Database` — reference to persist dirty marks

**Idle timer behavior:**
- Each call to `markDirty()` cancels the existing timer and starts a new 5-second one
- When the timer fires, calls `flush()`
- Timer is also cancelled on explicit `flush()` calls

**Flush logic:**
1. Move `changedBlockIds` into a local copy, clear the set
2. For each UUID in the copy: `fts5Database.markDirty(blockId:, operation: .upsert)`
3. `deletedBlockIds` are already flushed immediately on `markDeleted()`, so nothing to do for those

#### 3. `PlainTextExtractor`

Location: `Noto/Search/PlainTextExtractor.swift`

Strips markdown-like formatting from a single block's content string.

```
struct PlainTextExtractor {
    static func plainText(from content: String) -> String
}
```

**Algorithm:**
1. Remove bold markers: `**text**` → `text` (regex: `\*\*(.+?)\*\*`)
2. Remove italic markers: `*text*` → `text` (regex: `(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)`)
3. Remove strikethrough markers: `~~text~~` → `text`
4. Remove inline code markers: `` `text` `` → `text`
5. Remove list prefixes: leading `* `, `- `, `1. `, `- [x] `, `- [ ] `
6. Trim whitespace

Order matters — strip bold before italic (both use `*`).

The formatting conventions match `NoteTextStorage`'s `WordsFormatter` and `ListsFormatter`.

---

## Integration Points

### 1. Marking blocks dirty on content change

In `ContentView.syncContent()` and `NodeView`'s equivalent sync logic, after a block's content is updated:

```swift
dirtyTracker.markDirty(block.id)
```

The `DirtyTracker` is injected via the SwiftUI environment or passed as a dependency.

### 2. Marking blocks dirty on delete

When a block is deleted:

```swift
dirtyTracker.markDeleted(block.id)
```

### 3. Flushing on editing end

In `NoteTextEditor.Coordinator`, the `textViewDidEndEditing` callback:

```swift
func textViewDidEndEditing(_ textView: UITextView) {
    // existing code...
    Task { await dirtyTracker.flush() }
}
```

### 4. Flushing on navigation

On `ContentView` and `NodeView`:

```swift
.onDisappear {
    Task { await dirtyTracker.flush() }
}
```

### 5. Flushing on app background

In `NotoApp.swift`:

```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .background {
        Task { await dirtyTracker.flush() }
    }
}
```

### 6. FTS5Database initialization

In `NotoApp.swift`, create the database early:

```swift
let fts5Database = FTS5Database(directory: appSupportDir)
// For UI testing:
// let fts5Database = FTS5Database(directory: tempDir)
```

---

## File Structure

```
Noto/Search/
├── FTS5Database.swift        # Actor — SQLite C API wrapper, owns search.sqlite
├── DirtyTracker.swift        # ObservableObject — in-memory Set + flush lifecycle
└── PlainTextExtractor.swift  # Strips markdown from block content
```

---

## Testing Strategy

### Test Helpers

```swift
/// Creates a temp-file FTS5 database for testing.
func createTestFTS5Database() async throws -> (FTS5Database, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fts5-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let db = FTS5Database(directory: tempDir)
    await db.createTablesIfNeeded()
    return (db, tempDir)  // caller cleans up tempDir after test
}
```

### Unit Tests (Swift Testing)

#### FTS5Database

| Test | Setup | Assert |
|------|-------|--------|
| Creates tables on init | Open fresh database | Tables exist, no errors |
| Opens existing database | Create → close → reopen | Tables still exist, data preserved |
| Destroy deletes file | Create → destroy | File no longer exists |
| Concurrent access via actor | Multiple async calls | No data races, all complete |

#### DirtyTracker

| Test | Setup | Assert |
|------|-------|--------|
| markDirty accumulates | markDirty with 3 UUIDs | `hasDirtyBlocks == true` |
| Duplicate markDirty deduplicates | markDirty same UUID twice | Internal set has 1 entry |
| flush persists to dirty_blocks | markDirty → flush | `dirty_blocks` has entry; in-memory set empty |
| markDeleted writes immediately | markDeleted | `dirty_blocks` has "delete" entry before flush |
| Idle timer triggers flush | markDirty → wait 6 seconds | `dirty_blocks` populated |
| flush cancels idle timer | markDirty → flush immediately | Timer is nil |
| Multiple flush cycles | markDirty → flush → markDirty → flush | Both batches persisted |

#### Dirty Batch Operations

| Test | Setup | Assert |
|------|-------|--------|
| markDirtyBatch inserts multiple | Batch of 100 UUIDs | All 100 in dirty_blocks |
| fetchDirtyBatch respects limit | 100 dirty → fetch(limit: 50) | Returns 50 |
| removeDirty cleans up | Insert 5 → remove 3 | 2 remaining |
| dirtyCount accurate | Insert 10 → remove 4 | Count = 6 |

#### Vector Key Mapping

| Test | Setup | Assert |
|------|-------|--------|
| setVectorKey + getVectorKey | Set key for UUID | Same key returned |
| getBlockId reverse lookup | Set key → getBlockId | Correct UUID |
| removeVectorKey | Set → remove → get | Returns nil |
| Non-existent key | getVectorKey for unknown UUID | Returns nil |

#### Metadata

| Test | Setup | Assert |
|------|-------|--------|
| setMetadata + getMetadata | Set "key" = "value" | "value" returned |
| Non-existent key | getMetadata for unknown key | Returns nil |
| Update existing | Set → update → get | New value returned |

#### PlainTextExtractor

| Test | Input | Expected output |
|------|-------|----------------|
| Bold | `"**bold text**"` | `"bold text"` |
| Italic | `"*italic text*"` | `"italic text"` |
| Strikethrough | `"~~deleted~~"` | `"deleted"` |
| Inline code | `` "`codeSnippet`" `` | `"codeSnippet"` |
| List bullet | `"* list item"` | `"list item"` |
| List dash | `"- list item"` | `"list item"` |
| Numbered list | `"1. first item"` | `"first item"` |
| Checkbox checked | `"- [x] done task"` | `"done task"` |
| Checkbox unchecked | `"- [ ] open task"` | `"open task"` |
| Mixed formatting | `"**bold** and *italic*"` | `"bold and italic"` |
| No formatting | `"plain text"` | `"plain text"` |
| Empty string | `""` | `""` |

---

## Data Model Changes

Remove `SearchIndex` SwiftData model:
1. Delete `Noto/Models/SearchIndex.swift`
2. Remove `SearchIndex.self` from schema in `NotoApp.swift`
3. Remove `SearchIndex.self` from `createTestContainer()` in test helpers

Since `SearchIndex` has no relationships to other models, SwiftData auto-migration drops the table.

---

## Migration / Rollout

1. Remove `SearchIndex.self` from schema → auto-migration
2. `FTS5Database` creates `search.sqlite` on first init
3. All tables created via `createTablesIfNeeded()` — safe to call repeatedly
