# Spec: Semantic Search (Embeddings + HNSW)

Based on [PRD-semantic-search.md](./PRD-semantic-search.md).

**Dependencies:** Spec-search-foundation (FTS5Database, DirtyTracker, PlainTextExtractor, vector_key_map table).

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
- [ ] Markdown is stripped before embedding generation (via `PlainTextExtractor` from foundation)
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
DirtyTracker (from foundation)
        │
        │ dirty block IDs (from dirty_blocks table)
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

The conversion script bakes in CLS pooling and L2 normalization so the CoreML model outputs a ready-to-use normalized embedding.

**WordPiece tokenizer:**

Tokenization algorithm:
1. Lowercase the input text
2. Split into words on whitespace and punctuation
3. For each word, find the longest matching prefix in vocab
4. Split remainder into subword tokens (prefixed with `##`)
5. Prepend `[CLS]` token (ID 101), append `[SEP]` token (ID 102)
6. Pad or truncate to model's max sequence length (512 tokens)
7. Generate `attention_mask` (1 for real tokens, 0 for padding)

Implementation: vendor the tokenizer from `swift-embeddings` — specifically `BertTokenizer` and `WordPieceTokenizer`.

**Vendored files:**
- `Noto/Search/Tokenizer/BertTokenizer.swift`
- `Noto/Search/Tokenizer/WordPieceTokenizer.swift`

#### 2. `HNSWIndex`

Location: `Noto/Search/HNSWIndex.swift`

Wraps `usearch` with Noto-specific conventions. Translates between `UUID` block IDs and `usearch`'s `UInt64` keys via the foundation's `vector_key_map` table.

```
class HNSWIndex {
    init(path: URL, fts5Database: FTS5Database)
    func add(blockId: UUID, vector: [Float])
    func remove(blockId: UUID)
    func search(vector: [Float], count: Int) -> [(blockId: UUID, distance: Float)]
    func contains(blockId: UUID) -> Bool
    func save() throws
    var count: Int { get }
}
```

**UUID ↔ UInt64 key mapping:**

Use the first 8 bytes of UUID as UInt64 key (deterministic truncation). Store mapping in `vector_key_map` table (from foundation's `FTS5Database`).

```swift
func uuidToKey(_ uuid: UUID) -> UInt64 {
    let bytes = uuid.uuid
    return UInt64(bytes.0) | (UInt64(bytes.1) << 8) | ... | (UInt64(bytes.7) << 56)
}
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
let indexPath = appSupportDir.appendingPathComponent("vectors.usearch")
```

**Persistence:** `save()` called after batch operations (not per insert). Save triggers:
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

    func processDirtyBlocks(blockIds: [(UUID, DirtyOperation)]) async
    func buildAll(progressHandler: ((Int, Int) -> Void)?) async
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
   a. Fetch `Block` from SwiftData by ID. If not found, skip.
   b. Strip markdown via `PlainTextExtractor.plainText(from:)`
   c. Count words. If < 3 words:
      - If block has existing `BlockEmbedding`, delete it and remove from HNSW
      - Skip to next
   d. Compute `SHA256(plainText)`. If existing `BlockEmbedding` has matching `contentHash`, skip
   e. Generate embedding: `embeddingModel.embed(plainText)` → `[Float]`
   f. Insert/update HNSW: `hnswIndex.add(blockId: block.id, vector: embedding)`
   g. Create or update `BlockEmbedding` in SwiftData
   h. Save SwiftData context periodically (every 50 blocks)

3. After all blocks processed: `hnswIndex.save()`

**`buildAll()` algorithm (first launch):**
1. Fetch all non-archived blocks without a `BlockEmbedding`
2. Process in batches of 50
3. Call `progressHandler(completed, total)` after each batch
4. Save HNSW index after all batches

**`rebuildIndex()` algorithm (HNSW corruption recovery):**
1. Fetch all `BlockEmbedding` records
2. Create fresh HNSW index
3. Insert all embeddings — no CoreML inference needed
4. Save index

#### 4. `SemanticEngine`

Location: `Noto/Search/SemanticEngine.swift`

Query execution. Generates a query embedding, searches HNSW, post-filters, returns results.

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
   c. Filter results to only include blocks that passed
7. Return sorted by similarity descending

---

## Model Preparation (One-Time Build Step)

### CoreML Conversion Script

Location: `scripts/convert_model.py` (development-only, not shipped)

The conversion must bake in:
- CLS token pooling (or mean pooling, matching original model)
- L2 normalization of output vector

The resulting `.mlmodelc` directory and `vocab.txt` are added to Xcode as bundle resources.

### Validating the Conversion

Verify that:
1. CoreML model produces same embeddings as Python model (within floating-point tolerance)
2. Cosine similarity between known similar sentences > 0.7
3. Cosine similarity between known dissimilar sentences < 0.3

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

The `DirtyTracker` from foundation is shared. When dirty blocks are flushed, both FTS5 and embedding pipelines process them in a single orchestrated pass:

```swift
// On flush trigger:
await dirtyTracker.flush()
let dirtyBlocks = await fts5Database.fetchAllDirty()
await fts5Indexer.flushAll()
await embeddingIndexer.processDirtyBlocks(dirtyBlocks)
```

Both pipelines process the same batch before entries are removed from `dirty_blocks`.

### 2. Block Deletion Cascade

`BlockEmbedding` has cascade delete with `Block` in SwiftData — automatic cleanup. HNSW removal is explicit during `EmbeddingIndexer.processDirtyBlocks()`.

### 3. SPM Dependency

Add `usearch` to Xcode project's package dependencies:
```
https://github.com/unum-cloud/usearch
```
Import: `import USearch`

### 4. Initial Indexing Progress UI

`EmbeddingIndexer.buildAll()` progress handler updates a published property for a progress view:
```swift
@Published var indexingProgress: (completed: Int, total: Int)?
```

---

## Testing Strategy

### Design Principle

Layered tests to minimize CoreML overhead. HNSW tests use synthetic vectors. Only `EmbeddingModel` and validation tests run real inference.

### Test Helpers

```swift
func createTestHNSWIndex() throws -> (HNSWIndex, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hnsw-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let (db, _) = try await createTestFTS5Database()  // from foundation test helpers
    let index = HNSWIndex(path: tempDir.appendingPathComponent("test.usearch"), fts5Database: db)
    return (index, tempDir)
}

func randomVector(dimensions: Int = 384) -> [Float] {
    var v = (0..<dimensions).map { _ in Float.random(in: -1...1) }
    let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
    return v.map { $0 / norm }
}

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
}
```

### Unit Tests (Swift Testing)

#### EmbeddingModel (requires CoreML model)

| Test | Setup | Assert |
|------|-------|--------|
| 384-dim output | `model.embed("hello world")` | `result.count == 384` |
| Output normalized | `model.embed("any text")` | L2 norm ≈ 1.0 (within 0.001) |
| Deterministic | Same input twice | Identical vectors |
| Empty string | `model.embed("")` | Valid 384-dim vector |
| Long text | 600-word input | Valid vector (truncated at 512 tokens) |
| Batch inference | `model.embed(batch: ["a", "b", "c"])` | 3 vectors, each 384-dim |

#### Model Validation (requires CoreML model)

```swift
// Similar pairs — cosine similarity > 0.5
("aesthetic taste in design", "artistic judgement and beauty")
("the morning coffee was delicious", "I enjoyed the espresso today")
("meeting notes from the design review", "team discussion about UI feedback")
("running a marathon in the rain", "jogging through a storm")
("machine learning neural network", "deep learning AI model")

// Dissimilar pairs — cosine similarity < 0.3
("grocery shopping list", "quantum mechanics equations")
("fixing a plumbing leak", "playing guitar at a concert")
("baking chocolate cake recipe", "corporate tax regulations")
```

#### WordPiece Tokenizer

| Test | Input | Assert |
|------|-------|--------|
| Basic tokenization | `"hello world"` | Starts with [CLS], ends with [SEP] |
| Known token IDs | `"the"` | Expected ID from vocab |
| Subword splitting | `"unaffable"` | Splits with `##` prefixes |
| Punctuation | `"hello, world!"` | Punctuation separate |
| Unicode | `"café"` | Handles accented characters |
| Max length | 1000-word input | Capped at 512 tokens |
| Attention mask | `"short"` | 1 for real tokens, 0 for padding |

#### HNSWIndex (synthetic vectors)

| Test | Setup | Assert |
|------|-------|--------|
| Add + search | Insert 1 vector → search same | Returns inserted ID, distance ≈ 0 |
| K-nearest | Insert 10, one biased toward query | Biased vector ranks first |
| Remove | Insert → remove → search | Removed ID absent |
| Contains | Insert → contains | True; non-existent → false |
| Save + load | Insert 100 → save → reload → search | Same results |
| Count | Insert 5 → remove 2 | `count == 3` |
| Empty search | No insertions | Returns `[]` |

#### UUID Key Mapping

| Test | Setup | Assert |
|------|-------|--------|
| Deterministic | Same UUID twice | Same UInt64 both times |
| Distinct keys | 1000 random UUIDs | No collisions |
| Round-trip via vector_key_map | Set → lookup | Correct UUID |

#### EmbeddingIndexer (SwiftData container + HNSW temp)

| Test | Setup | Assert |
|------|-------|--------|
| Skips < 3 words | Block "ok" | No BlockEmbedding, not in HNSW |
| Skips unchanged | Process → process again | CoreML called once |
| Creates BlockEmbedding | Block with 5+ words | BlockEmbedding exists with correct hash |
| Handles delete | Process → delete → process | Removed from HNSW + BlockEmbedding |
| Short → long | Block "ok" updated to longer | Now embedded |
| Long → short | Long block updated to "ok" | Embedding removed |

#### SemanticEngine

| Test | Setup | Assert |
|------|-------|--------|
| Threshold filters | Known distances | Only similarity >= 0.3 |
| Date post-filter | Blocks at different dates | Only in-range returned |
| No date filter | No dateRange | All above-threshold returned |
| Empty query | `search(query: "")` | Returns `[]` |

---

## Performance Considerations

- **Neural Engine inference:** CoreML `.computeUnits = .all` routes to Neural Engine when available (~30ms).
- **No main thread blocking:** All embedding and HNSW operations on background actors.
- **Batch save:** HNSW `save()` once per flush batch, not per insert.
- **F16 quantization:** Halves memory with negligible recall loss.
- **Over-fetch 200:** Extra HNSW work is ~1-2ms, cheaper than multiple queries.

---

## Migration / Rollout

1. Add `usearch` SPM dependency
2. Bundle `bge-small-en-v1.5.mlmodelc` and `vocab.txt` in Xcode project
3. On first launch: `EmbeddingIndexer.buildAll()` runs in background
4. Progress indicator shown until complete
5. Subsequent updates: incremental via dirty tracking
