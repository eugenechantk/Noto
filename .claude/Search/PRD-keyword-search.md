# PRD: Keyword Search (FTS5)

## Overview

Full-text keyword search across all blocks using SQLite FTS5. Users can search by exact words, stemmed variants, prefix matches, and phrases. Returns results ranked by BM25 relevance.

**Scope:** FTS5 virtual table, keyword search engine, indexing pipeline, launch reconciliation.

**Dependencies:** PRD-search-foundation (FTS5Database, DirtyTracker, PlainTextExtractor, DateRange).

**Can run in parallel with:** PRD-semantic-search (after foundation is complete).

---

## Core Requirements

| Requirement | Implication |
|-------------|-------------|
| Search by exact words | FTS5 MATCH queries |
| Stemming ("running" → "run") | Porter tokenizer |
| Prefix search ("sema*") | FTS5 prefix queries |
| BM25 relevance ranking | FTS5 rank function |
| Offline-first | On-device SQLite, no network |
| Markdown stripped before indexing | `PlainTextExtractor` from foundation |
| Date filtering support | Post-filter via SwiftData join |

---

## FTS5 Virtual Table

Lives in the foundation's `search.sqlite` database, created by `FTS5Database`.

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS block_fts USING fts5(
    content,              -- block text content (markdown stripped)
    block_id UNINDEXED,   -- reference back to SwiftData Block (not searchable)
    tokenize='porter unicode61'  -- stemming + unicode normalization
);
```

---

## Indexing Pipeline

### Lazy Flush to FTS5

FTS5 updates only happen when actually needed. The `DirtyTracker` (from foundation) marks blocks dirty; this component reads and processes them.

**On search open:** Flush all `dirty_blocks` to FTS5 in batches of ~50 before returning results. For each batch:
1. Read 50 rows from `dirty_blocks`
2. For `upsert`: fetch block content from SwiftData, strip markdown via `PlainTextExtractor`, `INSERT OR REPLACE` into `block_fts`
3. For `delete`: `DELETE FROM block_fts WHERE block_id = ?`
4. Delete processed rows from `dirty_blocks`
5. Commit the batch
6. Repeat until `dirty_blocks` is empty

**On app background:** Same flush, best-effort. At ~0.2ms per FTS5 insert, 5 seconds of background execution handles ~25,000 blocks.

**On app launch:** Flush any remaining `dirty_blocks`, then run `IndexReconciler`.

---

## Query API

### Interface

```
FTS5Engine.search(query: String, dateRange: DateRange?) -> [(blockId: UUID, bm25Score: Double)]
```

### Query Execution

```sql
SELECT block_id, rank FROM block_fts
WHERE block_fts MATCH ?
ORDER BY rank;
```

Without date filter, return all matches. With date filter, post-filter results against SwiftData `createdAt` (cross-database join not possible — FTS5 and SwiftData are separate SQLite files).

### BM25 Scoring

FTS5's `rank` column returns negative BM25 scores (more negative = better match). Normalization to [0, 1] happens in the hybrid ranking layer (separate PRD).

### Threshold Filtering

Return all results above a minimum BM25 threshold. The threshold value is TBD — needs empirical tuning.

---

## Components

| Component | Responsibility |
|-----------|---------------|
| `FTS5Engine` | Search query execution. Takes query string + optional date filter, returns ranked block IDs with BM25 scores. Handles query sanitization. |
| `FTS5Indexer` | Flushes dirty blocks to FTS5. Reads block content from SwiftData, strips markdown via `PlainTextExtractor`, writes to FTS5. Handles batch processing and full rebuilds. |
| `IndexReconciler` | Launch-time safety net. Compares SwiftData `updatedAt` timestamps against `lastFullReconciliationAt` to catch blocks missed by dirty tracking (crash before flush). |

---

## Performance Targets

| Operation | Target |
|-----------|--------|
| FTS5 query | < 10ms |
| Single block FTS5 insert | ~0.2ms |
| Batch flush 500 blocks | ~100ms |
| Full re-index 100K blocks | ~20s (background) |

---

## Testing Strategy

### Unit Tests

| Area | What to test |
|------|-------------|
| **FTS5 query correctness** | Exact word match, stemmed match ("running" → "run"), prefix match ("sema*"), phrase match, no-match returns empty |
| **BM25 ranking** | Multi-result queries return results ordered by relevance; more specific matches rank higher |
| **Upsert/delete** | Upsert updates content; delete removes from results; re-upsert after delete works |
| **Batch indexing** | `FTS5Indexer.flushAll()` processes upserts and deletes in batches; partially flushed state is recoverable |
| **Full rebuild** | `rebuildAll()` re-indexes all blocks; results match incremental index |
| **Launch reconciliation** | `IndexReconciler` detects blocks with `updatedAt > lastFullReconciliationAt`; first launch triggers full rebuild |
| **Date post-filtering** | Results correctly filtered when date range provided; out-of-range blocks excluded |
| **Query sanitization** | Special FTS5 characters escaped; unbalanced quotes handled; intentional `*` preserved |

### Test Approach

- FTS5 engine tests insert `(blockId, content)` tuples directly into the FTS5 database — no SwiftData Block model needed.
- `FTS5Indexer` tests need a SwiftData in-memory container alongside the FTS5 test database.
- `IndexReconciler` tests need blocks with controlled `updatedAt` timestamps.
