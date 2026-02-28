# PRD: Data Structure for Personal Notetaking App

## Overview

This document defines the data structure for an outline-based note-taking app with semantic search and bidirectional linking.

**Scope Decisions:**
- **Sync:** Local-only for v1 (cross-device sync deferred)
- **Content:** Text-only for v1 (images/files deferred)
- **Conflict resolution:** Last-Writer-Wins when sync is added

---

## Core Requirements

| Requirement | Implication for Data Structure |
|-------------|-------------------------------|
| Outline-based notes | Hierarchical tree structure with parent-child relationships |
| Blocks individually addressable | Every block needs a globally unique ID |
| Bidirectional linking | Need to track both outgoing links and backlinks |
| Semantic + keyword search | Store embeddings + maintain full-text search index |
| Offline-first | Local-first storage (SwiftData/SQLite) |

---

## Data Models

### 1. Block (Core Entity)

The fundamental unit of the app. Everything is a block.

```
Block
├── id: UUID                    # Globally unique identifier
├── content: String             # Markdown text content
├── createdAt: Date
├── updatedAt: Date
├── sortOrder: Double           # For ordering siblings (fractional indexing)
│
├── parentId: UUID?             # nil = root block
├── depth: Int                  # Cached depth for query optimization
│
├── isArchived: Bool            # Soft delete
│
└── extensionData: Data?        # JSON blob for future metadata (schema-less)
```

**Key Design Decisions:**
- `sortOrder` uses fractional indexing (e.g., 0.5 between 0 and 1) to allow reordering without updating siblings
- `depth` is denormalized for efficient queries (e.g., "get all blocks at depth 2")
- Root blocks have `parentId = nil`
- `extensionData` is a schema-less JSON blob for future metadata without schema migrations

**Block Movement Operations:**

Moving a block requires updating `parentId`, `sortOrder`, and `depth` (plus descendants' depth).

| Operation | Description | Fields Updated |
|-----------|-------------|----------------|
| Reorder within siblings | Move block up/down among siblings | `sortOrder` only |
| Indent | Make block a child of previous sibling | `parentId`, `sortOrder`, `depth` (and descendants) |
| Outdent | Make block a sibling of its parent | `parentId`, `sortOrder`, `depth` (and descendants) |
| Move to new parent | Drag block to different parent | `parentId`, `sortOrder`, `depth` (and descendants) |

**Depth Recalculation Algorithm:**
```
function moveBlock(block, newParent, newSortOrder):
    oldDepth = block.depth
    newDepth = (newParent == nil) ? 0 : newParent.depth + 1
    depthDelta = newDepth - oldDepth

    block.parentId = newParent?.id
    block.sortOrder = newSortOrder
    block.depth = newDepth

    // Update all descendants' depth
    for descendant in block.allDescendants():
        descendant.depth += depthDelta
```

---

### 2. BlockLink (Bidirectional Linking)

Tracks references between blocks.

```
BlockLink
├── id: UUID
├── sourceBlockId: UUID         # Block containing the mention
├── targetBlockId: UUID         # Block being mentioned
├── mentionText: String?        # The text used for the mention (for display)
├── rangeStart: Int             # Character offset where mention starts
├── rangeEnd: Int               # Character offset where mention ends
└── createdAt: Date
```

**Bidirectional Queries:**
- **Outgoing links:** `WHERE sourceBlockId = X`
- **Backlinks (incoming):** `WHERE targetBlockId = X`

**Linked Editing:**
- When `targetBlock.content` changes, update `mentionText` in all links pointing to it
- Links are inline references; character ranges allow precise positioning

---

### 3. BlockEmbedding (Semantic Search)

Stores vector embeddings for semantic search.

```
BlockEmbedding
├── id: UUID
├── blockId: UUID               # One-to-one with Block
├── embedding: [Float]          # Vector (e.g., 384 or 768 dimensions)
├── modelVersion: String        # Track which model generated it
├── generatedAt: Date
└── contentHash: String         # Hash of content when embedding was generated
```

**Offline Semantic Search:**
- Use on-device model (e.g., Apple's NaturalLanguage framework or a bundled ONNX model)
- `contentHash` detects when re-embedding is needed
- Index with approximate nearest neighbor (ANN) for fast queries

---

### 4. SearchIndex (Keyword Search)

For full-text keyword search. Can leverage SQLite FTS5 or SwiftData's built-in search.

```
SearchIndex
├── blockId: UUID
├── searchableText: String      # Normalized, lowercased content
├── tokens: [String]            # Pre-tokenized for fast matching
└── lastIndexedAt: Date
```

**Hybrid Search Algorithm:**
1. Run keyword search (FTS5 or token matching)
2. Run semantic search (cosine similarity on embeddings)
3. Combine scores: `finalScore = α * keywordScore + (1-α) * semanticScore`
4. Rank by `finalScore`

---

### 5. Tag

For categorization and template assignment.

```
Tag
├── id: UUID
├── name: String
├── color: String?              # Hex color code
└── createdAt: Date
```

---

### 6. BlockTag (Many-to-Many)

```
BlockTag
├── id: UUID
├── blockId: UUID
├── tagId: UUID
└── createdAt: Date
```

---

### 7. MetadataField

Custom metadata fields attached to blocks.

```
MetadataField
├── id: UUID
├── blockId: UUID
├── fieldName: String           # e.g., "status", "priority"
├── fieldValue: String          # Stored as string, parsed by type
└── fieldType: MetadataType     # enum: text, number, date, select
```

---

## Sync Architecture (Deferred to v2)

For v1, the app is **local-only**. Data lives in SwiftData (SQLite) on-device.

**When adding sync later (v2):**
- Add `SyncMetadata` to all entities (version, deviceId, pendingSync)
- Use Last-Writer-Wins with Lamport timestamps
- Add `SyncQueue` for offline change tracking
- Consider CloudKit for Apple-native sync

---

## Relationships Diagram

```
                    ┌─────────────┐
                    │    Block    │
                    └─────────────┘
                          │
        ┌─────────┬───────┼───────┬─────────┐
        │         │       │       │         │
        ▼         ▼       ▼       ▼         ▼
   ┌─────────┐ ┌──────┐ ┌─────┐ ┌────┐ ┌─────────┐
   │BlockLink│ │Block │ │Block│ │Tag │ │BlockLink│
   │(source) │ │Embed │ │Tag  │ │    │ │(target) │
   └─────────┘ └──────┘ └─────┘ └────┘ └─────────┘

Block self-references (parent-child):
Block.parentId → Block.id
```

---

## SwiftData Implementation Notes

### Schema Definition

```swift
@Model
final class Block {
    @Attribute(.unique) var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Double
    var depth: Int
    var isArchived: Bool
    var extensionData: Data?    // JSON blob for future metadata

    // Relationships
    var parent: Block?
    @Relationship(deleteRule: .cascade, inverse: \Block.parent)
    var children: [Block]

    @Relationship(deleteRule: .cascade)
    var outgoingLinks: [BlockLink]

    @Relationship(deleteRule: .cascade)
    var tags: [BlockTag]

    @Relationship(deleteRule: .cascade)
    var embedding: BlockEmbedding?

    @Relationship(deleteRule: .cascade)
    var metadataFields: [MetadataField]
}
```

### Storage Strategy

| Data Type | Storage | Reasoning |
|-----------|---------|-----------|
| Blocks, Links, Tags | SwiftData (SQLite) | Relational queries, ACID |
| Embeddings | SwiftData + optional vector DB | Start simple, optimize later |
| Full-text index | SQLite FTS5 (via raw SQL) | Native, fast, offline |

---

## Search Implementation

### Hybrid Search Algorithm (Pseudocode)

```
function search(query: String) -> [Block]:
    // 1. Keyword search
    keywordResults = FTS5.search(query)
    keywordScores = normalize(keywordResults.scores)

    // 2. Semantic search
    queryEmbedding = embedModel.encode(query)
    semanticResults = vectorIndex.nearestNeighbors(queryEmbedding, k=100)
    semanticScores = normalize(semanticResults.similarities)

    // 3. Combine
    allBlockIds = union(keywordResults.ids, semanticResults.ids)
    for blockId in allBlockIds:
        kScore = keywordScores[blockId] ?? 0
        sScore = semanticScores[blockId] ?? 0
        finalScore = 0.6 * kScore + 0.4 * sScore  // Tunable weights

    // 4. Rank and return
    return sortByScore(allBlockIds)
```

### Offline Embedding Generation

- Use Apple's `NLEmbedding` (built into iOS/macOS) for basic semantic similarity
- Or bundle a small transformer model (e.g., MiniLM via ONNX/Core ML)
- Regenerate embeddings when `Block.content` changes (debounced)

---

## Performance Considerations

1. **Fractional indexing** for `sortOrder` avoids updating N siblings on reorder
2. **Denormalized `depth`** enables efficient depth-based queries
3. **Lazy embedding generation** - generate on idle, not on every keystroke
4. **Pagination** for large note trees - load visible blocks + buffer
5. **Index backlinks** - compound index on `(targetBlockId, createdAt)`

---

## Migration Path

1. **v1:** Implement all data models (Block, BlockLink, Tag, BlockTag, MetadataField, BlockEmbedding, SearchIndex)
2. **v1:** Build minimal test UI for Block CRUD and linking
3. **v2:** Add Tag UI and MetadataField UI
4. **v3:** Add Search UI (keyword + semantic)
5. **v4:** Add `SyncMetadata`, `SyncQueue` for cross-device sync
6. **Future:** Templates (deferred, needs scoping)

---

## Decisions Made

| Question | Decision |
|----------|----------|
| Sync backend | Local-only for v1 |
| Rich content | Text-only for v1 |
| Conflict resolution | Last-Writer-Wins when sync is added |

---

## Minimal Test UI

A basic UI is needed to validate the data structure before building the full app.

**Required functionality:**
- Create, edit, delete blocks
- Nest blocks (create children, move between parents)
- Reorder sibling blocks (test fractional indexing)
- Create links between blocks (test bidirectional linking)
- View backlinks for a block

**UI can be simple:**
- Single view with outline tree
- Tap to select/edit block content
- Swipe or buttons for delete/indent/outdent
- Modal or inline for linking

This test UI validates the data layer before investing in the final UI/UX.

---

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `Noto/Models/Block.swift` | Create | Core Block model with SwiftData |
| `Noto/Models/BlockLink.swift` | Create | Bidirectional linking model |
| `Noto/Models/Tag.swift` | Create | Tag and BlockTag models |
| `Noto/Models/MetadataField.swift` | Create | Custom metadata fields for blocks |
| `Noto/Models/BlockEmbedding.swift` | Create | Embedding storage for semantic search |
| `Noto/Models/SearchIndex.swift` | Create | Full-text search index |
| `Noto/Item.swift` | Delete | Replace with new Block model |
| `Noto/NotoApp.swift` | Modify | Update ModelContainer schema |
| `Noto/Views/TestOutlineView.swift` | Create | Minimal test UI for outline tree |
| `Noto/Views/BlockRowView.swift` | Create | Single block row component |
| `Noto/ContentView.swift` | Modify | Replace with TestOutlineView |
| `NotoTests/BlockTests.swift` | Create | Unit tests for Block and BlockLink |

---

## Success Criteria

Implementation is complete when ALL of the following are true:

### Data Models
- [ ] `Block` model created with all fields (id, content, createdAt, updatedAt, sortOrder, depth, isArchived, extensionData)
- [ ] `Block` has working parent-child relationship (self-referencing)
- [ ] `BlockLink` model created with source/target block references
- [ ] `Tag` and `BlockTag` models created
- [ ] `MetadataField` model created
- [ ] `BlockEmbedding` model created
- [ ] `SearchIndex` model created
- [ ] App compiles and runs without errors on iOS and macOS

### Core Operations (verified via Test UI)
- [ ] Can create a new root block
- [ ] Can create a child block under any existing block
- [ ] Can edit block content inline
- [ ] Can delete a block (and its children cascade delete)
- [ ] Can reorder siblings via drag or buttons (fractional indexing works)
- [ ] Can indent a block (move to become child of previous sibling)
- [ ] Can outdent a block (move to become sibling of parent)
- [ ] Can move a block to a different parent (drag and drop or UI action)
- [ ] Moving a block with children updates all descendants' depth correctly

### Bidirectional Linking (verified via Test UI)
- [ ] Can create a link from one block to another
- [ ] Can view outgoing links from a block
- [ ] Can view backlinks (incoming links) to a block
- [ ] Deleting a block removes its associated links

### Test UI
- [ ] Outline tree displays blocks with proper indentation by depth
- [ ] UI is functional on both iOS and macOS
- [ ] All core operations accessible via UI (no console/debug-only features)

### Unit Tests
- [ ] All tests in "Required Tests" section are implemented
- [ ] All tests pass

### NOT in scope for Test UI (data models still required)
- Search UI (but implement BlockEmbedding, SearchIndex models)
- Tag UI (but implement Tag, BlockTag models)
- Metadata fields UI (but implement MetadataField model)
- Templates
- Sync

---

## Required Tests

Unit tests to verify data structure correctness:

### Block CRUD Tests
- `testCreateBlock` - Creating a block persists all fields correctly
- `testUpdateBlockContent` - Updating content updates `updatedAt` timestamp
- `testDeleteBlock` - Deleting a block removes it from the database
- `testCascadeDeleteChildren` - Deleting a parent block deletes all descendants

### Hierarchy Tests
- `testCreateChildBlock` - Child block has correct `parentId` and `depth`
- `testDepthCalculation` - Nested blocks have correct depth (root=0, child=1, grandchild=2)
- `testRootBlockHasNilParent` - Root blocks have `parentId = nil`

### Block Movement Tests
- `testIndentBlock` - Indenting sets parent to previous sibling, updates depth
- `testOutdentBlock` - Outdenting sets parent to grandparent, updates depth
- `testMoveBlockToNewParent` - Moving a block updates `parentId` and recalculates `depth` for subtree
- `testMoveBlockWithDescendants` - Moving a block updates depth of all descendants correctly
- `testMoveToRoot` - Moving a nested block to root sets `parentId = nil` and `depth = 0`
- `testCannotMoveBlockUnderItself` - Prevent moving a block to be a descendant of itself (circular reference)

### Sibling Ordering Tests
- `testSortOrderOnCreate` - New siblings get correct `sortOrder` values
- `testReorderSiblings` - Moving a block between siblings updates `sortOrder` correctly
- `testFractionalIndexing` - Inserting between two blocks uses midpoint `sortOrder`
- `testSiblingsReturnInOrder` - Querying children returns them sorted by `sortOrder`

### BlockLink Tests
- `testCreateLink` - Link created with correct source and target
- `testQueryOutgoingLinks` - Can fetch all links where block is source
- `testQueryBacklinks` - Can fetch all links where block is target
- `testDeleteBlockRemovesLinks` - Deleting a block removes links where it's source or target
- `testLinkPersistsMentionText` - Link stores the mention text correctly

### Edge Cases
- `testEmptyContent` - Block can have empty string content
- `testDeepNesting` - Can create blocks nested 10+ levels deep
- `testManyChildren` - Parent can have 100+ children without issues
- `testSelfLinkPrevented` - Cannot create a link from a block to itself (if enforced)
