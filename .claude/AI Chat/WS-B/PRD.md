# PRD: BlockBuilder Extensions — Generic Block Operations

## Problem

BlockBuilder currently only supports `buildPath` — creating/finding blocks along a hierarchy path. AI Chat and other future features need generic CRUD operations on individual blocks: adding a block at a specific position, updating content, and archiving. These operations must respect block protection flags (`isContentEditableByUser`, `isDeletable`).

## Goals

1. Add a block as a child of any parent, positioned after a specific sibling or appended at the end
2. Update a block's content, respecting the `isContentEditableByUser` flag
3. Archive (soft-delete) a block, respecting the `isDeletable` flag
4. Provide clear error types for protection violations

## Non-Goals

- Dirty tracking (callers handle this)
- Undo/redo support
- Batch operations
- Hard deletion of blocks

## Design

### `addBlock`

- Parameters: content, parent block, optional afterSibling block, optional extensionData, ModelContext
- Sort order: If afterSibling provided, use `Block.sortOrderBetween(afterSibling.sortOrder, nextSibling?.sortOrder)`. Otherwise use `Block.sortOrderForAppending(to: parent.sortedChildren)`
- Depth: `parent.depth + 1` (handled by Block's init)
- Inserts into ModelContext and returns the new Block

### `updateBlock`

- Parameters: block, newContent string
- Guard: throws `BlockBuilderError.notEditable(block.id)` if `!block.isContentEditableByUser`
- Delegates to `block.updateContent(newContent)` which sets content + updatedAt

### `archiveBlock`

- Parameters: block
- Guard: throws `BlockBuilderError.notDeletable(block.id)` if `!block.isDeletable`
- Sets `isArchived = true` and `updatedAt = Date()`

### Error type

`BlockBuilderError` enum conforming to `Error`:
- `.notEditable(UUID)` — block's content is not user-editable
- `.notDeletable(UUID)` — block is not deletable
