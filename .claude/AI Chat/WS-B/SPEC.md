# Technical Spec: BlockBuilder Extensions

## File Changes

### `Packages/NotoCore/Sources/NotoCore/BlockBuilder.swift`

Add to existing `BlockBuilder` struct (do NOT modify `buildPath` or `BuildStep`).

#### `BlockBuilderError`

```
public enum BlockBuilderError: Error, Equatable
  case notEditable(UUID)
  case notDeletable(UUID)
```

#### `addBlock(content:parent:afterSibling:extensionData:context:) -> Block`

```
@MainActor public static func addBlock(...)
  1. Compute sortOrder:
     - If afterSibling is provided:
       - Find next sibling: parent.sortedChildren first where sortOrder > afterSibling.sortOrder
       - sortOrder = Block.sortOrderBetween(afterSibling.sortOrder, nextSibling?.sortOrder)
     - Else:
       - sortOrder = Block.sortOrderForAppending(to: parent.sortedChildren)
  2. Create Block(content:, parent:, sortOrder:, extensionData:)
  3. context.insert(newBlock)
  4. Log creation
  5. Return newBlock
```

#### `updateBlock(_:newContent:) throws`

```
@MainActor public static func updateBlock(...)
  1. Guard block.isContentEditableByUser else throw .notEditable(block.id)
  2. block.updateContent(newContent)
  3. Log update
```

#### `archiveBlock(_:) throws`

```
@MainActor public static func archiveBlock(...)
  1. Guard block.isDeletable else throw .notDeletable(block.id)
  2. block.isArchived = true
  3. block.updatedAt = Date()
  4. Log archive
```

### `Packages/NotoCore/Tests/NotoCoreTests/BlockBuilderExtensionTests.swift`

New test file using Swift Testing (`@Test`, `#expect`). Tests:

1. Add block between two siblings — sortOrder is between them
2. Add block at end — sortOrder after last child
3. Add block to empty parent — works correctly
4. Update editable block — content changes, updatedAt updated
5. Update non-editable block — throws notEditable
6. Archive deletable block — isArchived becomes true
7. Archive non-deletable block — throws notDeletable

## Dependencies

- No new package dependencies
- Uses existing `Block` model methods: `sortOrderBetween`, `sortOrderForAppending`, `updateContent`
- Uses existing `createTestContainer()` from NotoModels
