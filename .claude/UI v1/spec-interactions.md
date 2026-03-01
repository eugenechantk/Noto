# Feature Spec: User Interactions

Derived from [PRD-interactions.md](PRD-interactions.md). Each acceptance criterion is written as a testable scenario.

---

## Feature: Block Creation

### User Story

As a user, I want to create new blocks by pressing Return or tapping empty space, just like creating new lines in a text editor.

### Acceptance Criteria

**AC-BC-1: Return key creates sibling below**
- Given: Blocks "Alpha", "Beta" exist; cursor is at end of "Alpha"
- When: The user presses Return
- Then: A new empty block is inserted between "Alpha" and "Beta"
- And: The new block has the same parentId and depth as "Alpha"
- And: The new block's sortOrder is midpoint between "Alpha" and "Beta"
- And: Cursor moves to the new empty block

**AC-BC-2: Return on last block creates block at end**
- Given: "Alpha" is the last sibling; cursor is at end of "Alpha"
- When: The user presses Return
- Then: A new empty block is created after "Alpha"
- And: The new block's sortOrder = Alpha's sortOrder + 1

**AC-BC-3: Return at beginning of non-empty block inserts above**
- Given: Block "Alpha" has content; cursor is at position 0 (beginning)
- When: The user presses Return
- Then: A new empty block is inserted above "Alpha"
- And: "Alpha" retains its content unchanged
- And: Cursor remains in "Alpha"

**AC-BC-4: Tap empty space on empty screen creates first block**
- Given: No blocks exist
- When: The user taps on the empty screen area
- Then: A new root block is created with parentId = nil, depth = 0, sortOrder = 1.0
- And: The block enters edit mode with keyboard visible

**AC-BC-5: Tap below last block creates new block at end**
- Given: Blocks exist on the screen
- When: The user taps the empty space below the last visible block
- Then: A new block is created at the end of the sibling list
- And: The block enters edit mode

**AC-BC-6: New child in node view gets correct parentId and depth**
- Given: The user is in the node view for a block with depth = 2
- When: A new block is created (Return key or tap empty space)
- Then: The new block has parentId = currentNode.id
- And: The new block has depth = 3 (currentNode.depth + 1)

**AC-BC-7: New block has empty content**
- Given: Any creation scenario
- When: A new block is created
- Then: Its content is an empty string

---

## Feature: Block Deletion

### User Story

As a user, I want Backspace on an empty block to delete it and move my cursor up, just like deleting an empty line in a text editor.

### Acceptance Criteria

**AC-BD-1: Backspace on empty block deletes it**
- Given: An empty block exists between "Alpha" and "Beta"
- When: The user presses Backspace while the empty block is focused
- Then: The empty block is removed
- And: Cursor moves to the end of "Alpha" (the previous block)

**AC-BD-2: Deletion cascades to children**
- Given: Block "Parent" (empty) has children "Child A" and "Child B"; "Child B" has child "Grandchild"
- When: The user presses Backspace on empty "Parent"
- Then: "Parent", "Child A", "Child B", and "Grandchild" are all deleted (isArchived = true)

**AC-BD-3: Backspace on non-empty block does not delete**
- Given: Block "Alpha" has content "Hello"
- When: The user presses Backspace with cursor at position 1
- Then: The character "H" is deleted (normal text editing)
- And: The block itself is NOT deleted

**AC-BD-4: Delete only triggers when block is empty**
- Given: Block has content "X" (single character)
- When: The user presses Backspace (deleting "X", making it empty)
- Then: The block becomes empty but is NOT deleted on this keypress
- And: A second Backspace would delete the now-empty block

**AC-BD-5: Cursor moves to end of previous block after deletion**
- Given: Blocks "Alpha" (content: "Hello"), empty block, "Beta"
- When: The empty block is deleted via Backspace
- Then: Cursor is positioned at the end of "Alpha" (after the "o" in "Hello")

---

## Feature: Indent (Make Child of Previous Sibling)

### User Story

As a user, I want to indent a block to make it a child of the block above it, creating hierarchy without leaving edit mode.

### Acceptance Criteria

**AC-IN-1: Indent sets parentId to previous sibling**
- Given: Siblings "Alpha" (sortOrder 1), "Beta" (sortOrder 2) at depth 0
- When: The user indents "Beta"
- Then: "Beta".parentId = "Alpha".id
- And: "Beta".depth = 1

**AC-IN-2: Indent increments depth for all descendants**
- Given: "Beta" at depth 0 has children "Child A" (depth 1) and "Child B" (depth 1)
- When: The user indents "Beta"
- Then: "Beta".depth = 1, "Child A".depth = 2, "Child B".depth = 2

**AC-IN-3: Indent disabled for first sibling**
- Given: "Alpha" is the first sibling (no previous sibling at the same level)
- When: The user attempts to indent "Alpha"
- Then: The operation fails / is a no-op
- And: The Indent button is visually disabled (greyed out)

**AC-IN-4: Indent button triggers indent on iOS**
- Given: Edit mode is active, block is not the first sibling
- When: The user taps the Indent (→) button on the format bar (Liquid Glass styled with `.glassEffect(.regular.interactive())`)
- Then: The block is indented under its previous sibling

---

## Feature: Outdent (Make Sibling of Parent)

### User Story

As a user, I want to outdent a block to move it up one hierarchy level.

### Acceptance Criteria

**AC-OUT-1: Outdent sets parentId to grandparent**
- Given: "Child" (depth 1) has parent "Parent" (depth 0), which has parent nil (root)
- When: The user outdents "Child"
- Then: "Child".parentId = nil (grandparent)
- And: "Child".depth = 0
- And: "Child" is inserted after "Parent" in the root sibling list

**AC-OUT-2: Outdent decrements depth for all descendants**
- Given: "Child" at depth 1 has descendants "GC1" (depth 2) and "GGC1" (depth 3)
- When: The user outdents "Child"
- Then: "Child".depth = 0, "GC1".depth = 1, "GGC1".depth = 2

**AC-OUT-3: Outdent disabled for root blocks**
- Given: "Alpha" is a root block (depth = 0, parentId = nil)
- When: The user attempts to outdent "Alpha"
- Then: The operation fails / is a no-op
- And: The Outdent button is visually disabled (greyed out)

**AC-OUT-4: Outdent button triggers outdent on iOS**
- Given: Edit mode is active, block is not at root level
- When: The user taps the Outdent (←) button on the format bar (Liquid Glass styled with `.glassEffect(.regular.interactive())`)
- Then: The block is outdented to become a sibling of its parent

---

## Feature: Reorder (Long Press + Drag)

### User Story

As a user, I want to long-press a block and drag it to reorder it among its siblings.

### Acceptance Criteria

**AC-RO-1: Long press activates reorder mode**
- Given: A block "Beta" exists on any screen
- When: The user long-presses on "Beta"
- Then: The block lifts up visually indicating reorder mode

**AC-RO-2: Move block down recalculates sortOrder**
- Given: Siblings "Alpha" (sortOrder 1), "Beta" (sortOrder 2), "Gamma" (sortOrder 3)
- When: "Alpha" is dragged to the position after "Gamma"
- Then: All sortOrders are recalculated sequentially
- And: Final order is "Beta", "Gamma", "Alpha"

**AC-RO-3: Move block up recalculates sortOrder**
- Given: Siblings "Alpha" (sortOrder 1), "Beta" (sortOrder 2), "Gamma" (sortOrder 3)
- When: "Gamma" is dragged to the position before "Alpha"
- Then: All sortOrders are recalculated sequentially
- And: Final order is "Gamma", "Alpha", "Beta"

**AC-RO-4: Reorder preserves content**
- Given: Block "Beta" with content "Hello World"
- When: "Beta" is reordered to a new position
- Then: "Beta".content is still "Hello World"

**AC-RO-5: Reorder works in node view**
- Given: The user is in a node view with children "A", "B", "C"
- When: "C" is dragged to before "A"
- Then: The children reorder to "C", "A", "B" with recalculated sortOrders

---

## Feature: Edit Mode (Behavioral)

### User Story

As a user, I want to tap on text to start editing and tap away to save, with changes persisted automatically.

### Acceptance Criteria

**AC-EM-1: Tap enters edit mode**
- Given: A block "Alpha" with content "Hello"
- When: The user taps on "Alpha"
- Then: The keyboard appears
- And: The cursor is placed in the text

**AC-EM-2: Content changes are saved on exit**
- Given: The user is editing "Alpha", changes content from "Hello" to "Hello World"
- When: The user taps outside the text area
- Then: The block's content is persisted as "Hello World"
- And: The block's updatedAt timestamp is newer than before

**AC-EM-3: Tapping another block switches edit target**
- Given: The user is editing "Alpha"
- When: The user taps on "Beta"
- Then: "Alpha" is saved and exits edit mode
- And: "Beta" enters edit mode

---

## Feature: Mentioning Blocks (v1 Placeholder)

### User Story

As a user, I see mention controls that indicate future linking capabilities, but they are non-functional in v1.

### Acceptance Criteria

**AC-MN-1: Typing @ inserts character normally**
- Given: The user is editing a block
- When: The user types "@"
- Then: The "@" character is inserted into the content as plain text
- And: No search/picker popover appears

**AC-MN-2: Format bar mention button is disabled**
- Given: Edit mode is active on iOS
- When: Inspecting the format bar (Liquid Glass styled, buttons in `GlassEffectContainer`)
- Then: The Mention (@) button is visible but greyed out / non-interactive

**AC-MN-3: No block linking occurs in v1**
- Given: The user types "@username" in a block
- When: The content is saved
- Then: The text "@username" is stored as plain text
- And: No BlockLink record is created
