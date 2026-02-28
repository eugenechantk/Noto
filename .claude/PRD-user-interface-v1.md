# User interface

The user interface should look like a normal note taking app, similar to Apple notes. The key design principle: it should not feel like you are typing out a bullet list, even though the underlying data model is an outliner (blocks with parent-child relationships).

---

## Home screen

The home screen should be the root, showing all the blocks with no parent nodes (`parentId = nil`), ordered by `sortOrder` ascending. Each root block is displayed as a line of text (its `content`), with no bullet points or indentation — just clean text lines, like Apple Notes. If a root block has children, there is no visual indicator on the home screen; children are only revealed in the node view.

Block creation, editing, and deletion should feel exactly like typing in a normal note-taking app — no special buttons or gestures required.

**Creating a new block:**
- Pressing Return at the end of any existing block creates a new sibling block below it
- If the screen is completely empty (no blocks at all), tapping anywhere on the empty space creates the first block and enters edit mode
- New blocks get `sortOrder` appended at the end of their sibling list

**Deleting a block:**
- Backspace on an empty block deletes it and moves the cursor to the end of the previous block — just like deleting an empty line in a text editor
- If the deleted block had children, they are also deleted (`isArchived = true`, cascading to all descendants)

---

## Edit mode

Tapping on any text enters edit mode. Keyboard shows up. The editing experience should feel like a continuous text document — the user should not be aware they are editing discrete "blocks."

On save (triggered by tapping outside the text or on another block), the block's `content` is updated and `updatedAt` is set to the current time.

**Return key:** Creates a new sibling block directly below the current one (same `parentId`, same `depth`, `sortOrder` midpoint between current and next sibling). Cursor moves to the new block in edit mode. If cursor is at the beginning of a non-empty block, a new empty block is inserted above instead.

**Backspace on empty block:** Deletes the empty block and moves cursor to the end of the previous sibling — just like deleting an empty line in a text editor.

There should be a format bar on top of the keyboard as well (iOS only — macOS uses keyboard shortcuts and context menu instead; see platform considerations). The format bar has three options now:

1. **Indent (→):** Makes the current block a child of its previous sibling. Updates `parentId` to previous sibling's `id`, `depth += 1`. All descendants also have their `depth` incremented (per the depth recalculation algorithm in the data model PRD). Disabled if the block is the first sibling (no previous sibling to indent under). On macOS: Tab key.

2. **Outdent (←):** Makes the current block a sibling of its current parent. Updates `parentId` to grandparent's `id` (or `nil` if parent is root), block is inserted after the old parent in the grandparent's children, `depth -= 1`. All descendants also have their `depth` decremented. Disabled if the block is already at root level. On macOS: Shift+Tab.

3. **Mention (@):** Typing `@` inline triggers a block search/picker popover to insert a `BlockLink` reference. The format bar button and macOS right-click context menu item insert the `@` character and open the same popover. Placeholder for v1 — all three entry points are visually present but functionally disabled (typing `@` just inserts the character normally, format bar button greyed out, context menu item greyed out).

---

## Node view

Double-tapping any block's text should stack another screen on top (push onto NavigationStack). That is the node view. Double-tapping works from the home screen or from within another node view, creating a drill-down pattern: Home → Node A → Node A's child → ...

Long pressing any block's text enters reorder mode — the block lifts up and can be dragged to a new position among its siblings. On drop, the block's `sortOrder` is recalculated using fractional indexing (midpoint between the new neighbors' `sortOrder` values).

The node view still looks the same as Apple Notes, but instead showing the text of the node selected as a heading (large title style, ~22pt bold), and the first level children as main text (~17pt body). The children of the node would not be shown as a bullet, so to maintain a regular note look and feel; all the other descendent blocks from the children (e.g. grandchildren, great-grandchildren, etc.) will be shown as bullets and sub-bullets, with appropriate indentation.

**Indentation formula:** `indent level = block.depth - currentNode.depth - 1`, where indent level 0 means no bullet (first-level children), indent level 1 means first bullet level (grandchildren), indent level 2 means sub-bullets (great-grandchildren), etc. Indent roughly ~20pt per level.

**Bullet styles by indent level:**
- Level 1 (grandchildren): filled circle (•)
- Level 2 (great-grandchildren): hollow circle (◦)
- Level 3+: dash (–)

**Creating and deleting blocks** work the same as on the home screen — Return to create, Backspace on empty to delete. Tapping empty space below the last child also creates a new child block. New child blocks get `parentId = currentNode.id` and `depth = currentNode.depth + 1`.

On top of the node view is a menu bar. Left of the menu bar is a back button that goes back to the previous layer of the stack. Right of the menu bar is an expand all toggle button:
- **Collapsed (default):** Only first-level children shown as plain text, with their immediate descendants visible as described above
- **Expanded:** All descendants of the current node are shown. First-level children remain as plain text (no bullets). All deeper descendants shown with bullets at their respective indent levels. The button text/icon toggles between "Expand All" and "Collapse"

In the node view, tapping on any text will still get you into edit mode, same as described above.

---

## Interaction summary

| Gesture | Context | Action |
|---------|---------|--------|
| Tap on block text | Any screen | Enter edit mode for that block |
| Tap empty space | Empty screen | Create first block and enter edit mode |
| Tap empty space below last block | Any screen | Create new block at end and enter edit mode |
| Tap outside text | Edit mode | Exit edit mode, save changes |
| Return key | Edit mode | Create new sibling block below |
| Backspace on empty block | Edit mode | Delete block, cursor to previous |
| Double tap on block text | Any screen | Push node view onto NavigationStack |
| Long press on block text | Any screen | Enter reorder mode (drag to reposition) |
| Indent button | Edit mode | Indent under previous sibling |
| Outdent button | Edit mode | Outdent to parent's level |

---

## Platform considerations (iOS & macOS)

The app is a universal Apple app. Both platforms share the same SwiftUI views with minor adaptations:

| Aspect | iOS | macOS |
|--------|-----|-------|
| Edit mode trigger | Tap | Click |
| Node view trigger | Double tap | Double-click |
| Indent / Outdent | Format bar above keyboard | Tab / Shift+Tab |
| Mention | Format bar above keyboard | Right-click context menu |
| Reordering | Long press + drag | Long press + drag |
| Delete | Backspace on empty block | Backspace on empty block |

---

## State management

- **Current screen:** Managed by NavigationStack path
- **Edit mode:** `@State` property tracking which block is being edited (`editingBlockId: UUID?`)
- **Expand all toggle:** `@State` boolean per node view (`isExpanded: Bool = false`)
- **Block data:** Fetched via SwiftData `@Query`:
  - Home screen: `parentId == nil`, sorted by `sortOrder`
  - Node view (collapsed): `parentId == currentNodeId`, sorted by `sortOrder`
  - Node view (expanded): all descendants of `currentNodeId`, sorted by `depth` then `sortOrder`

---

## Required Tests

Unit tests validating the UI operations against the data layer. Tests operate directly on `ModelContext` and `Block` model, simulating the actions the views perform.

### Block Creation Tests
- `testCreateFirstRootBlock` — Creating a block when no blocks exist inserts a root block with `parent = nil`, `depth = 0`, empty content, and `sortOrder = 1.0`
- `testCreateBlockAfterExisting` — Pressing Return after an existing block creates a new sibling below it with `sortOrder` between the current block and the next sibling (or +1 if last)
- `testCreateBlockBetweenSiblings` — New block inserted between two siblings gets `sortOrder` as the midpoint of its neighbors
- `testCreateChildInNodeView` — Creating a child in node view sets `parentId = currentNode.id` and `depth = currentNode.depth + 1`

### Block Deletion Tests
- `testDeleteEmptyBlock` — Deleting an empty block removes it from the model context
- `testDeleteBlockCascadesToChildren` — Deleting a block with children also deletes all descendants
- `testDeleteNonEmptyBlockIgnored` — The delete-on-backspace operation is a no-op when the block has content

### Block Editing Tests
- `testEditBlockContent` — Updating a block's `content` persists correctly
- `testEditBlockUpdatesTimestamp` — Updating content sets `updatedAt` to a newer date

### Reorder Tests
- `testReorderMovesBlockDown` — Moving a block from index 0 to index 2 recalculates all sortOrders sequentially
- `testReorderMovesBlockUp` — Moving a block from index 2 to index 0 recalculates all sortOrders sequentially
- `testReorderPreservesContent` — Block content is unchanged after reorder

### Reorganize (Indent / Outdent) Tests
- `testIndentMakesChildOfPreviousSibling` — Indenting a block sets its `parent` to the previous sibling and increments `depth`
- `testIndentFirstSiblingFails` — Indenting the first sibling (no previous sibling) returns `false` and makes no changes
- `testOutdentMakesSiblingOfParent` — Outdenting a block sets its `parent` to the grandparent (or `nil`) and decrements `depth`
- `testOutdentRootBlockFails` — Outdenting a root block returns `false` and makes no changes
- `testIndentUpdatesDescendantDepths` — Indenting a block with children increments depth for all descendants

### Node View Flattening Tests
- `testFlattenCollapsedShowsChildrenAndGrandchildren` — In collapsed mode, the flattened list includes direct children (indent 0) and grandchildren (indent 1), but not great-grandchildren
- `testFlattenExpandedShowsAllDescendants` — In expanded mode, all descendants appear with correct indent levels
- `testFlattenIndentLevelFormula` — Each block's indent level equals `block.depth - currentNode.depth - 1`
- `testFlattenDirectChildrenHaveIndentZero` — Direct children always have indent level 0 (no bullet)
- `testFlattenPreservesSortOrder` — Blocks within the same parent appear in `sortOrder` ascending order

---

## Not in scope for v1 UI

These features exist in the data model but will not have UI in v1:
- Search (keyword + semantic)
- Tags
- Metadata fields
- Mention/linking (button is placeholder only)
- Templates
- Sync
- Today notes / Inbox
