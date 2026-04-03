# Feature: Block-Based Markdown Editor

## User Story

As a user, I want the markdown editor to render every line correctly regardless of edits — no formatting bleeding between lines, no cursor glitches, no visual artifacts — so that editing feels solid and predictable.

## User Flow

No user-facing flow changes. The editor looks and behaves identically to today's version. The difference is architectural: each line is its own isolated view instead of one shared text storage.

Editing interactions that must work exactly as before:
1. Type text → appears with correct formatting for the block type
2. Press Enter on a list item → new item of same type appears
3. Press Enter on empty list item → item removed, cursor on plain paragraph
4. Backspace at start of block → merge content into previous block
5. Tap checkbox → toggle checked state
6. Toolbar: indent/outdent/todo toggle
7. Navigate away and back → content persists as markdown on disk

## Success Criteria

- [ ] SC1: Parse markdown → blocks (headings, paragraphs, todos, bullets, ordered lists, frontmatter)
- [ ] SC2: Serialize blocks → markdown (round-trip: parse then serialize = original markdown)
- [ ] SC3: Each block renders with correct styling (heading font sizes, bullet indent, todo checkbox + strikethrough)
- [ ] SC4: Inline formatting works within blocks (bold, italic, code)
- [ ] SC5: Enter creates new block (auto-continue for list types)
- [ ] SC6: Enter on empty list block → converts to paragraph
- [ ] SC7: Backspace at start of block → merges with previous block
- [ ] SC8: Indent/outdent changes nesting level
- [ ] SC9: Toolbar todo toggle converts block type
- [ ] SC10: Checkbox tap toggles checked state + strikethrough
- [ ] SC11: Editing one block NEVER affects formatting of other blocks (the core bug fix)
- [ ] SC12: Cursor height always matches the block's font size (no tiny cursor)
- [ ] SC13: Frontmatter hidden (not editable by user)
- [ ] SC14: Note persists to disk as valid markdown
- [ ] SC15: macOS editor works with same block model

## Tests

_To be populated during Step 2._

## Implementation Details

### Keyboard focus handoff
- Backspace-at-start must transfer first responder to the previous visible block before deleting the current table row; otherwise UIKit briefly drops the keyboard and reopens it.

### Architecture

```
┌─────────────────────────────────────────────────┐
│  BlockEditorView (SwiftUI)                      │
│  ScrollView of BlockRowView instances           │
├─────────────────────────────────────────────────┤
│  BlockDocument (@Observable)                    │
│  [Block] array + split/merge/insert/delete      │
├─────────────────────────────────────────────────┤
│  MarkdownParser    MarkdownSerializer           │
│  String → [Block]   [Block] → String            │
├─────────────────────────────────────────────────┤
│  Block (enum)                                   │
│  .heading(level, text)                          │
│  .paragraph(text)                               │
│  .todo(checked, indent, text)                   │
│  .bullet(indent, text)                          │
│  .orderedList(number, indent, text)             │
└─────────────────────────────────────────────────┘
```

### Files to create
- `Noto/Editor/Block.swift` — Block enum + BlockDocument
- `Noto/Editor/MarkdownParser.swift` — parse markdown → [Block]
- `Noto/Editor/MarkdownSerializer.swift` — serialize [Block] → markdown
- `Noto/Editor/BlockEditorView.swift` — SwiftUI editor view
- `Noto/Editor/BlockRowView.swift` — per-block row view (text field + decorations)

### Files to delete (after migration complete)
- `Noto/Editor/MarkdownTextStorage.swift`
- `Noto/Editor/MarkdownFormatter.swift`
- `Noto/Editor/MarkdownLayoutManager.swift`
- `Noto/Editor/MarkdownEditorTheme.swift`
- `Noto/Editor/MarkdownEditingCommands.swift`
- `Noto/Editor/TodoMarkdown.swift`

### Key design decisions
- **Block granularity:** One block per paragraph/list item. A paragraph is text between `\n`s. Each bullet, todo, ordered list item, and heading is one block. Multi-line wrapped text within a block is still one block.
- **Prefix is visible and editable.** The user sees `## Section Title`, `- [ ] Task`, `- Bullet`, `1. Item` in the text field. Deleting the prefix (e.g., backspacing `## ` from a heading) converts the block to a paragraph. Typing a prefix (e.g., `## ` at the start of a paragraph) converts it to a heading. The block type is derived from the text content, not stored separately.
- **Block type is derived, not stored.** The block stores raw text (e.g., `"## Section Title"`). The type (heading, todo, bullet, etc.) is computed from the prefix. This means the text field IS the source of truth — no sync between "block type" and "block text" needed.
- Block identity: each block has a stable UUID for SwiftUI diffing
- Focus management: one block is focused at a time, tracked by BlockDocument
- Inline formatting: applied as attributed string styling within the text field (bold, italic, code)
- Frontmatter: parsed as a special hidden block, serialized back verbatim

## Bugs

- Backspace-deleting a block could flash the keyboard because the active row was removed before focus moved to the previous block.
