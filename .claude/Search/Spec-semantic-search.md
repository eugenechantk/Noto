# Spec: Semantic Search (Embeddings + HNSW)

Based on [PRD-semantic-search.md](./PRD-semantic-search.md).

---

## User Stories

1. **As a user**, I can search for "something related to taste" and find blocks about aesthetics, design, and artistic judgement — even when "taste" doesn't appear in the text.
2. **As a user**, semantic search works entirely offline with no network connection.
3. **As a user**, search results return in under 50ms regardless of whether I have 10K or 1M blocks.
4. **As a user**, short stub blocks ("TODO", "Ideas") don't pollute my semantic search results.
5. **As a user**, embedding generation happens invisibly — no lag while writing, no manual indexing step.
6. **As a user**, if the app crashes or the index is corrupted, the system self-repairs from stored embeddings.

---

## Acceptance Criteria

- [ ] CoreML model (`bge-small-en-v1.5`) is bundled and produces 384-dim embeddings
- [ ] WordPiece tokenizer correctly tokenizes input text for the BERT model
- [ ] Blocks with < 3 words are skipped (no embedding, no HNSW entry)
- [ ] Markdown is stripped before embedding generation
- [ ] Content hash (SHA256) prevents re-embedding unchanged blocks
- [ ] HNSW index uses F16 quantization and cosine similarity metric
- [ ] HNSW search returns results in < 10ms at 1M blocks
- [ ] Cosine similarity threshold (>= 0.3) filters out irrelevant results
- [ ] Date post-filtering works correctly when provided by hybrid layer
- [ ] Embedding generation does not occur during active typing
- [ ] Embeddings are generated lazily on search open / app background / app launch
- [ ] HNSW insert happens immediately after each embedding generation (same pass)
- [ ] Deleted blocks are removed from both HNSW index and `BlockEmbedding`
- [ ] HNSW index can be fully rebuilt from `BlockEmbedding` SwiftData records
- [ ] Initial indexing shows progress indicator for large collections
- [ ] `usearch` is the only external SPM dependency added

---

## Technical Design

### Architecture Overview

```
DirtyTracker (shared with keyword search)
        │
        │ dirty block IDs
        ▼
┌───────────────────┐
│ EmbeddingIndexer  │  Processes dirty blocks in batch
│                   │  Skips short blocks, checks content hash
└───┬──────────┬────┘
    │          │
    ▼          ▼
┌────────┐ ┌──────────┐
│Embedding│ │HNSWIndex │
│Model   │ │(usearch) │
│(CoreML)│ │          │
└────────┘ └──────────┘
    │          │
    │          ▼
    │     index.usearch (binary file on disk)
    ▼
BlockEmbedding (SwiftData — source of truth)

Query path:
┌───────────────┐
│SemanticEngine │ ← query string + optional date filter
│               │
│ 1. embed query│ → EmbeddingModel
│ 2. search     │ → HNSWIndex
│ 3. post-filter│ → SwiftData (date)
│ 4. threshold  │ → similarity >= 0.3
└───────────────┘
```

### Component Details

#### 1. `EmbeddingModel`

Location: `Noto/Search/EmbeddingModel.swift`

Wraps the CoreML model and WordPiece tokenizer. Single responsibility: text in, 384-dim vector out.

```
class EmbeddingModel {
    init() throws                           // loads CoreML model + vocab
    func embed(_ text: String) -> [Float]   // returns 384-dim vector
    func embed(batch: [String]) -> [[Float]] // batch inference
}
```

**CoreML model setup:**

The model file `bge-small-en-v1.5.mlmodelc` is added to the Xcode project's bundle. Loaded at init time:

```swift
let config = MLModelConfiguration()
config.computeUnits = .all  // Neural Engine + GPU + CPU fallback
let model = try MLModel(contentsOf: modelURL, configuration: config)
```

**Model input/output:**

The converted CoreML model expects:
- Input: `input_ids` (Int32 array), `attention_mask` (Int32 array) — from WordPiece tokenizer
- Output: `sentence_embedding` (Float32 array, 384 dims) — the pooled sentence vector

The conversion script (Python, one-time) handles the CLS pooling / mean pooling and normalization so the CoreML model outputs a ready-to-use normalized embedding.

**WordPiece tokenizer:**

BERT-style subword tokenization. Required files bundled in app:
- `vocab.txt` — the BERT vocabulary (~30K tokens)

Tokenization algorithm:
1. Lowercase the input text
2. Split into words on whitespace and punctuation
3. For each word, find the longest matching prefix in vocab
4. Split remainder into subword tokens (prefixed with `##`)
5. Prepend `[CLS]` token (ID 101), append `[SEP]` token (ID 102)
6. Pad or truncate to model's max sequence length (512 tokens)
7. Generate `attention_mask` (1 for real tokens, 0 for padding)

Implementation approach: vendor the tokenizer logic from `swift-embeddings` (https://github.com/jkrukowski/swift-embeddings) — specifically the `BertTokenizer` class. This avoids implementing the edge cases (unicode normalization, accent stripping, unknown token handling) from scratch.

**Vendored files from swift-embeddings:**
- `BertTokenizer.swift` — tokenization logic
- `WordPieceTokenizer.swift` — subword splitting
- Place in `Noto/Search/Tokenizer/`

#### 2. `HNSWIndex`

Location: `Noto/Search/HNSWIndex.swift`

Wraps `usearch` with Noto-specific conventions. Translates between `UUID` block IDs and `usearch`'s `UInt64` keys.

```
class HNSWIndex {
    init(path: URL)                    // loads existing index or creates new
    func add(blockId: UUID, vector: [Float])
    func remove(blockId: UUID)
    func search(vector: [Float], count: Int) -> [(blockId: UUID, distance: Float)]
    func contains(blockId: UUID) -> Bool
    func save() throws
    var count: Int { get }
}
```

**UUID ↔ UInt64 key mapping:**

`usearch` uses `UInt64` keys. UUIDs are 128-bit, so they don't fit directly. Approach: maintain a bidirectional mapping.

Option A — Deterministic hash:
```swift
// Use the first 8 bytes of UUID as UInt64 key
// UUID().uuid is a tuple of 16 UInt8 values
func uuidToKey(_ uuid: UUID) -> UInt64 {
    let bytes = uuid.uuid
    return UInt64(bytes.0) | (UInt64(bytes.1) << 8) | ... | (UInt64(bytes.7) << 56)
}
```
Risk: hash collisions (birthday problem at ~4B entries — effectively zero for our scale).

Option B — Sequential counter with lookup table:
Assign incrementing UInt64 keys and store a `[UUID: UInt64]` mapping persisted alongside the index. More complex but collision-free.

**Recommendation: Option A** — deterministic truncation of UUID to UInt64. At millions of blocks, collision probability is negligible (~1 in 4 billion). Simpler, no extra state to maintain. Store a reverse mapping `[UInt64: UUID]` in memory for converting search results back to UUIDs. This reverse map is rebuilt on index load by reading all keys from the index and matching against `BlockEmbedding` records.

Actually, a cleaner approach: store the UUID→UInt64 and UInt64→UUID mapping in a simple SQLite table in the FTS5 `search.sqlite` database (already exists). This avoids the reverse-lookup rebuild:

```sql
CREATE TABLE IF NOT EXISTS vector_key_map (
    block_id TEXT PRIMARY KEY,
    vector_key INTEGER UNIQUE NOT NULL
);
```

**Index configuration:**
```swift
let index = USearchIndex.make(
    metric: .cos,
    dimensions: 384,
    connectivity: 16,
    quantization: .F16
)
```

**Index file location:**
```swift
let indexPath = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("vectors.usearch")
```

**Persistence:** `save()` is called after batch operations (not after every single insert) to amortize disk I/O. Save triggers:
- After EmbeddingIndexer completes a flush batch
- On app background
- On app termination (if possible)

**Rebuild from BlockEmbedding:**
```swift
func rebuild(from embeddings: [BlockEmbedding]) throws {
    index.clear()
    for emb in embeddings {
        guard let block = emb.block else { continue }
        add(blockId: block.id, vector: emb.embedding)
    }
    try save()
}
```

#### 3. `EmbeddingIndexer`

Location: `Noto/Search/EmbeddingIndexer.swift`

Processes dirty blocks through the embedding pipeline. Runs in the same flush pass as FTS5 indexing.

```
class EmbeddingIndexer {
    let embeddingModel: EmbeddingModel
    let hnswIndex: HNSWIndex
    let modelContext: ModelContext

    // Process dirty blocks — generate embeddings + insert HNSW
    func processDirtyBlocks(blockIds: [(UUID, DirtyOperation)]) async

    // Full rebuild for first launch
    func buildAll(progressHandler: ((Int, Int) -> Void)?) async

    // Rebuild HNSW from existing BlockEmbedding records (no CoreML needed)
    func rebuildIndex() async
}
```

**`processDirtyBlocks()` algorithm:**

For each (blockId, operation) pair:

1. **Delete operation:**
   - `hnswIndex.remove(blockId:)`
   - Delete the `BlockEmbedding` record from SwiftData
   - Continue to next

2. **Upsert operation:**
   a. Fetch `Block` from SwiftData by ID. If not found (deleted between dirty mark and flush), skip.
   b. Strip markdown from `block.content` using `PlainTextExtractor.plainText(from:)` (shared with FTS5 — see Spec-keyword-search.md)
   c. Count words. If < 3 words:
      - If block has an existing `BlockEmbedding`, delete it and remove from HNSW (block became too short)
      - Skip to next
   d. Compute `SHA256(plainText)`. If block has existing `BlockEmbedding` with matching `contentHash`, skip (content unchanged)
   e. Generate embedding: `embeddingModel.embed(plainText)` → `[Float]` (384 dims)
   f. Insert/update HNSW: `hnswIndex.add(blockId: block.id, vector: embedding)`
   g. Create or update `BlockEmbedding` in SwiftData:
      ```swift
      if let existing = block.embedding {
          existing.embedding = embedding
          existing.contentHash = hash
          existing.generatedAt = Date()
      } else {
          let emb = BlockEmbedding(
              block: block,
              embedding: embedding,
              modelVersion: "bge-small-en-v1.5",
              contentHash: hash
          )
          modelContext.insert(emb)
      }
      ```
   h. Save SwiftData context periodically (every 50 blocks)

3. After all blocks processed: `hnswIndex.save()`

**`buildAll()` algorithm (first launch):**
1. Fetch all non-archived blocks from SwiftData that don't have a `BlockEmbedding`
2. Process in batches of 50
3. For each block: strip markdown, check word count, generate embedding, insert HNSW, create BlockEmbedding
4. Call `progressHandler(completed, total)` after each batch
5. Save HNSW index after all batches

**`rebuildIndex()` algorithm (HNSW corruption recovery):**
1. Fetch all `BlockEmbedding` records from SwiftData
2. Create a fresh HNSW index
3. For each record: `hnswIndex.add(blockId:, vector: embedding)`
4. Save index
5. No CoreML inference needed — embeddings already exist

#### 4. `SemanticEngine`

Location: `Noto/Search/SemanticEngine.swift`

Query execution. Generates a query embedding, searches the HNSW index, post-filters, returns results.

```
struct SemanticEngine {
    let embeddingModel: EmbeddingModel
    let hnswIndex: HNSWIndex

    func search(
        query: String,
        dateRange: DateRange?,
        modelContext: ModelContext
    ) async -> [SemanticSearchResult]
}

struct SemanticSearchResult {
    let blockId: UUID
    let similarity: Float  // cosine similarity [0, 1]
}
```

**Search algorithm:**
1. Strip markdown from query via `PlainTextExtractor.plainText(from:)`
2. Generate query embedding: `embeddingModel.embed(query)` → `[Float]` (~30ms)
3. Search HNSW: `hnswIndex.search(vector: queryEmbedding, count: 200)` — over-fetch 200
4. Convert distances to similarities: `similarity = 1.0 - distance`
5. Apply threshold: keep results where `similarity >= 0.3`
6. If `dateRange` is provided:
   a. Collect passing block IDs
   b. Fetch from SwiftData: blocks where `id IN blockIds AND createdAt >= start AND createdAt <= end`
   c. Filter results to only include blocks that passed the date check
7. Return results sorted by similarity (descending)

**Over-fetch rationale:** Request 200 from HNSW because post-filtering (threshold + date) may discard many. 200 is enough headroom while keeping the HNSW search fast (<10ms even at 1M blocks).

---

## Model Preparation (One-Time Build Step)

### CoreML Conversion Script

Location: `scripts/convert_model.py` (not shipped in app, development-only)

```python
# Pseudocode for the conversion pipeline
# 1. Load bge-small-en-v1.5 from HuggingFace
# 2. Export to ONNX with sentence pooling + L2 normalization baked in
# 3. Convert ONNX to CoreML via coremltools
# 4. Output: bge-small-en-v1.5.mlmodelc + vocab.txt
```

The conversion must bake in:
- CLS token pooling (or mean pooling, matching the original model's strategy)
- L2 normalization of the output vector
- So the CoreML model outputs a ready-to-use unit-length embedding

The resulting `.mlmodelc` directory and `vocab.txt` are added to the Xcode project as bundle resources.

### Validating the Conversion

After conversion, verify that:
1. The CoreML model produces the same embeddings (within floating-point tolerance) as the Python model for a set of test sentences
2. Cosine similarity between known similar sentences is high (> 0.7)
3. Cosine similarity between known dissimilar sentences is low (< 0.3)

Include a test case that validates this with 5-10 sentence pairs.

---

## File Structure

```
Noto/Search/
├── EmbeddingModel.swift       # CoreML model wrapper + inference
├── HNSWIndex.swift            # usearch wrapper, UUID↔UInt64 mapping
├── SemanticEngine.swift       # Query execution, post-filtering
├── EmbeddingIndexer.swift     # Dirty block processing, batch embedding
├── Tokenizer/
│   ├── BertTokenizer.swift    # Vendored from swift-embeddings
│   └── WordPieceTokenizer.swift
├── Resources/
│   ├── bge-small-en-v1.5.mlmodelc/  # CoreML model (~33MB)
│   └── vocab.txt                     # BERT vocabulary

scripts/
└── convert_model.py           # One-time model conversion (dev only)
```

---

## Integration Points

### 1. Shared DirtyTracker

The `DirtyTracker` from the keyword search spec is shared. When dirty blocks are flushed, both the FTS5 and embedding pipelines process them. The orchestration happens in the hybrid search layer (or a shared `IndexingService`):

```swift
// On flush trigger (search open, background, launch):
await dirtyTracker.flush()
let dirtyBlocks = await fts5Database.fetchAllDirty()
await fts5Indexer.flushAll()              // keyword indexing
await embeddingIndexer.processDirtyBlocks(dirtyBlocks)  // semantic indexing
```

Both pipelines read from the same `dirty_blocks` table. The FTS5 indexer removes entries after processing; the embedding indexer processes the same list. Coordination: either process both before removing from `dirty_blocks`, or let each pipeline track its own completion state.

Simpler approach: the `dirty_blocks` table serves both pipelines. Process FTS5 and embeddings for each batch, then remove the batch from `dirty_blocks`. This is done in a single orchestrated pass.

### 2. Block Deletion Cascade

The `BlockEmbedding` model already has a cascade delete relationship with `Block` (defined in `Block.swift`: `embedding: BlockEmbedding?` with cascade). When a Block is deleted via SwiftData, the BlockEmbedding is automatically removed.

The HNSW index removal must be done explicitly since it's outside SwiftData. When `DirtyTracker.markDeleted()` is called, the embedding indexer handles the HNSW removal during flush.

### 3. SPM Dependency

Add `usearch` to `Package.swift` or the Xcode project's package dependencies:

```
https://github.com/unum-cloud/usearch
```

Import: `import USearch`

### 4. Initial Indexing Progress UI

On first launch, if there are existing blocks without embeddings, the `EmbeddingIndexer.buildAll()` runs in the background. The progress handler updates a published property that a progress view observes:

```swift
@Published var indexingProgress: (completed: Int, total: Int)?
```

This is shown in the search sheet or as a banner in the app. Not blocking — the user can continue using the app while indexing happens.

---

## Testing Strategy

### Unit Tests (Swift Testing)

| Test | What it verifies |
|------|-----------------|
| EmbeddingModel produces 384-dim output | Model loaded, inference works |
| EmbeddingModel output is normalized (L2 norm ≈ 1.0) | Conversion correctness |
| Similar sentences have high cosine similarity | Model quality |
| Dissimilar sentences have low cosine similarity | Model quality |
| WordPiece tokenizer matches expected token IDs | Tokenizer correctness |
| HNSWIndex add + search returns match | Basic HNSW operations |
| HNSWIndex remove excludes from results | Deletion works |
| HNSWIndex save + load preserves data | Persistence works |
| HNSWIndex search returns correct distances | Distance computation |
| EmbeddingIndexer skips blocks < 3 words | Short block handling |
| EmbeddingIndexer skips unchanged content (hash match) | Content hash check |
| EmbeddingIndexer creates BlockEmbedding in SwiftData | Storage integration |
| EmbeddingIndexer handles delete operations | HNSW + SwiftData cleanup |
| SemanticEngine applies similarity threshold | Threshold filtering |
| SemanticEngine applies date post-filter | Date range support |
| UUID→UInt64 key mapping is deterministic | Key consistency |

### Integration Tests

| Test | What it verifies |
|------|-----------------|
| End-to-end: create block → flush → search finds it | Full pipeline |
| Edit block content → re-embed → search reflects update | Content change handling |
| Delete block → search no longer returns it | Deletion pipeline |
| Rebuild HNSW from BlockEmbedding records | Corruption recovery |

### Model Validation Tests

Include a set of sentence pairs with expected similarity ranges:
```swift
@Test func knownSimilarSentencesAreClose() {
    let sim = cosineSimilarity(
        model.embed("aesthetic taste in design"),
        model.embed("artistic judgement and beauty")
    )
    #expect(sim > 0.5)
}

@Test func knownDissimilarSentencesAreFar() {
    let sim = cosineSimilarity(
        model.embed("grocery shopping list"),
        model.embed("quantum mechanics equations")
    )
    #expect(sim < 0.3)
}
```

---

## Performance Considerations

- **Neural Engine inference:** CoreML with `.computeUnits = .all` routes to Neural Engine when available (fastest), falls back to GPU → CPU. The ~30ms target assumes Neural Engine.
- **No main thread blocking:** All embedding generation and HNSW operations run on background actors/tasks. The `EmbeddingModel` and `HNSWIndex` are not `@MainActor`.
- **Batch save:** HNSW `save()` is called once per flush batch, not per insert. Amortizes disk I/O.
- **F16 quantization:** Halves HNSW memory usage with negligible recall loss for 384-dim vectors.
- **Over-fetch strategy:** Requesting 200 from HNSW when we may only need 50 after filtering. The extra HNSW work is ~1-2ms, much cheaper than multiple queries.

---

## Migration / Rollout

1. Add `usearch` SPM dependency
2. Bundle `bge-small-en-v1.5.mlmodelc` and `vocab.txt` in Xcode project
3. On first launch after update: `EmbeddingIndexer.buildAll()` runs in background, generating embeddings for all existing blocks and building the HNSW index
4. Progress indicator shown until initial indexing completes
5. Subsequent updates: incremental via dirty tracking
