# PRD: Keyword Search (FTS5)

## Overview

Full-text keyword search across all blocks using SQLite FTS5. Users can search by exact words, stemmed variants, prefix matches, and phrases. Returns results ranked by BM25 relevance.

**Scope:** Keyword search engine + indexing pipeline. Does not include the search UI or hybrid ranking — those are separate PRDs.

**Dependencies:** None (FTS5 is bundled with iOS's SQLite).

---

## Core Requirements

| Requirement | Implication |
|-------------|-------------|
| Search by exact words | FTS5 MATCH queries |
| Stemming ("running" → "run") | Porter tokenizer |
| Prefix search ("sema*") | FTS5 prefix queries |
| BM25 relevance ranking | FTS5 rank function |
| Offline-first | On-device SQLite, no network |
| No SwiftData conflicts | Separate `.sqlite` database file |
| Markdown stripped before indexing | Use `NoteTextStorage.deformatted()` |
| Date filtering support | Join block metadata on query |

---

## Storage

### Separate SQLite Database

FTS5 lives in a dedicated `search.sqlite` file managed via the SQLite C API. SwiftData has no native FTS5 support, and co-locating with SwiftData's database risks schema conflicts.

Location: app's Application Support directory alongside the SwiftData store.

If corrupted, the entire file can be deleted and rebuilt from SwiftData blocks.

### Schema

```sql
-- FTS5 virtual table for full-text search
CREATE VIRTUAL TABLE block_fts USING fts5(
    content,              -- block text content (markdown stripped)
    block_id UNINDEXED,   -- reference back to SwiftData Block (not searchable)
    tokenize='porter unicode61'  -- stemming + unicode normalization
);

-- Dirty tracking table for lazy sync
CREATE TABLE IF NOT EXISTS dirty_blocks (
    block_id TEXT PRIMARY KEY,
    operation TEXT NOT NULL DEFAULT 'upsert'  -- 'upsert' or 'delete'
);

-- Metadata table for reconciliation
CREATE TABLE IF NOT EXISTS index_metadata (
    key TEXT PRIMARY KEY,
    value TEXT
);
-- Stores: 'lastFullReconciliationAt' timestamp
```

---

## Indexing Pipeline

### Two-Phase Dirty Marking

**Phase 1 — In-memory tracking (while typing):**
- `syncContent` updates a block → add its UUID to an in-memory `Set<UUID>` of changed blocks
- Reset an idle timer on each change
- Zero overhead — just a Set insert

**Phase 2 — Persist to `dirty_blocks` table (on trigger):**
Flush the in-memory set to `dirty_blocks`. Triggers:
1. Block loses focus (tap another block or tap outside)
2. Navigate away (back button, switch notes)
3. App enters background (`scenePhase == .background`)
4. Idle timeout (~5-10s) — user stops typing but stays in the block

Block deletion writes to `dirty_blocks` immediately (discrete action, not continuous typing).

After flushing, clear the in-memory set.

### Lazy Flush to FTS5

FTS5 updates only happen when actually needed:

**On search open:** Flush all `dirty_blocks` to FTS5 in batches of ~50 before returning results. For each batch:
1. Read 50 rows from `dirty_blocks`
2. For `upsert`: fetch block content from SwiftData, strip markdown via `deformatted()`, `INSERT OR REPLACE` into `block_fts`
3. For `delete`: `DELETE FROM block_fts WHERE block_id = ?`
4. Delete processed rows from `dirty_blocks`
5. Commit the batch
6. Repeat until `dirty_blocks` is empty

**On app background:** Same flush, best-effort. At ~0.2ms per FTS5 insert, 5 seconds of background execution handles ~25,000 blocks.

**On app launch:** Two-phase catch-up:
1. Flush any remaining `dirty_blocks`
2. Timestamp reconciliation safety net — compare `block.updatedAt` against `lastFullReconciliationAt` to catch blocks that changed but were never marked dirty (crash before dirty insert)

### Crash Resilience

- Batch transactions (50 blocks each) — partial flush is safe, uncommitted blocks stay in `dirty_blocks`
- Force-kill before flush trigger: in-memory set lost, but launch reconciliation catches it
- FTS5 index is never corrupted, only potentially stale

---

## Query API

### Interface

The FTS5 engine exposes a search function that takes a query string and optional date filter, returns block IDs with BM25 scores.

```
FTS5Engine.search(query: String, dateRange: DateRange?) -> [(blockId: UUID, bm25Score: Double)]
```

### Query Execution

Basic search with date filter:
```sql
SELECT block_id, rank FROM block_fts
WHERE block_fts MATCH ?
AND block_id IN (
    SELECT id FROM blocks
    WHERE createdAt >= ? AND createdAt <= ?
)
ORDER BY rank;
```

Without date filter, omit the `AND block_id IN (...)` clause.

### BM25 Scoring

FTS5's `rank` column returns BM25 scores (negative values, more negative = better match). The hybrid ranking layer normalizes these to [0, 1] — that's not this PRD's concern.

### Threshold Filtering

Return all results above a minimum BM25 threshold. The threshold value is TBD — needs empirical tuning based on real data.

---

## Data Model Changes

**Remove `SearchIndex` SwiftData model.** FTS5 replaces its functionality entirely. The `dirty_blocks` table in the FTS5 database replaces any tracking role it might have served.

---

## Performance Targets

| Operation | Target |
|-----------|--------|
| FTS5 query | < 10ms |
| Single block FTS5 insert | ~0.2ms |
| Dirty mark (in-memory) | ~0ms |
| Dirty mark (persist to SQLite) | ~1ms |
| Batch flush 500 blocks | ~100ms |
| Full re-index 100K blocks | ~20s (background) |

---

## Components

| Component | Responsibility |
|-----------|---------------|
| `FTS5Database` | Manages the separate `search.sqlite` file. Opens/creates database, creates tables, handles raw SQLite C API calls. |
| `FTS5Engine` | Search query execution. Takes query string + optional filters, returns ranked block IDs with BM25 scores. |
| `DirtyTracker` | Manages the in-memory `Set<UUID>` and persists to `dirty_blocks` on trigger. Shared with semantic indexing pipeline. |
| `FTS5Indexer` | Flushes dirty blocks to FTS5. Reads block content from SwiftData, strips markdown, writes to FTS5 table. Handles batch processing. |
| `IndexReconciler` | Launch-time safety net. Compares SwiftData timestamps against `lastFullReconciliationAt`, marks missed blocks as dirty. |
