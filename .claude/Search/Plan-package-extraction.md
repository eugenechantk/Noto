# Plan: Extract Search into Swift Packages

Extracts the monolithic Noto search implementation into standalone Swift packages for independent testing, CLI tooling, and faster iteration.

---

## Package Structure

```
NotoModels/           SwiftData models
NotoCore/             Shared utilities
NotoDirtyTracker/     Dirty block tracking (shared between keyword + semantic indexing)
NotoFTS5/             FTS5 keyword search pipeline
NotoEmbedding/        CoreML text-to-vector inference
NotoHNSW/             HNSW vector storage + embedding indexing
NotoSearch/           Search orchestration + hybrid ranking
NotoTodayNotes/       Today's Notes date-aware hierarchy
```

## Dependency Graph

```
NotoModels                     (no dependencies)
    ^
NotoCore                       (NotoModels)
    ^
NotoDirtyTracker               (NotoModels, NotoCore)
    ^
    |-- NotoFTS5               (NotoModels, NotoCore, NotoDirtyTracker)
    |-- NotoEmbedding          (no dependencies - pure CoreML inference)
    |-- NotoHNSW               (NotoModels, NotoCore, NotoDirtyTracker, NotoEmbedding)
    |-- NotoTodayNotes         (NotoModels, NotoCore)
    |
    '-- NotoSearch             (NotoModels, NotoCore, NotoDirtyTracker,
                                NotoFTS5, NotoHNSW, NotoEmbedding)

Noto (app target)              (all packages + SwiftUI/UIKit)
```

---

## Package Details

### 1. NotoModels

SwiftData `@Model` classes. Leaf dependency — everything else depends on this.

**Contents:**
- `Block.swift`
- `BlockEmbedding.swift`
- `BlockLink.swift`
- `Tag.swift`
- `BlockTag.swift`
- `MetadataField.swift`

**Dependencies:** SwiftData framework only.

**Notes:**
- No UIKit, no SwiftUI imports
- Test helper `createTestContainer()` moves here (in-memory ModelContainer factory)

---

### 2. NotoCore

Widely-used utilities with no search-specific logic. Depended on by most other packages.

**Contents:**
- `PlainTextExtractor.swift` — strips markdown formatting from block content
- `BlockBuilder.swift` — creates blocks with specific configurations
- `BreadcrumbBuilder.swift` — walks Block parent chain, produces "Home / Projects / Ideas" strings

**Dependencies:** NotoModels

**Notes:**
- PlainTextExtractor is consumed by both NotoFTS5 (strips markdown before FTS5 indexing) and NotoHNSW (strips markdown before embedding). Putting it here avoids a cross-dependency.

---

### 3. NotoDirtyTracker

Shared dirty block tracking. Both keyword (FTS5) and semantic (HNSW) indexing pipelines consume the dirty set.

**Contents:**
- `DirtyStore.swift` (actor) — owns `dirty.sqlite` with two tables:
  - `dirty_blocks` (blockId TEXT, operation TEXT, timestamp TEXT)
  - `index_metadata` (key TEXT PRIMARY KEY, value TEXT)
- `DirtyTracker.swift` (@MainActor ObservableObject) — in-memory `Set<UUID>`, idle timer, flush to DirtyStore

**Current location of this logic:** `FTS5Database` actor (dirty_blocks + index_metadata tables) and `DirtyTracker.swift`.

**Refactoring required:**
1. Extract `dirty_blocks` and `index_metadata` table management from `FTS5Database` into new `DirtyStore` actor
2. `DirtyStore` manages its own `dirty.sqlite` file (separate from FTS5's `search.sqlite`)
3. `DirtyTracker` references `DirtyStore` instead of `FTS5Database`
4. `DirtyStore` exposes same API as current FTS5Database dirty methods:
   - `markDirty(blockId:operation:)`, `markDirtyBatch(blockIds:operation:)`
   - `fetchDirtyBatch(limit:)`, `removeDirty(blockIds:)`, `dirtyCount()`
   - `clearDirtyBlocks()`
   - `getMetadata(key:)`, `setMetadata(key:value:)`

**Dependencies:** NotoModels, NotoCore

**SQLite file:** `dirty.sqlite` in Application Support (or temp dir for testing)

---

### 4. NotoFTS5

Full keyword search pipeline. Self-contained from indexing to query execution.

**Contents:**
- `FTS5Database.swift` (actor) — owns `search.sqlite` with one table:
  - `block_fts` (FTS5 virtual table: blockId, content, tokenize=porter)
- `FTS5Engine.swift` — query execution with BM25 ranking, date post-filtering via SwiftData
- `FTS5Indexer.swift` — batch flush dirty blocks to FTS5, full rebuild from SwiftData
- `IndexReconciler.swift` — launch-time safety net, catches blocks missed by dirty tracking

**Refactoring required:**
1. Remove `dirty_blocks`, `index_metadata`, and `vector_key_map` table management from `FTS5Database`
2. `FTS5Database` shrinks to only managing `block_fts` in `search.sqlite`
3. `FTS5Indexer` reads dirty blocks from `DirtyStore` (NotoDirtyTracker) instead of `FTS5Database`
4. `IndexReconciler` reads `lastFullReconciliationAt` from `DirtyStore` instead of `FTS5Database`
5. `FTS5Engine` and `FTS5Indexer` use `PlainTextExtractor` from NotoCore

**Dependencies:** NotoModels, NotoCore, NotoDirtyTracker

**SQLite file:** `search.sqlite` in Application Support (block_fts only)

---

### 5. NotoEmbedding

Pure CoreML inference. Text in, `[Float]` out. No vector storage, no search logic.

**Contents:**
- `EmbeddingModel.swift` — CoreML wrapper for bge-small-en-v1.5, 384-dim normalized embeddings
- `Tokenizer/BertTokenizer.swift` — full BERT tokenization pipeline
- `Tokenizer/WordPieceTokenizer.swift` — subword tokenization
- `Resources/bge-small-en-v1.5.mlmodelc/` — CoreML model bundle (~33MB)
- `Resources/vocab.txt` — BERT vocabulary

**Dependencies:** CoreML framework only. No other Noto packages.

**Notes:**
- Completely standalone — can be tested in a CLI without any other package
- `embed(_ text: String) throws -> [Float]` is the only public API that matters
- CLI can benchmark inference latency, test tokenization edge cases, compare outputs

---

### 6. NotoHNSW

Vector storage, embedding indexing pipeline, and UUID-to-key mapping.

**Contents:**
- `HNSWIndex.swift` — usearch wrapper with UUID<->UInt64 key mapping
- `VectorKeyStore.swift` (actor) — owns `vectors.sqlite` with one table:
  - `vector_key_map` (blockId TEXT PRIMARY KEY, vectorKey INTEGER)
- `EmbeddingIndexer.swift` — processes dirty blocks: strip markdown -> check word count -> check content hash -> embed via NotoEmbedding -> HNSW insert

**Current location of vector_key_map:** `FTS5Database` actor.

**Refactoring required:**
1. Extract `vector_key_map` table management from `FTS5Database` into `VectorKeyStore` actor
2. `VectorKeyStore` manages its own `vectors.sqlite` (or use a single file alongside the `.usearch` index)
3. `HNSWIndex` references `VectorKeyStore` instead of `FTS5Database`
4. `EmbeddingIndexer` calls `NotoEmbedding.embed()` for inference, `HNSWIndex.add()` for storage
5. `EmbeddingIndexer` reads dirty blocks from `DirtyStore` (NotoDirtyTracker)
6. `EmbeddingIndexer` uses `PlainTextExtractor` from NotoCore

**Dependencies:** NotoModels, NotoCore, NotoDirtyTracker, NotoEmbedding, USearch (SPM)

**Files on disk:**
- `vectors.usearch` — HNSW binary index
- `vectors.sqlite` — vector_key_map table

---

### 7. NotoSearch

Search orchestration and hybrid ranking. Ties all search packages together.

**Contents:**
- `SearchService.swift` — single entry point: flush dirty -> parse date -> parallel search -> hybrid rank -> build results
- `SemanticEngine.swift` — embed query via NotoEmbedding -> search HNSW via NotoHNSW -> similarity threshold -> date post-filter
- `HybridRanker.swift` — score normalization (BM25 + cosine) and weighted combination (alpha=0.6)
- `DateFilterParser.swift` — extracts temporal phrases ("today", "last week", "in March 2024") from query strings
- `SearchTypes.swift` — shared types: DateRange, SearchQuery, SearchResult, KeywordSearchResult, SemanticSearchResult, RankedResult

**Dependencies:** NotoModels, NotoCore, NotoDirtyTracker, NotoFTS5, NotoHNSW, NotoEmbedding

**Notes:**
- `SemanticEngine` lives here (not in NotoHNSW) because it calls both NotoEmbedding (embed query) and NotoHNSW (search vectors)
- `DateFilterParser` lives here because it's query-level interpretation, not an indexing concern
- When semantic search is unavailable (`#if canImport(USearch)` fails), HybridRanker falls back to alpha=1.0 (pure keyword)

---

### 8. NotoTodayNotes

Date-aware block hierarchy for Today's Notes feature. Unrelated to search.

**Contents:**
- `TodayNotesService.swift` — creates/manages Today's Notes root, year/month/week/day hierarchy

**Dependencies:** NotoModels, NotoCore

---

## App Target (Noto)

After extraction, the app target contains only UI and lifecycle code:

```
Noto/
├── NotoApp.swift              — lifecycle, environment wiring, launch reconciliation
├── ContentView.swift          — NavigationStack owner
├── Views/
│   ├── OutlineView.swift      — text editing + block management
│   ├── SearchSheet.swift      — search UI (presents SearchService results)
│   ├── Toolbar.swift          — liquid glass components
│   ├── ScrollableBreadcrumb.swift
│   └── DebugPanelView.swift
└── TextKit/                   — UIKit TextKit 1 stack
    ├── NoteTextStorage.swift
    ├── NoteTextView.swift
    ├── NoteTextEditor.swift
    ├── CheckmarkView.swift
    └── StringHelpers.swift
```

---

## SQLite Files After Extraction

Three SQLite files, each owned by one package:

| File | Package | Tables |
|------|---------|--------|
| `dirty.sqlite` | NotoDirtyTracker | dirty_blocks, index_metadata |
| `search.sqlite` | NotoFTS5 | block_fts |
| `vectors.sqlite` | NotoHNSW | vector_key_map |

Plus the binary HNSW index: `vectors.usearch` (NotoHNSW).

All stored in Application Support. UI testing mode uses temp directories.

---

## CLI Targets

Each package can expose a CLI executable for testing without Xcode rebuilds:

```swift
// Package.swift
targets: [
    .executableTarget(name: "NotoFTS5CLI", dependencies: ["NotoFTS5"]),
    .executableTarget(name: "NotoEmbeddingCLI", dependencies: ["NotoEmbedding"]),
]
```

**NotoFTS5CLI:** Index text files from stdin, run queries, print BM25 scores.
**NotoEmbeddingCLI:** Embed text from stdin, print vectors, benchmark latency.
**NotoHNSWCLI:** Build vector index from embeddings, run similarity search.
**NotoSearchCLI:** Full pipeline — seed in-memory SwiftData, index, search, print ranked results with breadcrumbs.

---

## Execution Order

### Phase 1: Create package structure + move models
1. Create `NotoModels` package with all `@Model` classes
2. Create `NotoCore` package with PlainTextExtractor, BlockBuilder, BreadcrumbBuilder
3. Update app target to import both packages
4. Verify build + all existing tests pass

### Phase 2: Extract dirty tracking
5. Create `NotoDirtyTracker` package
6. Extract dirty_blocks + index_metadata from FTS5Database into DirtyStore actor
7. Update DirtyTracker to reference DirtyStore
8. Update all consumers (FTS5Indexer, IndexReconciler, EmbeddingIndexer, SearchService)
9. Verify build + tests

### Phase 3: Extract search packages
10. Create `NotoFTS5` package (FTS5Database shrinks to block_fts only)
11. Create `NotoEmbedding` package (EmbeddingModel + tokenizers)
12. Create `NotoHNSW` package (HNSWIndex + VectorKeyStore + EmbeddingIndexer)
13. Create `NotoSearch` package (SearchService, SemanticEngine, HybridRanker, DateFilterParser, SearchTypes)
14. Verify build + tests

### Phase 4: Extract remaining
15. Create `NotoTodayNotes` package
16. Clean up app target imports
17. Verify full build + all tests

### Phase 5: CLI targets
18. Add CLI executable targets to packages that benefit from it
19. Test CLI workflows
