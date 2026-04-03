# Personal Notetaking Universal Apple App

This is a universal apple application for my markdown based note taking app

## Current editor architecture

The live editor path is a markdown-native block editor on iOS. At the app level, `NotoApp` creates a vault-scoped `MarkdownNoteStore` plus a `VaultFileWatcher`, and `NoteEditorScreen` loads one note's full markdown content into a single `String` state called `content`. The screen passes that binding into `BlockEditorView`, and debounces save and rename operations back through `MarkdownNoteStore`. The store is the persistence boundary: it reads and writes `.md` files, manages YAML frontmatter timestamps, derives titles from markdown content, and renames files to match note titles when appropriate.

### Active runtime path

The current live editor is `BlockEditorView`, not the older `MarkdownEditorView` TextKit path. `BlockEditorView` is a `UIViewControllerRepresentable` wrapper around `BlockEditorViewController`. The controller owns a `BlockDocument`, which is an array of `Block` values, one block per markdown line. Each `Block` stores the full markdown text for that line, including prefixes such as `# `, `- `, or `- [ ] `. Structure is inferred from text; `BlockType.detect(from:)` derives whether a row is a paragraph, heading, todo, bullet, ordered list, or frontmatter block. That means markdown stays the source of truth, and semantics come from parsing prefixes rather than from a separate rich-text model.

Each visible row in the editor is a `BlockCell` with its own `UITextView`. The controller renders the document through a `UITableView`, tracks the focused row and cursor offset, and handles structural editing operations at the document layer. Pressing Return calls `BlockDocument.split(blockIndex:atOffset:)`, which splits the current markdown line into two blocks and auto-continues list prefixes when needed. Pressing Backspace at the start of a row calls `mergeWithPrevious(blockIndex:)`, which joins the current block into the previous block. Tapping a todo checkbox or the keyboard toolbar todo button mutates the underlying markdown using `TodoMarkdown` helpers and then re-renders the affected row.

### Load, edit, and save flow

The load path is:

1. Disk file -> `MarkdownNoteStore.readContent(of:)`
2. Raw markdown string -> `NoteEditorScreen.content`
3. `BlockEditorViewController.loadMarkdown(_:)`
4. `BlockParser.parse(...)` -> `[Block]`
5. `[Block]` stored in `BlockDocument`

Frontmatter is preserved as a single hidden `frontmatter` block, while the remaining note body is split by newline into one block per line. The editor never stores a separate rich document format.

While editing, each block cell updates only its own markdown text. The controller then serializes the full `BlockDocument` back into a single markdown string using `BlockSerializer.serialize(...)` and pushes it through the SwiftUI binding. `NoteEditorScreen` debounces persistence: a short task writes updated content through `saveContent`, and a longer task renames the file through `renameFileIfNeeded`. On disappear, it performs a final save and rename pass.

The save path is:

1. Block row edit -> update one `Block.text`
2. `BlockDocument` -> `BlockSerializer.serialize(...)`
3. Serialized markdown -> SwiftUI binding
4. `MarkdownNoteStore.saveContent(...)`
5. Store updates frontmatter timestamp and writes the `.md` file

### Rendering and formatting

Rendering is separate from the document model. `BlockType.renderSpec(for:)` converts semantic block type into a declarative `BlockRenderSpec`, which describes typography, spacing, indentation, prefix visibility, checkbox state, and content styling. `BlockRenderer.render(...)` then converts the block's raw markdown into an attributed string for display.

This is how the editor can:

- hide or dim heading prefixes while preserving the underlying `# `
- replace todo markdown prefixes with a checkbox accessory
- render focused bullet and ordered-list markers without exposing raw markdown prefixes
- apply checked-state strikethrough and dimming for completed todos
- apply inline markdown styling for bold, italic, and code spans

The important separation is:

- document structure comes from markdown prefixes in `Block.text`
- block-level presentation comes from `BlockRenderSpec`
- inline markdown formatting is applied after block styling in the renderer

During typing, the editor avoids fully restyling the row on every keystroke. Instead, it updates the block text immediately and mainly re-applies focused or unfocused styling on configuration and focus transitions. This keeps keyboard behavior and row focus stable.

### Older editor still in tree

There is also an older `MarkdownEditorView` architecture still in the repo. That version uses a single `UITextView` backed by `MarkdownTextStorage`, `MarkdownFormatter`, and `MarkdownLayoutManager`. Architecturally, that editor is a single-buffer text editor with markdown-aware attributed rendering layered on top. The current live block editor is different: it is row-structured first, markdown serialization second.

## Feature set (running)

- node-based note-taking that doesn't feel like you are typing out a bullet list
  - node-based because it can accommodate very small, random thoughts
- semantic + keyword search on any snippet of text
- a way to dump ideas in, and process later (e.g. Today notes/Inbox)
  - between today notes and inbox, today notes is better for me, because i associate random thoughts with the day i thought of it + i can keep my journal there as well
- template, or auto-fill a node based on a template
  - e.g. for each day's journal, have a few questions as template, so that I don't have to find the questions and paste them in again every day
  - the template is determined by a higher level of categorization (e.g. tags)
- mention any snippet of text inline + view where each snippet of text is mentioned + linked editing
- markdown editor + image + url
- pull highlights and full text from readwise
- ai chat with all my notes
- quick time-to-first-keystroke and load time
- offline edit
- offline search
- sync across devices
- metadata & metadata templates
  - e.g. for every node, it should have created time; for notes, it should have status (e.g. seeding, growing, blossomed, etc.)
  - the metadata fields should also be a template, based on a higher level of categorization (e.g. tags)
- tags
  - i am not sure about tags; because my belief is that, if search is so great, there is no need for tagging or any form of categorization
  - but tags might be a good categorization tool for applying different templates or presets
- the editor should feel good for both writing small thoughts, and a large body of text
  - small thoughts: 1 sentence, maybe with some bullet points
  - large body of text: podcast scripts
  - i don't need to think about how to format either, it just looks good for both

## Feature brainstorm

### 1. Outline-based note-taking

This note-taking app should be an outliner-based note taking. Here are the requirements for this outliner-based note taking system

- Each entry is a block, represented as a bullet point
- Blocks can be infinitely nested through identation.
- Each block is individually addressable and can be linked/referenced elsewhere
- Each block can attach metadata on it (e.g. created at, tags, etc.)

As for the interface for this outline-based note-taking approach, here are the requirements

- Each block itself can be selected as the main view, with all its descendent blocks shown in the view
- the child of the main block view would not be shown as a bullet, so to maintain a regular note look and feel; all the other descendent blocks from the child (e.g. grandchildren, great-grandchildren, etc.) will be shown as bullets and sub-bullets, with appropropriate identation
- Clicking on any block make that block the main view, and display its descendents accordingly

### Markdown editor + image + URL

### 3. Semantic + keyword search

Sometimes I know exactly the words in the block to search for it.
Sometimes I know the synonyms or similar words in the block to seach for it
Sometimes I only know the meaning around that block to search for the block

An intelligent search should be able to surface blocks for the three situations above and rank them intelligent that matches the most to the search query.

An intelligent search should be able to understand semantics so it can "search by meaning", but also have flexibilty for hard filters, like exact word matching.

An intelligent search does not need me to switch between semantic and keyword search. It should intelligently rerank blocks that is semantically similar and/or keyword matched so that the ranking reflects how closely the blocks answer/match with my search query.

This search should work offline as well.

This also serves as the backbone for AI chat, which requires some grounding from the blocks I wrote.

### Today notes / Inbox / An easy way to dump ideas

The today notes follow the same block primitive as the whole entire app. The block structure of the today notes feature would be like:
|-Today notes
|--[Year e.g. 2026]
|---[Month e.g. Jan 2026]
|----[Week e.g. Week 1 (1/1 - 7/1)]
|-----[Day e.g. 1/1/2026]

The block data model already supports scaffolding of the year -> month -> week -> day
But this feature needs a way to automatically add blocks when a new day/week/month/year starts
I may also add those new day/week/month/year manually. So the auto-adding function needs to check if the new day/week/month/year is already added

This automatic adding of block should become a new primitive, not just suitable for this today notes feature, but also for other features like AI editing
Therefore, this automatic adding block primitive should have a robust interface that other features can reuse

### Templates & auto-fill

### Bidirectional linking and editing

When you mentioned a block, the original block displays the mentioned block as a link to the mentioned block. The mentioned block gains a "linked reference" to the block that mentioned it.

I am also able to edit the mentioned text, and reflect the changes to the mentioned block

### Readwise integration

### AI chat with notes

### Quick load time & time-to-first-keystroke

### Offline edit

### Offline search

### Metadata & metadata templates

### Tags

### Flexible editor for small thoughts and large text
