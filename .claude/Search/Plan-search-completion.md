# Plan: Complete Search Implementation

Remaining tasks to get search fully functional with both keyword and semantic pipelines.

---

## Current State

- Keyword search pipeline works end-to-end: FTS5Database, FTS5Indexer, FTS5Engine, DirtyTracker, IndexReconciler
- SearchService orchestrates keyword search and hybrid ranking, but semantic search is **stubbed as empty**
- All semantic files (SemanticEngine, EmbeddingIndexer, HNSWIndex, EmbeddingModel, BertTokenizer, WordPieceTokenizer) are written but guarded behind `#if canImport(USearch)` — they compile-skip today
- SearchSheet UI is complete, wired to SearchService
- 204 tests pass (keyword + hybrid + breadcrumb + tokenizer logic tests)

---

## Task 1: Add USearch SPM Dependency

USearch is the HNSW vector index library. All semantic search code imports it.

**Steps:**
1. Add the `unum-cloud/usearch` Swift package to `Noto.xcodeproj`:
   - URL: `https://github.com/unum-cloud/usearch`
   - Version: latest stable (2.x)
   - Link `USearch` framework to the Noto app target and NotoTests target
2. Verify `#if canImport(USearch)` blocks now compile in:
   - `HNSWIndex.swift`
   - `EmbeddingIndexer.swift`
   - `SemanticEngine.swift`
   - `SemanticSearchTests.swift`
3. Build and confirm no new errors

**Risk:** USearch SPM may have platform restrictions. Confirm it supports iOS 18+ / macOS 15+. If the Swift package doesn't work natively, fall back to adding USearch as a vendored xcframework.

---

## Task 2: Bundle CoreML Model + Vocabulary

EmbeddingModel loads `bge-small-en-v1_5.mlmodelc` and `vocab.txt` from the app bundle.

**Steps:**
1. Run the conversion script to produce the `.mlpackage`:
   ```bash
   cd /Users/eugenechan/dev/personal/Noto
   uv run --with coremltools --with transformers --with torch --with numpy \
       python scripts/convert_model.py
   ```
   This produces:
   - `Noto/Search/Resources/bge-small-en-v1_5.mlpackage`
   - `Noto/Search/Resources/vocab.txt`

2. Compile the `.mlpackage` to `.mlmodelc`:
   ```bash
   xcrun coremlcompiler compile \
       Noto/Search/Resources/bge-small-en-v1_5.mlpackage \
       Noto/Search/Resources/
   ```
   This produces `Noto/Search/Resources/bge-small-en-v1_5.mlmodelc/` directory.

3. Add both resources to the Xcode project:
   - `Noto/Search/Resources/bge-small-en-v1_5.mlmodelc` (directory reference)
   - `Noto/Search/Resources/vocab.txt`
   - Ensure both are in the "Copy Bundle Resources" build phase
   - Since we use PBXFileSystemSynchronizedRootGroup, placing files under `Noto/Search/Resources/` should auto-include them — verify in Xcode

4. Verify EmbeddingModel initializes without error:
   - Add a quick sanity test that loads the model and embeds a short string
   - Confirm output is 384-dim and L2-normalized (norm ≈ 1.0)

**Size:** The `.mlmodelc` is ~33MB. This is the largest addition to the app bundle.

**Note:** The `.mlpackage` is an intermediate artifact and should be gitignored (only `.mlmodelc` and `vocab.txt` go into the repo).

---

## Task 3: Wire EmbeddingIndexer into SearchService

Currently `SearchService.ensureIndexFresh()` only flushes FTS5. It needs to also process dirty blocks through the embedding pipeline.

**Changes to SearchService.swift:**

1. Add semantic infrastructure fields (behind `#if canImport(USearch)`):
   ```
   #if canImport(USearch)
   private let embeddingModel: EmbeddingModel?
   private let hnswIndex: HNSWIndex?
   #endif
   ```

2. In init, attempt to create EmbeddingModel and HNSWIndex:
   - EmbeddingModel init can throw (model/vocab not found) — catch and set to nil (graceful degradation)
   - HNSWIndex needs a path (Application Support + "vectors.usearch") and the FTS5Database for vector_key_map

3. Update `ensureIndexFresh()`:
   - After FTS5 flush, if embeddingModel and hnswIndex are available:
     - Fetch dirty batch from FTS5Database (same dirty_blocks table)
     - Create EmbeddingIndexer with embeddingModel + hnswIndex + modelContext
     - Call `embeddingIndexer.processDirtyBlocks(blockIds:)`
   - If unavailable, skip silently (keyword-only mode)

4. Update `search()`:
   - If embeddingModel and hnswIndex are available:
     - Create SemanticEngine with embeddingModel + hnswIndex
     - Run semantic search in parallel with keyword search using async let
     - Pass real semantic results to HybridRanker
   - If unavailable, continue passing empty semantic results (current behavior)

5. **Dirty block sharing concern:** Both FTS5Indexer and EmbeddingIndexer consume dirty blocks from the same `dirty_blocks` table. Currently FTS5Indexer calls `fetchDirtyBatch()` then `removeDirty()` after processing. EmbeddingIndexer needs to process the same dirty set.

   Solution: Process both indexers from the same fetched batch before removing. Pseudocode for ensureIndexFresh:
   ```
   flush dirtyTracker to SQLite
   batch = fts5Database.fetchDirtyBatch(limit: 500)

   // Process both pipelines from the same batch
   fts5Indexer.processBatch(batch)        // upsert/delete from FTS5
   embeddingIndexer.processBatch(batch)   // embed/insert into HNSW

   fts5Database.removeDirty(batch)        // remove after both succeed
   ```

   This requires refactoring FTS5Indexer.flushAll() to accept an external batch instead of fetching internally, OR have SearchService manage the fetch-process-remove cycle directly.

**Changes to NotoApp.swift:**

6. Create shared HNSWIndex alongside sharedSearchDatabase:
   ```
   #if canImport(USearch)
   @MainActor
   let sharedHNSWIndex: HNSWIndex? = { ... }()
   #endif
   ```

7. On launch, if HNSW index file doesn't exist but BlockEmbedding records do, call `embeddingIndexer.rebuildIndex()` to reconstruct the HNSW from persisted embeddings.

---

## Task 4: Integration Tests for SearchService

End-to-end tests that exercise the full pipeline: create blocks → dirty track → index → search → verify results.

**Test file:** `NotoTests/SearchServiceTests.swift`

**Tests (keyword-only, always run):**

1. `testKeywordSearchFindsBlock` — insert block, flush, search by keyword, verify result contains the block
2. `testKeywordSearchRespectsDateFilter` — insert blocks at different dates, search with "today" / "last week", verify only matching blocks return
3. `testKeywordSearchBreadcrumb` — insert nested blocks, search, verify breadcrumb shows ancestor path
4. `testKeywordSearchUpdateBlock` — insert block, index, update content, re-index, verify new content is searchable and old is not
5. `testKeywordSearchDeleteBlock` — insert block, index, delete, re-index, verify block no longer returned
6. `testEmptyQueryReturnsEmpty` — search with empty string returns []
7. `testDateOnlyQueryReturnsBlocksInRange` — search with just "today" returns all blocks created today

**Tests (semantic, `#if canImport(USearch)`):**

8. `testSemanticSearchReturnsSimilar` — insert blocks with known content, embed, search with semantically similar query, verify relevant block ranks high
9. `testHybridRankingMergesResults` — ensure blocks found by both keyword and semantic rank higher than blocks found by only one
10. `testSemanticSearchGracefulWithoutModel` — if EmbeddingModel fails to init, search still works (keyword-only fallback)

**Test helper:** Create a `SearchServiceTestHelper` that sets up in-memory ModelContainer + temp FTS5Database + temp HNSW index + DirtyTracker, returning a fully wired SearchService. Reuse `createTestContainer()` and `createTestFTS5Database()` from existing test helpers.

---

## Task 5: UI Tests for SearchSheet

Test the search UI flow in the simulator.

**Test file:** `NotoUITests/SearchUITests.swift`

**Tests:**

1. `testSearchBarTriggerOpensSheet` — tap the search bar trigger in the bottom toolbar, verify SearchSheet appears (search field is visible)
2. `testSearchAndSelectResult` — open search sheet, type a query, submit, verify results appear, tap a result, verify navigation to that block
3. `testSearchClearButton` — type a query, tap the clear (x) button, verify text clears and results reset
4. `testSearchDismiss` — open search sheet, swipe down to dismiss, verify sheet closes
5. `testEmptySearchShowsNoResults` — open search sheet, submit with empty text, verify no results message

**Prerequisites:**
- SearchSheet must have accessibility identifiers:
  - `searchBarTrigger` (already set on GlassSearchBarTrigger)
  - `searchTextField` (add to the TextField in SearchSheet)
  - `askAIRow` (already set)
  - `searchResultRow_\(result.id)` (add to SearchResultRow)
  - `noResultsText` (add to empty results view)
  - `clearSearchButton` (add to the clear button)

**Setup:** Each test uses `-UITesting` launch argument for in-memory data. Seed test blocks before searching by navigating to the app and creating content.

---

## Execution Order

```
Task 1: Add USearch SPM         (no dependencies)
Task 2: Bundle CoreML model     (no dependencies)
    ↓
Task 3: Wire EmbeddingIndexer   (depends on 1 + 2)
    ↓
Task 4: Integration tests       (depends on 3)
Task 5: UI tests                (depends on 3, can run parallel with 4)
```

Tasks 1 and 2 are independent and can be done in parallel. Task 3 requires both. Tasks 4 and 5 can run in parallel after Task 3.
