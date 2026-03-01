# User Interactions

Behavioral specification for all user interactions across the home screen and node screen. Covers block creation, deletion, reorganization, and mentioning.

**Figma source:** [Home view](https://www.figma.com/design/9nh3TpDEoZx8Pt8hVUrJgV/Noto?node-id=23-707), [Node view](https://www.figma.com/design/9nh3TpDEoZx8Pt8hVUrJgV/Noto?node-id=24-705)

---

## Edit Mode

### Entering Edit Mode

- **Tap** (iOS) or **click** (macOS) on any block's text enters edit mode
- Keyboard appears, cursor is placed at the tap location
- Format bar appears above the keyboard (iOS only)

### Exiting Edit Mode

- Tap outside text or on another block
- On save: block's `content` is updated, `updatedAt` set to current time

### Format Bar (iOS)

Three buttons above the keyboard, styled with Liquid Glass (`.glassEffect(.regular.interactive())`):

1. **Indent (→)** — see [Reorganizing Blocks](#reorganizing-blocks)
2. **Outdent (←)** — see [Reorganizing Blocks](#reorganizing-blocks)
3. **Mention (@)** — see [Mentioning Blocks](#mentioning-blocks)

Format bar buttons should be wrapped in a `GlassEffectContainer` for proper blending between adjacent glass elements.

### macOS Equivalents

- Indent: Tab key
- Outdent: Shift+Tab
- Mention: Right-click context menu item

---

## Creating Blocks

Block creation should feel exactly like pressing Return in a text editor — no special buttons or gestures required.

### Return Key (in edit mode)

- Creates a new **sibling** block directly below the current one
- New block properties:
  - Same `parentId` as the current block
  - Same `depth` as the current block
  - `sortOrder` = midpoint between current block and next sibling (or current + 1 if last)
  - Empty `content`
- Cursor moves to the new block in edit mode
- **Special case:** If cursor is at the beginning of a non-empty block, a new empty block is inserted **above** instead

### Tap on Empty Space

- **Empty screen (no blocks):** Tapping anywhere creates the first root block (`parentId = nil`, `depth = 0`, `sortOrder = 1.0`) and enters edit mode
- **Below the last block:** Tapping empty space below the last visible block creates a new block at the end and enters edit mode

### Creating Children in Node View

- New blocks created in the node view get:
  - `parentId = currentNode.id`
  - `depth = currentNode.depth + 1`
  - `sortOrder` appended at the end of the sibling list
- Tapping empty space below the last child also creates a new child block

---

## Deleting Blocks

Deletion feels like deleting an empty line in a text editor — Backspace on an empty line removes it.

### Backspace on Empty Block

- Deletes the empty block from the model context
- Cursor moves to the **end of the previous block**
- **Cascade:** If the deleted block had children, all descendants are also deleted (`isArchived = true`, cascading to all descendants)

### Non-Empty Blocks

- Backspace on a block with content is a normal text editing operation (deletes the character before the cursor)
- The delete-on-backspace operation is a **no-op** when the block has content — it never deletes a block that still has text

---

## Reorganizing Blocks

### Indent (Make Child of Previous Sibling)

Triggered by: format bar Indent button (iOS) or Tab key (macOS)

- Sets `parentId` to the previous sibling's `id`
- Increments `depth` by 1
- All descendants also have their `depth` incremented (per the depth recalculation algorithm in the data model PRD)
- **Disabled** if the block is the first sibling (no previous sibling to indent under)

### Outdent (Make Sibling of Parent)

Triggered by: format bar Outdent button (iOS) or Shift+Tab (macOS)

- Sets `parentId` to the grandparent's `id` (or `nil` if parent is root)
- Block is inserted **after the old parent** in the grandparent's children
- Decrements `depth` by 1
- All descendants also have their `depth` decremented
- **Disabled** if the block is already at root level (`depth = 0`)

### Reorder (Long Press + Drag)

Triggered by: long press on any block's text (both platforms)

- The block lifts up and can be dragged to a new position among its **siblings**
- On drop: block's `sortOrder` is recalculated using fractional indexing (midpoint between the new neighbors' `sortOrder` values)
- Block content is unchanged after reorder
- Works from both the home screen and within node views

---

## Mentioning Blocks

**v1 status: Placeholder only — all entry points are visually present but functionally disabled.**

### Entry Points (all disabled in v1)

1. **Typing `@` inline** — would trigger a block search/picker popover to insert a `BlockLink` reference. In v1, typing `@` just inserts the character normally.
2. **Format bar @ button (iOS)** — greyed out in v1
3. **Right-click context menu item (macOS)** — greyed out in v1

### Intended Behavior (post-v1)

All three entry points insert the `@` character and open a search/picker popover for selecting a block to link via `BlockLink`.

---

## Interaction Summary

| Gesture | Context | Action |
|---|---|---|
| Tap on block text | Any screen | Enter edit mode for that block |
| Tap empty space | Empty screen | Create first block and enter edit mode |
| Tap empty space below last block | Any screen | Create new block at end and enter edit mode |
| Tap outside text | Edit mode | Exit edit mode, save changes |
| Return key | Edit mode | Create new sibling block below |
| Backspace on empty block | Edit mode | Delete block, cursor to previous |
| Double tap on block text | Any screen | Push node view onto NavigationStack |
| Long press on block text | Any screen | Enter reorder mode (drag to reposition) |
| Indent button / Tab | Edit mode | Indent under previous sibling |
| Outdent button / Shift+Tab | Edit mode | Outdent to parent's level |

---

## Platform Considerations

| Aspect | iOS | macOS |
|---|---|---|
| Edit mode trigger | Tap | Click |
| Indent / Outdent | Format bar above keyboard | Tab / Shift+Tab |
| Mention | Format bar above keyboard | Right-click context menu |
| Reordering | Long press + drag | Long press + drag |
| Delete | Backspace on empty block | Backspace on empty block |

---

## State Management

| State | Type | Scope |
|---|---|---|
| Editing block | `@State editingBlockId: UUID?` | Per screen |
| Edit content | `@State` tracking current text | Per screen |
| Syncing guard | `isSyncing: Bool` flag to prevent re-entrant sync | Per screen |
