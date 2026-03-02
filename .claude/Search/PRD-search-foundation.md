# PRD: Search Foundation

## Overview

Shared infrastructure layer for Noto's search system. Provides the storage backend, dirty block tracking, markdown stripping, and shared type definitions used by all search components.

**Scope:** SQLite database management, dirty block tracking, plain text extraction, shared data types, schema migration.

**Dependencies:** None.

**Depended on by:** PRD-keyword-search, PRD-semantic-search, PRD-hybrid-search-and-ui.

---

## Core Requirements

| Requirement | Implication |
|-------------|-------------|
| No SwiftData conflicts | Separate `.sqlite` database file via C API |
| Zero main-thread writes during typing | In-memory dirty set, async SQLite writes |
| Crash-resilient dirty tracking | Persisted `dirty_blocks` table + launch reconciliation |
| Markdown stripped before indexing | Shared `PlainTextExtractor` for both pipelines |
| Shared between keyword + semantic pipelines | Single `DirtyTracker`, single database file |

---

## Storage

### Separate SQLite Database

Search infrastructure lives in a dedicated `search.sqlite` file managed via the SQLite C API. SwiftData has no native FTS5 support, and co-locating with SwiftData's database risks schema conflicts.

Location: app's Application Support directory alongside the SwiftData store.

If corrupted, the entire file can be deleted and rebuilt from SwiftData blocks.

### Schema (Foundation Tables)

```sql
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

-- UUID ↔ UInt64 mapping for HNSW index keys
CREATE TABLE IF NOT EXISTS vector_key_map (
    block_id TEXT PRIMARY KEY,
    vector_key INTEGER UNIQUE NOT NULL
);
```

Note: The FTS5 virtual table (`block_fts`) lives in this same database but is defined in PRD-keyword-search.

---

## Shared Data Types

```
DateRange {
    start: Date
    end: Date
}

DirtyOperation: String {
    case upsert
    case delete
}
```

---

## Two-Phase Dirty Marking

**Phase 1 — In-memory tracking (while typing):**
- `syncContent` updates a block → add its UUID to an in-memory `Set<UUID>`
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

### Crash Resilience

- Batch transactions (50 blocks each) — partial flush is safe, uncommitted blocks stay in `dirty_blocks`
- Force-kill before flush trigger: in-memory set lost, but launch reconciliation catches it (see PRD-keyword-search `IndexReconciler`)
- Indexes are never corrupted, only potentially stale

---

## Plain Text Extraction

Strips markdown-like formatting from block content. Both FTS5 indexing and embedding generation need the raw text without formatting markers.

Block content in SwiftData stores inline formatting (`**bold**`, `*italic*`, `~~strikethrough~~`, `` `code` ``).

**Algorithm:**
1. Remove bold markers: `**text**` → `text`
2. Remove italic markers: `*text*` → `text`
3. Remove strikethrough markers: `~~text~~` → `text`
4. Remove inline code markers: `` `text` `` → `text`
5. Remove list prefixes: leading `* `, `- `, `1. `, `- [x] `, `- [ ] `
6. Trim whitespace

---

## Data Model Changes

**Remove `SearchIndex` SwiftData model.** FTS5 replaces its functionality. Delete `Noto/Models/SearchIndex.swift` and remove `SearchIndex.self` from the schema array in `NotoApp.swift`. Since `SearchIndex` has no relationships to other models, the migration is a simple table drop.

---

## Components

| Component | Responsibility |
|-----------|---------------|
| `FTS5Database` | Manages the separate `search.sqlite` file. Opens/creates database, creates all tables (foundation + FTS5), handles raw SQLite C API calls. Actor-isolated for thread safety. |
| `DirtyTracker` | Manages the in-memory `Set<UUID>` and persists to `dirty_blocks` on trigger. Shared by keyword and semantic indexing pipelines. |
| `PlainTextExtractor` | Strips markdown formatting from block content. Returns plain text for both FTS5 indexing and embedding generation. |

---

## Performance Targets

| Operation | Target |
|-----------|--------|
| Dirty mark (in-memory) | ~0ms |
| Dirty mark (persist to SQLite) | ~1ms |
| Plain text extraction | < 0.1ms per block |

---

## Testing Strategy

### Unit Tests

| Area | What to test |
|------|-------------|
| **FTS5Database lifecycle** | Creates tables on init; opens existing database; `destroy()` deletes file; handles concurrent access via actor isolation |
| **Dirty tracking (in-memory)** | `markDirty()` accumulates set; duplicate UUIDs deduplicated; `hasDirtyBlocks` reflects state |
| **Dirty tracking (flush)** | `flush()` persists to `dirty_blocks` table; in-memory set cleared after flush; `markDeleted()` writes immediately |
| **Idle timer** | Timer fires after timeout; `markDirty()` resets timer; explicit `flush()` cancels timer |
| **Batch operations** | `markDirtyBatch()` inserts multiple rows; `fetchDirtyBatch(limit:)` respects limit; `removeDirty()` cleans up processed entries |
| **PlainTextExtractor** | Strips bold, italic, strikethrough, inline code, list prefixes; handles mixed formatting; preserves unformatted text; empty string → empty string |
| **Metadata** | `setMetadata`/`getMetadata` round-trip; non-existent key returns nil |

### Test Approach

- `FTS5Database` tests use a temp-file SQLite database (not `:memory:` — FTS5 may require file-backed storage). Cleaned up after each test.
- `DirtyTracker` tests verify both in-memory state and persisted `dirty_blocks` table.
- `PlainTextExtractor` tests are pure string-in/string-out — no database dependency.
