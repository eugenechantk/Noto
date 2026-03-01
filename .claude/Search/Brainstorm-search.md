# Brainstorm: Semantic + Keyword Search

Braindump of research, options, trade-offs, and open questions for implementing hybrid search across all blocks in Noto.

---

## What We Want

From the README:
- Search by exact words (keyword)
- Search by synonyms or similar words
- Search by meaning (semantic)
- No mode switching — one search box that intelligently ranks results combining keyword and semantic relevance
- Must work offline
- Also serves as the backbone for AI chat (grounding retrieval)

---

## Current State

### Existing Data Models (shells, no implementation)

**SearchIndex** (`Models/SearchIndex.swift`):
- Stores `blockId`, `searchableText` (lowercased content), `tokens` ([String] split on whitespace)
- Naive tokenization — no stemming, no stop-word removal, no ranking
- Probably unnecessary if we use FTS5 (which handles all of this internally)

**BlockEmbedding** (`Models/BlockEmbedding.swift`):
- Stores `embedding: [Float]`, `modelVersion`, `contentHash`, `generatedAt`
- One-to-one relationship with Block
- Well-designed shell, just needs an embedding generation backend

### What's NOT Built Yet
- No embedding generation
- No search query logic
- No hybrid ranking algorithm
- No FTS5 integration
- No search UI
- No vector similarity computation

---

## Keyword Search Strategy

SQLite FTS5 in a separate `.sqlite` database, synced via dirty-set with lazy flush.

### Why FTS5

FTS5 is the gold standard for on-device full-text search. Built into the SQLite bundled with iOS — it's a system library, so it satisfies the "no external dependencies" constraint.

**What FTS5 gives us for free:**
- BM25 relevance scoring (TF-IDF based ranking)
- Stemming via porter tokenizer (so "running" matches "run")
- Prefix queries (`"sema*"` matches "semantic")
- Phrase queries (`"keyword search"` as exact phrase)
- Boolean operators (AND, OR, NOT)
- Column weighting (if we index multiple fields)
- Highlight/snippet extraction (for showing matches in context)

### Separate SQLite Database

SwiftData has no native API for FTS5 virtual tables. Can't create one through `@Model` or `#Predicate`. So the FTS5 index lives in a dedicated `.sqlite` file managed entirely through the C API. This gives us simpler isolation, no risk of SwiftData schema conflicts, and easy rebuild if corrupted.

### FTS5 Table Design

```sql
CREATE VIRTUAL TABLE block_fts USING fts5(
    content,          -- block text content
    block_id UNINDEXED, -- reference back to SwiftData Block (not searchable)
    tokenize='porter unicode61'  -- stemming + unicode normalization
);
```

### Querying

```sql
-- Basic search with BM25 ranking
SELECT block_id, rank FROM block_fts WHERE block_fts MATCH 'semantic search' ORDER BY rank;

-- Prefix search
SELECT block_id, rank FROM block_fts WHERE block_fts MATCH 'sema*' ORDER BY rank;

-- Snippet extraction for result preview
SELECT block_id, snippet(block_fts, 0, '<b>', '</b>', '...', 10) FROM block_fts WHERE block_fts MATCH 'search';
```

### Sync Strategy

Dirty-set with lazy flush (see Indexing Strategy section for full details).
- On block change/delete: mark dirty in `dirty_blocks` table (cheap single-row write)
- On search open: flush dirty blocks to FTS5 in batches before returning results
- On app background: best-effort flush
- On launch: flush remaining dirty + timestamp reconciliation safety net

The existing `SearchIndex` SwiftData model should be removed — FTS5 replaces its functionality entirely.

---

## Semantic Search Strategy

Bundled CoreML sentence-transformer model (`bge-small-en-v1.5`), converted to `.mlmodelc` and shipped in the app bundle.

### Why a Bundled Sentence-Transformer (Not Apple's NL Framework)

The key requirement is **abstract conceptual search** — a query like "i wrote about something related to taste" should find blocks about aesthetics, design commentary, and artistic judgement, even when the word "taste" never appears.

This requires a model trained with a **contrastive similarity objective** (similar meaning → close vectors, different meaning → far vectors). Apple's NL framework models were not trained for this:

- **`NLEmbedding`** — Static Word2Vec-style embeddings. Not context-aware ("bank" produces the same vector in "river bank" and "bank account"). No ability to bridge abstract concepts.
- **`NLContextualEmbedding`** — BERT-like transformer trained on masked language modeling. Produces context-aware *token* embeddings, but was never optimized for sentence-level similarity. Mean-pooling token vectors gives a sentence representation that isn't calibrated for cosine similarity ranking. Will struggle with conceptual queries where the surface words don't overlap.

Sentence-transformer models (like `bge-small-en-v1.5`) are trained with contrastive loss on millions of sentence pairs. The training objective is literally the task we need: "these two texts mean the same thing → close vectors." They handle abstract conceptual bridging because the contrastive training forces them to learn that "taste in art" and "aesthetic judgement" live nearby in embedding space.

### Why `bge-small-en-v1.5` Over `all-MiniLM-L6-v2`

Both are 384-dimensional sentence-transformers, but `bge-small-en-v1.5` scores measurably better on retrieval benchmarks (MTEB), especially for asymmetric query-to-document matching — which is exactly our use case (short query → find relevant longer block).

| | `all-MiniLM-L6-v2` | `bge-small-en-v1.5` |
|--|---------------------|---------------------|
| Dimensions | 384 | 384 |
| Bundle size | ~22MB | ~33MB |
| MTEB retrieval score | ~41 | ~51 |
| Asymmetric search quality | Good | Better |
| Cross-platform consistency | Yes | Yes |

The ~11MB extra is worth the quality gain for conceptual queries.

### What This Requires

- **One-time model conversion:** Python `coremltools` pipeline to convert the HuggingFace model to `.mlmodelc`
- **WordPiece tokenizer in Swift:** BERT-style tokenization. Can vendor from `swift-embeddings` (https://github.com/jkrukowski/swift-embeddings) or implement directly — the tokenizer is well-documented and deterministic.
- **~33MB added to app bundle:** The compiled CoreML model
- **CoreML inference:** ~10-30ms per block on Neural Engine, 384-dim output

### Options Considered But Not Chosen

- **`NLEmbedding`** — Static embeddings, no context awareness, poor quality for conceptual search. Ruled out.
- **`NLContextualEmbedding`** — Wrong training objective (language understanding, not similarity). Per-token output requires manual pooling. 512/768 dimension mismatch across iOS/macOS. Ruled out.
- **`model2vec.swift`** — Distilled static embeddings, external dependency. Interesting for size-constrained scenarios but lower quality. Not needed given acceptable bundle size.
- **`all-MiniLM-L6-v2`** — Viable but `bge-small-en-v1.5` is strictly better on retrieval benchmarks for marginal size increase.

---

## Vector Similarity Search

HNSW (Hierarchical Navigable Small World) index via `usearch` library (https://github.com/unum-cloud/usearch). This is the one external dependency in the project.

### Why HNSW

The app will scale to tens of thousands or millions of blocks over years of use. Brute-force cosine similarity is O(n) per query — at 1M blocks with 384 dims, that's ~7-10 seconds per search. Unacceptable.

HNSW is a graph-based ANN (Approximate Nearest Neighbor) index that pre-organizes vectors into a multi-layer navigable graph. At query time, it traverses the graph greedily, touching only ~200-400 vectors to find the top-K most similar — regardless of total dataset size.

| Scale | Brute Force | HNSW |
|-------|-------------|------|
| 10K blocks | ~700ms | ~1-2ms |
| 100K blocks | ~7s | ~2-5ms |
| 1M blocks | ~70s | ~5-10ms |

### Why `usearch`

- First-class Swift bindings via SPM
- HNSW under the hood (the paper authors' algorithm, battle-tested)
- Designed for embedded/on-device use — small footprint
- **Incremental insertion** — new blocks are added to the graph without rebuilding the entire index
- **Persistence** — save/load index to a single file on disk
- Supports cosine similarity, inner product, L2 distance
- Actively maintained, widely used in production

### Index Configuration

```swift
// 384 dims from bge-small-en-v1.5, cosine similarity metric
let index = USearchIndex.make(
    metric: .cos,
    dimensions: 384,
    connectivity: 16,      // M parameter — edges per node (16 is standard)
    quantization: .F16      // half precision — halves memory, negligible quality loss
)
```

### Operations

- **Insert:** `index.add(key: blockId, vector: embedding)` — ~1-5ms, called after embedding generation
- **Search:** `index.search(vector: queryEmbedding, count: 50)` — ~1-10ms, returns top-K block IDs with distances
- **Remove:** `index.remove(key: blockId)` — for deleted blocks
- **Persist:** `index.save(path: indexFilePath)` / `index.load(path: indexFilePath)`

### Storage

The HNSW index is a single binary file on disk (separate from both SwiftData and the FTS5 database). At 1M blocks × 384 dims with F16 quantization:
- Index file: ~0.75-1GB (half of F32's ~1.5-2GB)
- Negligible quality loss for cosine similarity on 384-dim vectors
- Loaded into memory on app launch / search view appear

### Sync with Embeddings

The HNSW index and the `BlockEmbedding` SwiftData model store the same vectors. The HNSW index is the *query structure*, BlockEmbedding is the *source of truth*. If the HNSW index file is corrupted or deleted, it can be fully rebuilt from BlockEmbedding records.

**HNSW inserts happen eagerly — but only relative to embedding generation, which itself is lazy.** The embedding generation (~30ms CoreML inference) is the expensive part, not the HNSW insert (~1-5ms). There's no reason to run CoreML inference while the user is actively writing — it burns battery and thermal budget on the Neural Engine for embeddings that aren't needed yet.

The combined flow across all three indexing systems:

| Component | Cost per block | When it happens |
|-----------|---------------|-----------------|
| In-memory dirty mark | ~0ms (Set insert) | On block change via `syncContent` |
| Persist to `dirty_blocks` table | ~1ms | On dirty flush trigger (see below) |
| Embedding generation | ~30ms (Neural Engine) | Lazy — on search open / app background / app launch |
| HNSW insert | ~1-5ms | Immediately after embedding generation (same pass) |
| FTS5 flush | ~0.2ms | Lazy — on search open / app background / app launch |

#### Two-Phase Dirty Marking

Dirty marking happens in two phases to avoid any SQLite writes while typing:

**Phase 1 — In-memory tracking (while typing):**
- `syncContent` updates a block → add its UUID to an in-memory `Set<UUID>` of changed blocks
- Reset an idle timer on each change
- Zero overhead — just a Set insert

**Phase 2 — Persist to `dirty_blocks` table (on trigger):**
Flush the in-memory set to the `dirty_blocks` SQLite table. Triggers:
1. **Block loses focus** — user taps another block or taps outside
2. **Navigate away** — back button, switch to a different note
3. **App enters background** — `scenePhase == .background`
4. **Idle timeout (~5-10s)** — user stops typing but stays focused on the block (e.g., sets phone down mid-thought)

After flushing, clear the in-memory set.

**If the app is force-killed before a flush trigger fires** (e.g., user is typing and iOS kills the process), the in-memory set is lost. Those blocks never get marked dirty. The launch-time timestamp reconciliation safety net catches exactly this case — it compares `block.updatedAt` timestamps against `lastFullReconciliationAt` to find blocks that changed but were never marked dirty.

#### Lazy Processing

**While writing:** Zero SQLite writes, zero Neural Engine work, zero HNSW work. Only in-memory Set inserts.

**On dirty flush trigger:** ~1ms per block to persist to `dirty_blocks` table.

**When search opens / app backgrounds / launch:** For each dirty block, in one pass:
1. Generate embedding (CoreML, ~30ms)
2. Insert into HNSW index (~1-5ms)
3. Store embedding in `BlockEmbedding` (SwiftData)
4. Flush to FTS5 (~0.2ms)
5. Remove from `dirty_blocks`

This keeps writing completely lightweight and batches all expensive work into moments when it's actually needed.

---

## Indexing Strategy

### When to Index (FTS5 Keyword)

**Decision: Dirty-set with lazy flush.**

The user writes notes frequently but searches occasionally. Instead of syncing FTS5 on every block change, we track *what* changed cheaply and only do the real FTS5 work when it's actually needed.

**Dirty tracking table** (lives in the same separate FTS5 `.sqlite` database):
```sql
CREATE TABLE IF NOT EXISTS dirty_blocks (
    block_id TEXT PRIMARY KEY,
    operation TEXT NOT NULL DEFAULT 'upsert'  -- 'upsert' or 'delete'
);
```

**Flow:**

1. **Block content changes or new block created** → UUID added to in-memory `Set<UUID>`. On dirty flush trigger (focus loss, navigate away, app background, idle timeout ~5-10s), persist to `dirty_blocks`: `INSERT OR REPLACE INTO dirty_blocks (block_id, operation) VALUES (?, 'upsert')`.

2. **Block deleted** → `INSERT OR REPLACE INTO dirty_blocks (block_id, operation) VALUES (?, 'delete')` — this one writes immediately since deletion is a discrete action, not continuous typing.

3. **User opens search** → Flush `dirty_blocks` to FTS5 in batches of ~50 before returning results. For each batch:
   - Read 50 rows from `dirty_blocks`
   - For `upsert`: fetch block content from SwiftData, `INSERT OR REPLACE` into `block_fts`
   - For `delete`: `DELETE FROM block_fts WHERE block_id = ?`
   - Delete the processed rows from `dirty_blocks`
   - Commit the batch
   - Repeat until `dirty_blocks` is empty

4. **App enters background** (`scenePhase == .background`) → Same flush as step 3, best-effort. iOS gives ~5 seconds of background execution. At ~0.2ms per FTS5 insert, that's enough for ~25,000 blocks — more than enough for any realistic dirty set. If the process is killed mid-flush, partially processed batches are already committed and the remaining dirty IDs survive on disk for next time.

5. **App launch** → Two-phase catch-up:
   - **Phase 1:** Flush any remaining `dirty_blocks` (handles the case where background sync was killed or app crashed)
   - **Phase 2:** Timestamp reconciliation safety net — compare `block.updatedAt` against a stored `lastFullReconciliationAt` timestamp to catch blocks that changed but were never marked dirty (e.g., crash before the dirty insert). Only needs to run if `dirty_blocks` was non-empty at launch (indicating potential data loss).

**Why this works if the app is killed mid-flush:**
- FTS5 inserts are committed in small batch transactions (50 blocks each). A kill mid-flush means some batches committed, some didn't.
- The uncommitted blocks still have their IDs in `dirty_blocks` (we delete from `dirty_blocks` only after the corresponding FTS5 batch commits).
- Next search or next launch picks up exactly where it left off.
- The FTS5 index is never corrupted — just potentially stale on some blocks.

**Why this works if the app crashes before marking dirty:**
- The launch-time timestamp reconciliation catches this. It's the safety net for the safety net.
- This should be rare — the dirty insert is a single fast write that happens synchronously with the block change.

### When to Index (Embeddings / Semantic)

- **Content hash check:** Only regenerate embedding if `SHA256(block.content) != blockEmbedding.contentHash`
- **Background processing:** Generate embeddings on a background actor/queue. Don't block the main thread.
- **Batch initial indexing:** On first launch or when enabling search for existing notes, queue all unindexed blocks and process in batches during idle time. Show a progress indicator ("Indexing your notes... 142/500").
- Embedding generation is slower than FTS5 indexing (~50ms per block vs ~0.2ms), so can reuse the same dirty-set pattern but with more aggressive batching and a separate dirty table or flag.

### What to Index

**For FTS5 (keyword):**
- `block.content` (the plain text, possibly after running `deformatted()` from NoteTextStorage to strip markdown)
- Could also index parent context for richer matching (see open questions)

**For embeddings (semantic):**
- The block's own content
- Potentially with parent/ancestor context prepended (see open questions)
- Short blocks (< 5 words) may produce poor embeddings — consider concatenating with children or skipping

---

## Hybrid Search Strategy

A single search query goes through three stages: **filter extraction**, **parallel search**, and **hybrid ranking**.

### 1. Filter Extraction

No explicit filter UI — date filters are parsed from natural language in the query before searching.

**Regular search path (rule-based, offline, fast):**

Pattern match common temporal phrases using `NSDataDetector` (.date type) + a small regex layer. Strip matched phrase from query before sending remainder to FTS5 + HNSW.
- "today" → `createdAt >= startOfDay`
- "yesterday" → yesterday's range
- "last week" / "this week" → 7-day window
- "in March" / "in 2024" → month/year range
- "recent" → last 7 days

**Ask AI path (LLM, may need network):**

The LLM decomposes the full natural language query into intent + structured filters, then calls the same underlying search system. Can handle complex cases like:
- "things about food from January" → intent: "food", filter: January date range
- "what was I thinking today" → intent: "thinking", filter: today

Both paths produce the same structured filter parameters:
```
SearchQuery {
    text: String              // the search terms (temporal phrases stripped)
    dateRange: DateRange?     // optional date filter
}
```

### 2. Parallel Search

Run keyword and semantic search in parallel, both respecting the extracted date filter:

**FTS5:** `WHERE` clause joining block metadata:
```sql
SELECT block_id, rank FROM block_fts
WHERE block_fts MATCH ?
AND block_id IN (
    SELECT id FROM blocks
    WHERE createdAt >= ? AND createdAt <= ?
)
ORDER BY rank;
```

**HNSW:** Post-filter. Over-fetch from `usearch` (e.g., request top 200), then filter by date, keep top 50. ANN indexes don't natively support metadata filters — post-filtering is the standard approach.

### 3. Hybrid Ranking

#### Candidate Set Strategy

Threshold-based, not fixed top-K. Only return results that pass a minimum relevance score:
1. FTS5 keyword search → all results above BM25 threshold
2. HNSW semantic search → over-fetch top 200, keep results with cosine similarity >= threshold (e.g., 0.3)
3. Union the candidate sets
4. Compute hybrid scores only for the union
5. Return all results that pass the combined threshold, sorted by hybrid score

Thresholds to tune empirically:
- **Cosine similarity:** >= 0.3 (starting point, may need adjustment)
- **BM25:** TBD — depends on score distribution in practice

#### Score Combination

```
finalScore = α * keywordScore + (1 - α) * semanticScore
```

Both scores must be normalized to [0, 1] before combining.

#### Score Normalization

**Keyword (FTS5 BM25):**
- BM25 returns negative scores (more negative = better match in SQLite's implementation)
- Normalize: `normalizedScore = (score - minScore) / (maxScore - minScore)` over the result set
- If only one result, score = 1.0

**Semantic (cosine similarity):**
- Cosine similarity is already in [-1, 1], but practically in [0, 1] for positive embeddings
- Normalize to [0, 1]: `normalizedScore = (similarity - minSim) / (maxSim - minSim)` over the result set

#### Weight Tuning

Start with `α = 0.6` (keyword-heavy). Rationale:
- Users typing exact words expect exact matches first
- Semantic is the fallback when keywords don't match well
- Can be tuned later based on user behavior

#### Short-Circuit Optimizations

- **Exact match boost:** If query appears verbatim in a block, boost that result significantly
- **Empty keyword results:** If FTS5 returns nothing, fall back to pure semantic ranking
- **Single common word:** If query is one common word, keyword search alone is probably sufficient
- **Long natural-language query:** If query is a full sentence with no exact matches, lean heavier on semantic

---

## Storage Architecture

| Component | Storage | Reasoning |
|-----------|---------|-----------|
| FTS5 keyword index | Separate `.sqlite` file via C API | Avoids SwiftData schema conflicts; rebuildable |
| Embeddings (source of truth) | SwiftData `BlockEmbedding` model | Already defined; co-located with block data |
| HNSW vector index | `usearch` binary file on disk | Fast ANN queries; rebuildable from BlockEmbedding |

### Data Model Changes

**Remove or repurpose `SearchIndex`:**
- FTS5 replaces its functionality entirely
- Could repurpose as a tracking table (which blocks have been indexed in FTS5) or just delete it

**Enhance `BlockEmbedding`:**
- Consider adding `dimension: Int` to future-proof cross-platform and model-upgrade scenarios
- The existing `modelVersion` + `contentHash` fields are well-designed

---

## Architecture Sketch

```
┌─────────────────────────────────────────────────┐
│                   Search UI                      │
│  ┌─────────────────────────────────────────────┐ │
│  │  Search Bar (single input, no mode switch)  │ │
│  └─────────────┬───────────────────────────────┘ │
│                │ query string                     │
│  ┌─────────────▼───────────────────────────────┐ │
│  │          SearchService                       │ │
│  │  - Orchestrates keyword + semantic search    │ │
│  │  - Normalizes scores                         │ │
│  │  - Combines with hybrid ranking              │ │
│  │  - Returns ranked [SearchResult]             │ │
│  └──────┬──────────────────┬───────────────────┘ │
│         │                  │                      │
│  ┌──────▼──────┐    ┌─────▼──────────────┐       │
│  │ FTS5Engine  │    │ SemanticEngine     │       │
│  │ (C API)     │    │ (CoreML bge-small  │       │
│  │             │    │  + usearch HNSW)   │       │
│  │ search.db   │    │                    │       │
│  └──────┬──────┘    └─────┬──────────────┘       │
│         │                  │                      │
│  ┌──────▼──────┐    ┌─────▼──────────────┐       │
│  │ FTS5 SQLite │    │ HNSW index (disk)  │       │
│  │ (separate   │    │ + BlockEmbedding   │       │
│  │  .sqlite)   │    │   (SwiftData)      │       │
│  └─────────────┘    └────────────────────┘       │
│                                                   │
│  ┌───────────────────────────────────────────┐   │
│  │ IndexingService                            │   │
│  │ - Watches for block content changes        │   │
│  │ - Debounces updates                        │   │
│  │ - Updates FTS5 + regenerates embeddings    │   │
│  │ - Batch re-index on first launch           │   │
│  └───────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

---

## Open Questions

### 1. What's the unit of search? — RESOLVED

**Index only the block's own content.** No parent context, no children, no ancestor chain.

- Blocks with real substance carry their own meaning — no parent context needed.
- Including parent content dilutes the block's own meaning in the embedding, causes cascade re-indexing when parents change, and adds complexity.
- Short/header blocks ("Ingredients", "TODO") are handled separately (see Question 4) — that's a short-block problem, not a missing-context problem.

### 2. Hierarchical context in embeddings — RESOLVED

**No.** Embeddings are generated from the block's content only. No parent chain, no immediate parent, no children concatenated.

If search quality proves poor for certain blocks, parent context can be revisited later — `modelVersion` / `contentHash` on `BlockEmbedding` makes re-indexing straightforward.

### 3. Search result presentation — RESOLVED

**Decided via Figma design** (figma.com/design/9nh3TpDEoZx8Pt8hVUrJgV, node 24:767):

Each result is a list row with:
- **Title line**: Block content text (17pt, primary color, truncated with ellipsis for single-line blocks, wraps for longer blocks)
- **Breadcrumb line**: Ancestor path in secondary gray (15pt) — e.g., "Home / Not too bad / but this is a bullet"

The search lives in a **bottom sheet** overlaying the current note. The search bar is at the **bottom** of the sheet (liquid glass style). An "Ask AI" action row sits above the results, sharing the same query input — search and AI chat are unified.

No tree view, no surrounding context snippets — just block text + breadcrumb path. Tapping a result navigates to that block in-place.

### 4. Empty/very short blocks — RESOLVED

**Skip embedding generation for blocks under N words (e.g., 3).** No embedding, no HNSW entry. They are still indexed in FTS5 and findable via keyword search.

### 5. Query embedding caching — RESOLVED

**Not needed.** The search UI uses a submit button — one embedding generated per search, not per keystroke. No debouncing or caching required.

FTS5 keyword search could optionally run as-you-type (<10ms) for instant partial results, with semantic results blending in after the user submits. But that's a UI decision, not an architecture concern.

### 6. Markdown stripping — RESOLVED

**Yes, always strip.** Raw content only for both FTS5 and embedding generation. `NoteTextStorage.deformatted()` already extracts plain text — use that.

### 7. Re-indexing strategy on model change — RESOLVED

**Not applicable.** The model is `bge-small-en-v1.5` bundled in the app, and it won't change.

### 8. Search scope — RESOLVED

**Global search by default, with date range filtering.** No explicit filter UI — date filters are parsed from natural language. See Hybrid Search Strategy section for full details.

---

## Performance Budget

| Operation | Target | Notes |
|-----------|--------|-------|
| Keyword search (FTS5) | < 10ms | FTS5 is extremely fast |
| Query embedding generation | < 50ms | NLContextualEmbedding on Neural Engine |
| Brute-force vector scan (5K blocks) | < 500ms | Accelerate vDSP |
| Score normalization + ranking | < 5ms | Simple math |
| Total search latency | < 600ms | Acceptable for search-on-submit |
| Embedding generation per block | < 50ms | Background, debounced |
| Full re-index (5K blocks) | < 5 min | Background, show progress |

For search-as-you-type:
- Keyword results can appear instantly (< 10ms)
- Semantic results appear after debounce + inference (~300-500ms)
- UI shows keyword results first, then blends in semantic results when ready

---

## Libraries & Frameworks Summary (All Apple-native)

| Need | Framework | Notes |
|------|-----------|-------|
| Full-text keyword search | `libsqlite3` (FTS5) | System library, C API |
| Contextual embeddings | `NaturalLanguage` (`NLContextualEmbedding`) | iOS 17+, on-device transformer |
| Fast vector math | `Accelerate` (`vDSP`) | Cosine similarity, dot products |
| Content hashing | `CryptoKit` (`SHA256`) | Detect content changes for re-embedding |
| Background processing | `Swift Concurrency` (actors) | Debounced indexing off main thread |

No external dependencies required.

---

## References

- [NLEmbedding — Apple Developer Documentation](https://developer.apple.com/documentation/naturallanguage/nlembedding)
- [NLContextualEmbedding — Apple Developer Documentation](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)
- [NaturalLanguageEmbeddings — Semantic text search using Apple's NL framework](https://github.com/buh/NaturalLanguageEmbeddings)
- [On-Device Text Embeddings with Apple NLP framework](https://www.callstack.com/blog/on-device-ai-introducing-apple-embeddings-in-react-native)
- [swift-embeddings — Run embedding models locally in Swift](https://github.com/jkrukowski/swift-embeddings)
- [all-MiniLM-L6-v2 on HuggingFace](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2)
- [model2vec.swift — On-Device Static Sentence Embeddings](https://github.com/shubham0204/model2vec.swift)
- [SQLite FTS5 Extension](https://sqlite.org/fts5.html)
- [Leveraging SQLite Full-Text Search on iOS](https://www.nutrient.io/blog/leveraging-sqlite-full-text-search-on-ios/)
- [GRDB.swift Full-Text Search Documentation](https://github.com/groue/GRDB.swift/blob/master/Documentation/FullTextSearch.md)
- [Explore Natural Language Multilingual Models — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10042/)
- [Make Apps Smarter with Natural Language — WWDC20](https://developer.apple.com/videos/play/wwdc2020/10657/)
