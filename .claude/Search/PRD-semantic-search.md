# PRD: Semantic Search (Embeddings + HNSW)

## Overview

On-device semantic search using a bundled CoreML sentence-transformer model (`bge-small-en-v1.5`) and an HNSW vector index (`usearch` library). Users can search by meaning — a query like "something related to taste" finds blocks about aesthetics, design commentary, and artistic judgement even when the word "taste" never appears.

**Scope:** Embedding generation + HNSW vector index + semantic query execution. Does not include the search UI or hybrid ranking — those are separate PRDs.

**Dependencies:**
- `usearch` (SPM) — HNSW vector index. The one external dependency in the project.
- `bge-small-en-v1.5.mlmodelc` — CoreML model bundled in the app (~33MB).

---

## Core Requirements

| Requirement | Implication |
|-------------|-------------|
| Search by meaning / concepts | Sentence-transformer embeddings |
| Abstract conceptual bridging | Contrastive-trained model (not Apple NL framework) |
| Scale to millions of blocks | HNSW index, not brute-force |
| Offline-first | On-device CoreML inference, local HNSW index |
| Cross-platform consistency | 384 dims on both iOS and macOS (bundled model) |
| Short blocks skipped | No embedding for blocks under 3 words |
| Markdown stripped before embedding | Use `NoteTextStorage.deformatted()` |

---

## Embedding Model

### Why `bge-small-en-v1.5`

The key requirement is abstract conceptual search. This requires a model trained with a contrastive similarity objective — Apple's `NLEmbedding` (static, Word2Vec-style) and `NLContextualEmbedding` (BERT MLM, not similarity-optimized) are insufficient.

`bge-small-en-v1.5` is a sentence-transformer trained with contrastive loss on millions of sentence pairs. It outperforms `all-MiniLM-L6-v2` on retrieval benchmarks (MTEB), especially for asymmetric query-to-document matching.

| Property | Value |
|----------|-------|
| Dimensions | 384 |
| Bundle size | ~33MB (.mlmodelc) |
| Inference speed | ~10-30ms per block (Neural Engine) |
| MTEB retrieval score | ~51 |

### Model Preparation (One-Time)

Convert the HuggingFace model to CoreML format using Python `coremltools`. The resulting `.mlmodelc` is bundled in the Xcode project.

### WordPiece Tokenizer

BERT-style tokenization is required before CoreML inference. Options:
- Vendor the tokenizer from `swift-embeddings` (https://github.com/jkrukowski/swift-embeddings)
- Implement directly — WordPiece is well-documented and deterministic

The tokenizer and its vocabulary file are bundled with the app alongside the CoreML model.

---

## HNSW Vector Index

### Why HNSW via `usearch`

Brute-force cosine similarity is O(n) — at 1M blocks, that's ~7-10 seconds per query. HNSW provides sub-linear search via graph traversal.

| Scale | Brute Force | HNSW |
|-------|-------------|------|
| 10K blocks | ~700ms | ~1-2ms |
| 100K blocks | ~7s | ~2-5ms |
| 1M blocks | ~70s | ~5-10ms |

### Why `usearch`

- First-class Swift bindings via SPM
- Incremental insertion (no rebuild needed for new blocks)
- Persistence (save/load to single binary file)
- Supports cosine similarity metric
- Designed for embedded/on-device use

### Index Configuration

```swift
let index = USearchIndex.make(
    metric: .cos,
    dimensions: 384,
    connectivity: 16,       // M parameter — edges per node
    quantization: .F16      // half precision — halves memory, negligible quality loss
)
```

### Storage

Single binary file on disk, separate from SwiftData and FTS5 databases.

At 1M blocks × 384 dims with F16 quantization: ~0.75-1GB.

If corrupted or deleted, fully rebuildable from `BlockEmbedding` SwiftData records.

---

## Indexing Pipeline

### Embedding Generation Triggers

Embedding generation is lazy — it does not run while the user is typing. It shares the same dirty-set mechanism as keyword search (see PRD-keyword-search.md).

**When embeddings are generated:**
- On search open (flush dirty blocks)
- On app background (best-effort flush)
- On app launch (flush remaining + reconciliation)

For each dirty block in the flush pass:
1. Fetch block content from SwiftData
2. Strip markdown via `deformatted()`
3. Check word count — skip if < 3 words (no embedding, no HNSW entry)
4. Check content hash — skip if `SHA256(content) == blockEmbedding.contentHash` (unchanged)
5. Run CoreML inference (~30ms) → 384-dim float vector
6. Insert into HNSW index (~1-5ms) — eager relative to embedding generation
7. Store embedding in `BlockEmbedding` SwiftData model
8. Remove from `dirty_blocks`

### HNSW Insert Timing

HNSW inserts happen immediately after each embedding is generated (same pass), not deferred. The insert cost (~1-5ms) is negligible compared to the embedding generation (~30ms) and they naturally pair together.

### Block Deletion

When a block is deleted:
- Remove from HNSW index: `index.remove(key: blockId)`
- Delete the `BlockEmbedding` SwiftData record

### Initial Indexing (First Launch)

On first launch or when search is enabled for an existing note collection:
- Queue all unindexed blocks
- Process in batches on a background actor
- Show progress indicator ("Indexing your notes... 142/500")
- At ~30ms per block, 10K blocks ≈ 5 minutes

---

## Query API

### Interface

The semantic engine takes a query string and optional date filter, returns block IDs with cosine similarity scores.

```
SemanticEngine.search(query: String, dateRange: DateRange?) -> [(blockId: UUID, similarity: Float)]
```

### Query Execution

1. Strip markdown from query (if any)
2. Generate query embedding via CoreML (~30ms)
3. Search HNSW index — over-fetch top 200 results
4. If date filter provided: post-filter by block `createdAt`, keep results that pass the date range
5. Apply cosine similarity threshold (>= 0.3 starting point, tune empirically)
6. Return passing results with similarity scores

### Cosine Similarity

`usearch` returns cosine distance. Convert to similarity: `similarity = 1 - distance`.

- Distance 0 → identical meaning (similarity 1.0)
- Distance 1 → unrelated (similarity 0.0)

### Short Block Handling

Blocks with < 3 words have no embedding and no HNSW entry. They are invisible to semantic search but still findable via keyword search (FTS5).

---

## Data Model

### `BlockEmbedding` (Existing SwiftData Model)

Already defined with the right fields:
- `embedding: [Float]` — 384-dim vector
- `contentHash: String` — SHA256 of block content, used to detect changes
- `modelVersion: String` — fixed to `"bge-small-en-v1.5"`
- `generatedAt: Date`

No changes needed to the model itself.

---

## Multi-Device Sync (Future)

Embeddings sync as data (block ID + 384 floats, ~1.5KB each) through whatever sync layer is used for blocks. Each device rebuilds its own HNSW index locally from synced embeddings — fast (~30-60 seconds for 500K pre-computed vectors). The expensive part (CoreML inference) is skipped on devices that receive pre-computed embeddings.

---

## Performance Targets

| Operation | Target |
|-----------|--------|
| Query embedding generation | < 30ms (Neural Engine) |
| HNSW search (1M blocks) | < 10ms |
| HNSW single insert | ~1-5ms |
| Block embedding generation | ~30ms |
| Full index build from embeddings (500K) | ~60s |
| Full embedding generation (10K blocks) | ~5 min (background) |

---

## Components

| Component | Responsibility |
|-----------|---------------|
| `EmbeddingModel` | Wraps CoreML model + WordPiece tokenizer. Takes a string, returns 384-dim float vector. Handles model loading and inference. |
| `HNSWIndex` | Wraps `usearch`. Insert, remove, search, save, load. Manages the binary index file on disk. |
| `SemanticEngine` | Query execution. Takes query string + optional filters, generates query embedding, searches HNSW, post-filters, returns results with similarity scores. |
| `EmbeddingIndexer` | Processes dirty blocks — generates embeddings, inserts into HNSW, stores in `BlockEmbedding`. Handles batch processing and initial indexing. |
