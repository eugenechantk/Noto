# Outline Editor — User Interactions

How the user interacts with the outline edit view, and what happens to Blocks at each step.

## The Edit View

Each edit view is a "zoom in" on a specific block (the **selected node**). The view shows:

- **Title** (line 0): The selected node's content
- **Text** (lines 1+): The selected node's descendants

The app opens with the root node as the selected node. Because the root node has empty content, the starting page has no visible title.

### Collapsed vs Expanded

- **Collapsed** (default): Title + direct children only
- **Expanded**: Title + all descendants at all depth levels, indented by their depth relative to the selected node

## Interactions

### Typing on the Title (line 0)

| Action | Result |
|---|---|
| Type text | Updates the selected node's `content` |
| Press Enter | Creates a new **child** of the selected node, inserted at the **top** of children (lowest sortOrder) |

### Typing on Text Lines (lines 1+)

| Action | Result |
|---|---|
| Type text | Updates that block's `content` |
| Press Enter | Creates a new **sibling** of the current line (same parent, same depth), inserted after the current line using fractional sortOrder |
| Delete all text on a line | Block's `content` becomes `""` — the block still exists. Blocks can have empty content. This is normal when rewriting a sentence. |
| Press Backspace on an already-empty line | **Now** the block (and its descendants) are deleted. This is the only way to delete a block. |

**Important**: Deleting text content and deleting a block are two separate actions. A user may clear a line to rewrite it — that doesn't destroy the block or its children. Only pressing Backspace when the line is already blank triggers block deletion.

### Indent (Tab / toolbar button)

| Context | Result |
|---|---|
| On a text line with a previous sibling | Block is reparented to the previous sibling (becomes its last child). Depth increases by 1. All descendants also increase depth. |
| On a text line with no previous sibling (first child) | **No-op** — cannot indent without a previous sibling to become parent of |
| On the title (line 0) | **No-op** — cannot indent the selected node |

### Outdent (Shift+Tab / toolbar button)

| Context | Result |
|---|---|
| On a grandchild or deeper | Block is reparented to its grandparent (becomes sibling of its current parent). Placed after its old parent in sortOrder. Depth decreases by 1. All descendants also decrease depth. |
| On a direct child of the selected node | **No-op** — cannot outdent past the selected node's child level |
| On the title (line 0) | **No-op** — cannot outdent the selected node |

### Delete

Deletion is a two-step process: first the content is cleared, then the block itself.

| Context | Result |
|---|---|
| Backspace while line has content | Normal text deletion — removes characters. Block still exists. |
| Backspace on an already-empty line | Block deleted from SwiftData. Cascade delete removes all its descendants. |
| Backspace on an empty title (line 0) | **No-op** — cannot delete the block you are currently viewing, even if its content is empty |

### Move / Reorder (long-press drag)

| Context | Result |
|---|---|
| Drag a text line to a new position | Block's sortOrder updated. All siblings get sequential sortOrders reassigned. Parent relationship preserved. |
| Drag the title (line 0) | **No-op** — cannot reorder the selected node |

### Double-Tap / Drill Down

| Context | Result |
|---|---|
| Double-tap a text line | Navigate into that block — it becomes the new selected node. A new edit view opens with that block as the title. |

## States

### Entry List

The editor maintains a flat list of `BlockEntry` objects:

```
entries[0] = { block: selectedNode, indentLevel: 0 }   ← always the title
entries[1] = { block: child1,       indentLevel: 0 }   ← direct child
entries[2] = { block: grandchild1,  indentLevel: 1 }   ← only visible when expanded
entries[3] = { block: child2,       indentLevel: 0 }   ← direct child
```

- `indentLevel` is relative to the selected node (direct children = 0, grandchildren = 1, etc.)
- The list is rebuilt via `reload()` whenever structure changes (indent, outdent, insert, delete, move)
- Content edits do NOT trigger a reload — they mutate the block in place

### Block Properties Affected by Each Operation

| Operation | content | parent | depth | sortOrder | children |
|---|---|---|---|---|---|
| Type text | changed | — | — | — | — |
| Insert (Enter) | "" (empty) | set to appropriate parent | set to match siblings | fractional between neighbors | — |
| Delete | — | — | — | — | cascade deleted |
| Indent | — | changed to prev sibling | +1 (and descendants) | set to last child of new parent | — |
| Outdent | — | changed to grandparent | -1 (and descendants) | placed after old parent | — |
| Move | — | preserved | preserved | reassigned sequentially | — |

## Edge Cases

### Empty selected node (app startup)

The root node has empty content. The title area shows nothing. The user can type on the title to name it, or press Enter to create the first child block.

### Single child

- Indent: no-op (no previous sibling)
- Outdent: no-op (already direct child of selected node)
- Delete: removes it, leaving just the title
- Insert after it: creates a sibling (second child of selected node)

### Deep nesting (5+ levels)

- Indent/outdent at any level works correctly
- Depth changes cascade to all descendants
- Only visible when expanded

### Collapsed mode with structure changes

When a block is indented in collapsed mode and becomes a grandchild (no longer a direct child), it disappears from view. The editor switches to expanded mode so the user can see where it went.

### Fractional sort order

New blocks are inserted with a sortOrder halfway between their neighbors. This avoids rewriting sortOrders for all siblings on every insert. Over time, sortOrders may become very close together (e.g., 1.5, 1.25, 1.125...) but this is fine for Double precision.
