# Spec: Keyword Search (FTS5)

Based on [PRD-keyword-search.md](./PRD-keyword-search.md).

---

## User Stories

1. **As a user**, I can search for blocks by exact words and see results ranked by relevance.
2. **As a user**, I can search for "running" and find blocks containing "run", "runs", "running" (stemming).
3. **As a user**, I can type a partial word with `*` and find prefix matches.
4. **As a user**, I can search with a date filter (applied by the hybrid search layer) and only see results from that time range.
5. **As a user**, my search index stays up to date without any noticeable lag while I'm writing.
6. **As a user**, if the app crashes or is force-killed, no data is lost — the index self-repairs on next launch.

---

## Acceptance Criteria

- [ ] FTS5 search returns blocks matching exact words, stemmed variants, and prefix queries
- [ ] Results are ranked by BM25 relevance (most relevant first)
- [ ] Markdown formatting is stripped before indexing (bold markers, list prefixes, etc.)
- [ ] Index updates do not block the main thread or cause UI jank while typing
- [ ] No SQLite writes occur during active typing — only on focus loss, navigation, background, or idle timeout
- [ ] After a dirty flush, newly created or edited blocks appear in search results
- [ ] Deleted blocks are removed from the FTS5 index
- [ ] If the app is force-killed mid-edit, the launch reconciliation recovers missed blocks
- [ ] If the FTS5 database is deleted, it can be fully rebuilt from SwiftData blocks
- [ ] The `SearchIndex` SwiftData model is removed from the schema
- [ ] FTS5 query latency is < 10ms for typical queries
- [ ] Date filtering works correctly when provided by the hybrid search layer

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
│  (shared)        │  Flushes to dirty_blocks on trigger
└────────┬────────┘
         │ flush triggers: focus loss, navigate, background, idle
         ▼
┌─────────────────┐
│  FTS5Database    │  Manages search.sqlite via C API
│  (actor)         │  Owns dirty_blocks + block_fts + index_metadata tables
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌──────────────┐
│FTS5    │ │FTS5Indexer   │
│Engine  │ │              │
│(query) │ │(flush dirty  │
│        │ │ to block_fts)│
└────────┘ └──────────────┘
```

### Component Details

#### 1. `FTS5Database` (Actor)

Location: `Noto/Search/FTS5Database.swift`

A Swift actor wrapping the SQLite C API. Owns the `search.sqlite` file lifecycle and provides type-safe query execution.

```
actor FTS5Database {
    // Lifecycle
    init(directory: URL)          // opens or creates search.sqlite
    func close()                  // closes the database connection
    func destroy()                // deletes the .sqlite file (for rebuild)

    // DDL — called on init
    func createTablesIfNeeded()
    // Creates: block_fts, dirty_blocks, index_metadata

    // Dirty tracking
    func markDirty(blockId: UUID, operation: DirtyOperation)
    func markDirtyBatch(blockIds: [UUID], operation: DirtyOperation)
    func fetchDirtyBatch(limit: Int) -> [(blockId: UUID, operation: DirtyOperation)]
    func removeDirty(blockIds: [UUID])
    func dirtyCount() -> Int

    // FTS5 operations
    func upsertBlock(blockId: UUID, content: String)
    func deleteBlock(blockId: UUID)
    func search(query: String) -> [(blockId: UUID, bm25Score: Double)]

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

**FTS5 table creation:**
```sql
CREATE VIRTUAL TABLE IF NOT EXISTS block_fts USING fts5(
    content,
    block_id UNINDEXED,
    tokenize='porter unicode61'
);
```

**Search query:**
```sql
SELECT block_id, rank FROM block_fts
WHERE block_fts MATCH ?
ORDER BY rank;
```

FTS5 `rank` returns negative BM25 scores (more negative = better match). Results are returned as-is — normalization happens in the hybrid ranking layer.

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

**Integration points (where flush is triggered):**

| Trigger | Where it happens |
|---------|-----------------|
| Block loses focus | `NoteTextEditor.Coordinator.textViewDidEndEditing` → calls `dirtyTracker.flush()` |
| Navigate away | View's `onDisappear` modifier on ContentView / NodeView |
| App backgrounds | `.onChange(of: scenePhase)` in `NotoApp.swift` when `.background` |
| Idle timeout | `DirtyTracker` internal 5-second timer |
| Search opens | Search sheet `onAppear` → triggers full indexing pipeline |
| Block deleted | `markDeleted()` writes to `dirty_blocks` immediately |

#### 3. `FTS5Indexer`

Location: `Noto/Search/FTS5Indexer.swift`

Reads dirty blocks from the database, fetches content from SwiftData, strips markdown, and writes to FTS5.

```
struct FTS5Indexer {
    let fts5Database: FTS5Database
    let modelContext: ModelContext

    // Flush all dirty blocks to FTS5 in batches
    func flushAll() async

    // Full rebuild from SwiftData (for first launch or corruption recovery)
    func rebuildAll() async
}
```

**`flushAll()` algorithm:**
1. Loop:
   a. Fetch batch of 50 from `dirty_blocks` via `fts5Database.fetchDirtyBatch(limit: 50)`
   b. If empty, break
   c. For each entry:
      - If `upsert`: fetch Block from SwiftData by ID, get `block.content`, strip markdown (see below), call `fts5Database.upsertBlock(blockId:content:)`
      - If `delete`: call `fts5Database.deleteBlock(blockId:)`
   d. Call `fts5Database.removeDirty(blockIds:)` for the processed batch
2. Update `index_metadata['lastFullReconciliationAt']` to current timestamp

**Markdown stripping:**

The PRD specifies using `NoteTextStorage.deformatted()`, but that method operates on a `NoteTextStorage` instance (NSTextStorage) and returns tab-indented text with the full document structure. For FTS5 indexing, we need just the plain text of a single block without tabs or formatting markers.

Approach: create a lightweight plain-text extractor that strips markdown markers from a block's `content` string directly. The block content in SwiftData stores inline markdown-like formatting (`**bold**`, `*italic*`, `~~strikethrough~~`, `` `code` ``).

```
func plainText(from content: String) -> String
```

Algorithm:
1. Remove bold markers: `**text**` → `text`
2. Remove italic markers: `*text*` → `text`
3. Remove strikethrough markers: `~~text~~` → `text`
4. Remove inline code markers: `` `text` `` → `text`
5. Remove list prefixes: leading `* `, `- `, `1. `, `- [x] `, `- [ ] `
6. Trim whitespace

This is simpler and more efficient than instantiating NoteTextStorage for each block. The formatting conventions are defined in `NoteTextStorage`'s `WordsFormatter` and `ListsFormatter`.

**`rebuildAll()` algorithm:**
1. Drop and recreate the `block_fts` table
2. Fetch all non-archived blocks from SwiftData
3. For each block: strip markdown, insert into FTS5
4. Process in batches of 100 within transactions
5. Clear `dirty_blocks` table
6. Update `lastFullReconciliationAt`

#### 4. `FTS5Engine`

Location: `Noto/Search/FTS5Engine.swift`

Query execution. Takes a search string, returns ranked results.

```
struct FTS5Engine {
    let fts5Database: FTS5Database

    func search(
        query: String,
        dateRange: DateRange?,
        modelContext: ModelContext
    ) async -> [KeywordSearchResult]
}

struct KeywordSearchResult {
    let blockId: UUID
    let bm25Score: Double
}

struct DateRange {
    let start: Date
    let end: Date
}
```

**Search algorithm:**
1. Sanitize the query string — escape special FTS5 characters (`"`, `*`, etc. in unexpected positions)
2. Call `fts5Database.search(query:)` → returns all matches with BM25 scores
3. If `dateRange` is provided:
   a. Collect all matched block IDs
   b. Fetch those blocks from SwiftData in one batch query: `FetchDescriptor<Block>` with `#Predicate { blockIds.contains($0.id) && $0.createdAt >= start && $0.createdAt <= end }`
   c. Filter FTS5 results to only include blocks that passed the date filter
4. Return filtered results sorted by BM25 score (most negative first = best match)

**Why post-filter instead of cross-database join:**
The FTS5 database and SwiftData are separate SQLite files. Cross-database joins aren't possible. Post-filtering is the same pattern used by HNSW semantic search, keeping both engines consistent.

**Query sanitization:**
FTS5 MATCH syntax has special characters. User input needs escaping:
- Wrap each search term in double quotes if it contains special chars
- Strip unbalanced quotes
- Preserve intentional `*` at end of words (prefix search)

#### 5. `IndexReconciler`

Location: `Noto/Search/IndexReconciler.swift`

Launch-time safety net that catches blocks missed by the dirty tracker (e.g., app force-killed before in-memory set was flushed).

```
struct IndexReconciler {
    let fts5Database: FTS5Database
    let modelContext: ModelContext

    func reconcileIfNeeded() async
}
```

**Algorithm:**
1. Read `lastFullReconciliationAt` from `index_metadata`
2. If nil (first launch): trigger full rebuild via `FTS5Indexer.rebuildAll()`, return
3. Check if `dirty_blocks` table is non-empty:
   - If empty: no crash recovery needed, just update `lastFullReconciliationAt`, return
   - If non-empty: possible data loss, proceed to step 4
4. Query SwiftData for all blocks where `updatedAt > lastFullReconciliationAt`
5. For each found block: `fts5Database.markDirty(blockId:, operation: .upsert)`
6. Flush via `FTS5Indexer.flushAll()`

**When this runs:**
- Called from `NotoApp.swift` on app launch, after the ModelContainer is initialized
- Runs on a background task, does not block app startup UI

---

## Data Model Changes

### Remove `SearchIndex`

Delete `Noto/Models/SearchIndex.swift` and remove `SearchIndex.self` from the schema array in `NotoApp.swift`:

```swift
// Before
Schema([
    Block.self, BlockLink.self, Tag.self, BlockTag.self,
    MetadataField.self, BlockEmbedding.self, SearchIndex.self,
])

// After
Schema([
    Block.self, BlockLink.self, Tag.self, BlockTag.self,
    MetadataField.self, BlockEmbedding.self,
])
```

This is a schema migration — SwiftData will need to handle the removed model. Since `SearchIndex` has no relationships to other models (it stores `blockId: UUID` as a plain field, not a SwiftData relationship), the migration is a simple table drop. Configure a lightweight migration plan or let SwiftData auto-migrate.

---

## File Structure

```
Noto/Search/
├── FTS5Database.swift       # Actor — SQLite C API wrapper, owns search.sqlite
├── DirtyTracker.swift       # ObservableObject — in-memory Set + flush lifecycle
├── FTS5Indexer.swift        # Batch flush dirty → FTS5, full rebuild
├── FTS5Engine.swift         # Query execution, BM25 results
├── IndexReconciler.swift    # Launch-time reconciliation safety net
└── PlainTextExtractor.swift # Strips markdown from block content
```

---

## Integration Points

### 1. Marking blocks dirty on content change

In `ContentView.syncContent()` and `NodeView`'s equivalent sync logic, after a block's content is updated:

```swift
// In syncContent(), after block.updateContent(newContent):
dirtyTracker.markDirty(block.id)
```

The `DirtyTracker` is injected via the SwiftUI environment or passed as a dependency.

### 2. Marking blocks dirty on delete

When a block is deleted (in `syncContent()` when excess blocks are removed, or explicit delete actions):

```swift
dirtyTracker.markDeleted(block.id)
```

### 3. Flushing on editing end

In `NoteTextEditor.Coordinator`, the `textViewDidEndEditing` callback already exists. Add a flush trigger:

```swift
func textViewDidEndEditing(_ textView: UITextView) {
    // existing code...
    Task { await dirtyTracker.flush() }
}
```

### 4. Flushing on navigation

On `ContentView` and `NodeView`, add `.onDisappear`:

```swift
.onDisappear {
    Task { await dirtyTracker.flush() }
}
```

### 5. Flushing on app background

In `NotoApp.swift`, observe scene phase:

```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .background {
        Task { await dirtyTracker.flush() }
        // Also trigger FTS5Indexer.flushAll() for best-effort indexing
    }
}
```

### 6. Launch reconciliation

In `NotoApp.swift`, after ModelContainer setup:

```swift
Task.detached(priority: .background) {
    let reconciler = IndexReconciler(fts5Database: fts5Database, modelContext: backgroundContext)
    await reconciler.reconcileIfNeeded()
}
```

### 7. Search open trigger

When the search sheet appears, before accepting queries:

```swift
// SearchSheet.onAppear
Task {
    await dirtyTracker.flush()
    await fts5Indexer.flushAll()
}
```

---

## Testing Strategy

### Unit Tests (Swift Testing)

| Test | What it verifies |
|------|-----------------|
| FTS5Database creates tables on init | Schema setup works |
| FTS5Database upsert + search returns match | Basic indexing and query |
| FTS5Database search with stemming | "running" matches "run" |
| FTS5Database search with prefix | "sema*" matches "semantic" |
| FTS5Database delete removes from results | Deletion works |
| FTS5Database BM25 ordering | More relevant results rank higher |
| DirtyTracker markDirty accumulates in set | In-memory tracking |
| DirtyTracker flush persists to dirty_blocks | Phase 2 works |
| DirtyTracker idle timer triggers flush | Timer fires after 5s |
| FTS5Indexer flushAll processes batches | Batch processing works |
| FTS5Indexer handles upsert and delete ops | Both operations work |
| PlainTextExtractor strips bold/italic/code | Markdown removal |
| PlainTextExtractor strips list prefixes | List prefix removal |
| IndexReconciler detects missed blocks | Reconciliation catches gaps |
| Date post-filtering excludes out-of-range | Date filter works |

### Test Helpers

```swift
// Creates an in-memory FTS5 database for testing
func createTestFTS5Database() -> FTS5Database {
    // Use ":memory:" or temp file
}
```

FTS5Database should accept an optional `path` override for testing with temporary files (SQLite FTS5 may not work with `:memory:` databases depending on configuration — use a temp directory file that's cleaned up after tests).

---

## Performance Considerations

- **Zero main-thread writes during typing:** DirtyTracker only does Set inserts on `@MainActor`. All SQLite writes happen in the FTS5Database actor (off main thread).
- **Batch transactions:** FTS5 inserts are committed in groups of 50 within a single SQLite transaction to minimize fsync overhead.
- **Lazy indexing:** No FTS5 work happens unless the user actually searches or the app backgrounds. Writing notes is completely unaffected.
- **Post-filter for dates:** SwiftData fetch for date filtering happens only if a date range is provided, and only for the block IDs returned by FTS5 (bounded set).

---

## Migration / Rollout

1. Remove `SearchIndex.self` from schema → SwiftData auto-migration drops the table
2. On first launch after update: `IndexReconciler` sees no `lastFullReconciliationAt` → triggers `FTS5Indexer.rebuildAll()` to build the FTS5 index from all existing blocks
3. Subsequent launches: incremental dirty tracking and flush
