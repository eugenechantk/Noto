# Spec: Keyword Search (FTS5)

Based on [PRD-keyword-search.md](./PRD-keyword-search.md).

**Dependencies:** Spec-search-foundation (FTS5Database, DirtyTracker, PlainTextExtractor).

---

## User Stories

1. **As a user**, I can search for blocks by exact words and see results ranked by relevance.
2. **As a user**, I can search for "running" and find blocks containing "run", "runs", "running" (stemming).
3. **As a user**, I can type a partial word with `*` and find prefix matches.
4. **As a user**, I can search with a date filter and only see results from that time range.
5. **As a user**, my search index stays up to date without noticeable lag while writing.
6. **As a user**, if the app crashes or is force-killed, no data is lost — the index self-repairs on next launch.

---

## Acceptance Criteria

- [ ] FTS5 search returns blocks matching exact words, stemmed variants, and prefix queries
- [ ] Results are ranked by BM25 relevance (most relevant first)
- [ ] Markdown formatting is stripped before indexing (via `PlainTextExtractor` from foundation)
- [ ] Index updates do not block the main thread or cause UI jank while typing
- [ ] After a dirty flush, newly created or edited blocks appear in search results
- [ ] Deleted blocks are removed from the FTS5 index
- [ ] If the app is force-killed mid-edit, `IndexReconciler` recovers missed blocks on launch
- [ ] If the FTS5 database is deleted, `rebuildAll()` fully reconstructs the index
- [ ] FTS5 query latency is < 10ms for typical queries
- [ ] Date filtering works correctly via post-filter against SwiftData

---

## Technical Design

### Architecture Overview

```
DirtyTracker (from foundation)
         │
         │ dirty_blocks table
         ▼
┌─────────────────┐
│  FTS5Database    │  (from foundation)
│                  │
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
                  │
                  ▼
          ┌──────────────┐
          │IndexReconciler│
          │(launch-time   │
          │ safety net)   │
          └──────────────┘
```

### Component Details

#### 1. `FTS5Engine`

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

#### 2. `FTS5Indexer`

Location: `Noto/Search/FTS5Indexer.swift`

Reads dirty blocks from the database, fetches content from SwiftData, strips markdown, and writes to FTS5.

```
struct FTS5Indexer {
    let fts5Database: FTS5Database
    let modelContext: ModelContext

    func flushAll() async
    func rebuildAll() async
}
```

**`flushAll()` algorithm:**
1. Loop:
   a. Fetch batch of 50 from `dirty_blocks` via `fts5Database.fetchDirtyBatch(limit: 50)`
   b. If empty, break
   c. For each entry:
      - If `upsert`: fetch Block from SwiftData by ID, get `block.content`, strip via `PlainTextExtractor.plainText(from:)`, call `fts5Database.upsertBlock(blockId:content:)`
      - If `delete`: call `fts5Database.deleteBlock(blockId:)`
   d. Call `fts5Database.removeDirty(blockIds:)` for the processed batch
2. Update `index_metadata['lastFullReconciliationAt']` to current timestamp

**`rebuildAll()` algorithm:**
1. Drop and recreate the `block_fts` table
2. Fetch all non-archived blocks from SwiftData
3. For each block: strip markdown, insert into FTS5
4. Process in batches of 100 within transactions
5. Clear `dirty_blocks` table
6. Update `lastFullReconciliationAt`

#### 3. `IndexReconciler`

Location: `Noto/Search/IndexReconciler.swift`

Launch-time safety net that catches blocks missed by dirty tracking (e.g., app force-killed before flush).

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
   - If empty and no missed blocks: update `lastFullReconciliationAt`, return
   - If non-empty: proceed to step 4
4. Query SwiftData for all blocks where `updatedAt > lastFullReconciliationAt`
5. For each found block: `fts5Database.markDirty(blockId:, operation: .upsert)`
6. Flush via `FTS5Indexer.flushAll()`

**When this runs:**
- Called from `NotoApp.swift` on app launch, after the ModelContainer is initialized
- Runs on a background task, does not block app startup UI

---

## Integration Points

### 1. Search open trigger

When the search sheet appears, flush FTS5:

```swift
// Part of SearchService.ensureIndexFresh()
await dirtyTracker.flush()
await fts5Indexer.flushAll()
```

### 2. Launch reconciliation

In `NotoApp.swift`, after ModelContainer setup:

```swift
Task.detached(priority: .background) {
    let reconciler = IndexReconciler(fts5Database: fts5Database, modelContext: backgroundContext)
    await reconciler.reconcileIfNeeded()
}
```

---

## File Structure

```
Noto/Search/
├── FTS5Engine.swift          # Query execution, BM25 results, date post-filtering
├── FTS5Indexer.swift         # Batch flush dirty → FTS5, full rebuild
└── IndexReconciler.swift     # Launch-time reconciliation safety net
```

---

## Testing Strategy

### Design Principle

FTS5 engine tests operate on FTS5's own SQLite database — insert `(blockId, content)` tuples directly. `FTS5Indexer` tests additionally need a SwiftData in-memory container for fetching block content.

### Unit Tests (Swift Testing)

#### FTS5Engine (Query)

| Test | Setup | Assert |
|------|-------|--------|
| Exact word match | Insert "the taste of coffee" | Search "coffee" returns it |
| Stemmed match | Insert "she was running fast" | Search "run" returns it |
| Prefix match | Insert "semantic search engine" | Search "sema*" returns it |
| Phrase match | Insert "design system guidelines" | Search `"design system"` returns it |
| No match returns empty | Insert "apple banana cherry" | Search "quantum" returns `[]` |
| BM25 ordering | A with "coffee" 3x, B with "coffee" 1x | A before B |
| Multiple terms | Insert several blocks | Search "coffee taste" ranks blocks with both words higher |

#### FTS5Engine (Date Post-Filtering)

| Test | Setup | Assert |
|------|-------|--------|
| No date filter returns all | 3 matching blocks, no dateRange | All 3 returned |
| Date filter includes in-range | Block A (today), B (last month) | dateRange=today → only A |
| Date filter excludes out-of-range | Block created 2 weeks ago | dateRange=today → not returned |
| Empty FTS5 + date filter | No matching content | Returns `[]` |

#### FTS5Indexer

| Test | Setup | Assert |
|------|-------|--------|
| flushAll processes upserts | Block in SwiftData → mark dirty → flushAll | Content searchable in FTS5 |
| flushAll processes deletes | Index → mark deleted → flushAll | No longer in FTS5 |
| Batch processing | 150 dirty blocks → flushAll | All 150 indexed |
| rebuildAll from scratch | Existing blocks, no index | Full index built |
| Updates lastFullReconciliationAt | flushAll | Metadata timestamp updated |

#### IndexReconciler

| Test | Setup | Assert |
|------|-------|--------|
| First launch triggers rebuild | No `lastFullReconciliationAt` | `rebuildAll()` called |
| Clean state skips reconciliation | Empty dirty_blocks, recent timestamp | No work done |
| Detects missed blocks | Block updatedAt > lastReconciliation | Block marked dirty |

#### Query Sanitization

| Test | Input | Expected |
|------|-------|----------|
| Normal query | `"hello world"` | Passed through unchanged |
| Special chars escaped | `"hello "world""` | Unbalanced quotes stripped |
| Prefix preserved | `"sema*"` | `*` kept at end of word |
| Empty query | `""` | Returns empty results |

---

## Performance Considerations

- **Zero main-thread writes during typing:** All SQLite writes happen in the FTS5Database actor.
- **Batch transactions:** FTS5 inserts committed in groups of 50 within a single SQLite transaction.
- **Lazy indexing:** No FTS5 work unless the user actually searches or the app backgrounds.
- **Post-filter for dates:** SwiftData fetch only for block IDs returned by FTS5 (bounded set).

---

## Migration / Rollout

1. On first launch: `IndexReconciler` sees no `lastFullReconciliationAt` → triggers `FTS5Indexer.rebuildAll()`
2. Subsequent launches: incremental dirty tracking and flush
