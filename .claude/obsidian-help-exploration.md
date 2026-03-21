# Site Exploration: https://help.obsidian.md/

**Boundary:** `https://help.obsidian.md/` (content fetched via `publish-01.obsidian.md` raw markdown API)
**Pages fetched:** 30+
**Max depth reached:** 2

---

## Key Findings

### 1. How Notes Are Created and Organized (Folders, Tags, Bookmarks)

**Note creation:**
- `Cmd+N` creates a new note (plain text Markdown files)
- Notes stored in a "vault" — just a folder on the filesystem
- Can also create from File Explorer or Command Palette
- Obsidian respects OS filename limitations; cross-platform users must ensure compatibility

**Folder organization (File Explorer core plugin):**
- Full folder CRUD — create, rename, move, delete
- Drag-and-drop for moving files between folders
- Sort by file name, modified time, or created time (ascending/descending)
- Auto-reveal option scrolls to the active note in the folder tree
- Bulk selection with Alt+Click / Shift+Click
- Dragging a file into a note creates a link; dragging into a folder copies the file

**Tags:**
- Inline syntax: `#meeting` anywhere in note body
- YAML frontmatter syntax: `tags: [recipe, cooking]`
- **Nested tags** via forward slashes: `#inbox/to-read` — searching `tag:inbox` matches all children
- Tags are case-insensitive for matching, preserve original casing
- Valid characters: letters, numbers, underscores, hyphens, forward slashes
- Must contain at least one non-numerical character (`#1984` invalid, `#y1984` valid)
- Tags View core plugin shows all tags with note counts, supports tree/flat display

**Bookmarks (core plugin):**
- Bookmarkable items: files, folders, graphs, searches, headings, blocks, and links
- Organized into bookmark groups (expandable/collapsible)
- Drag-and-drop reordering, batch bookmarking via multi-select
- Local graphs cannot be bookmarked

---

### 2. How Linking Works (Wikilinks, Backlinks, Unlinked Mentions)

**Two link formats:**
1. **Wikilink** (default): `[[Three laws of motion]]`
2. **Markdown link**: `[Three laws of motion](Three%20laws%20of%20motion.md)`

**Creating links:**
- Type `[[` to get file suggestions
- Select text and type `[[`
- Command palette: "Add internal link"

**Link to headings:**
- Same note: `[[#Heading name]]`
- Another note: `[[Note name#Heading name]]`

**Link to blocks:**
- Syntax: `[[Note name#^block-id]]`
- Example: `[[2023-01-01#^37066d]]`
- Human-readable IDs: `[[2023-01-01#^quote-of-the-day]]`

**Custom display text:**
- Wikilink: `[[Note name|Display text]]` (pipe separator)
- Markdown: `[Display text](Note%20name.md)`

**Backlinks (core plugin):**
- **Linked mentions:** Explicit internal links pointing to active note
- **Unlinked mentions:** Text matches of note name without formal links
- Options: collapse results, show full context, sort order, search filter
- Can appear in sidebar tab or at bottom of note

**Outgoing Links (core plugin):**
- Shows all links in the active note
- Also shows unlinked mentions (text matching note names that aren't linked yet)
- Can create links directly from unlinked mentions
- **Not available on mobile**

**Auto-update:** When renaming a file, Obsidian automatically updates ALL links to that file.

**Restrictions:** Characters `# | ^ : %% [[ ]]` in strings may not function as links.

---

### 3. Block References — Linking to Specific Paragraphs/Lines

**This is a critical feature for Noto's design.**

A "block" in Obsidian is any discrete unit of text — a paragraph, a list item, a table row, a blockquote, a code block. Essentially any chunk separated by blank lines.

**Block ID syntax:** Append `^identifier` at the end of the block text, after a space.

```markdown
The only way to do great work is to love what you do. ^quote-of-the-day
```

**Auto-generated IDs:** Random alphanumeric like `^37066d`. When you type `[[Note#^` and select a block, Obsidian auto-appends a `^random-id` to the target block if it doesn't already have one.

**Manual IDs:** Human-readable like `^quote-of-the-day`.

**Referencing:**
- Link: `[[Note#^block-id]]`
- Embed: `![[Note#^block-id]]`

**Key design implications:**
- Block IDs are stored **IN the note text itself** (appended to paragraphs), NOT in metadata or a separate index
- They persist across edits as long as the `^id` suffix remains
- They are Obsidian-specific, not standard Markdown
- The `^` caret prefix is the marker character
- Block IDs must be unique within a note
- Heading links (`[[Note#Heading]]`) are more portable but less granular

---

### 4. Embeds/Transclusions — Embedding Content Inline

**Core syntax:** Add `!` before any internal link.

| What to embed | Syntax |
|---|---|
| Entire note | `![[Note name]]` |
| Heading section | `![[Note name#Heading]]` |
| Specific block | `![[Note name#^block-id]]` |
| Image (internal) | `![[image.jpg]]` |
| Image with size | `![[image.jpg|640x480]]` or `![[image.jpg|100]]` |
| Image (external) | `![alt|250](https://example.com/image.jpg)` |
| Audio | `![[recording.ogg]]` |
| PDF | `![[Document.pdf]]` |
| PDF specific page | `![[Document.pdf#page=3]]` |
| PDF custom height | `![[Document.pdf#height=400]]` |
| List by block ID | `![[My note#^my-list-id]]` |
| Web page | `<iframe src="URL"></iframe>` |
| YouTube video | `![](https://youtube.com/watch?v=ID)` |
| Search results | Query code blocks |

**Heading embed scope:** Embeds the entire section under that heading until the next heading of same or higher level.

---

### 5. Daily Notes

- Core plugin, creates/opens notes based on current date
- Default naming: `YYYY-MM-DD`
- Custom format via Moment.js tokens: `YYYY/MMMM/YYYY-MMM-DD` creates `2023/January/2023-Jan-01` (auto-creates subfolders)
- Custom save location configurable
- Template file support: designate a template in Daily Notes settings
- **Date property auto-linking:** When a date property (formatted `2023-01-01`) exists in any note, it becomes a clickable link to that day's note in Live Preview

---

### 6. How Search Works

**Access:** `Cmd+Shift+F`

**Basic:**
- Words match independently, quotes for exact phrase
- Boolean: `meeting work` (AND), `meeting OR work` (OR)
- Exclusion: `-work`

**Operators:**

| Operator | Purpose |
|----------|---------|
| `file:` | Search filenames |
| `path:` | Search file paths |
| `content:` | Search note body text |
| `tag:` | Search tags (includes nested) |
| `line:` | All terms on same line |
| `block:` | All terms in same block |
| `section:` | All terms in same section |
| `task:` | Match tasks |
| `task-todo:` | Incomplete tasks |
| `task-done:` | Completed tasks |
| `match-case:` | Case-sensitive |
| `ignore-case:` | Case-insensitive |

**Property search:** `[status:Draft]` bracket notation

**Regex:** `/pattern/` with forward slashes

**Sort:** By filename, modification date, or creation date

**Embedded search:** Can embed query results in notes using code blocks

---

### 7. How the Editor Works

**Three modes:**
1. **Live Preview** (default) — WYSIWYG-like. Markdown renders inline as you type. Cursor position reveals raw Markdown; other areas show rendered output.
2. **Source mode** — Pure Markdown editing, all syntax visible, no rendering.
3. **Reading mode** — Fully rendered view, no editing.

**Key details:**
- Source mode and Live Preview do NOT support PrismJS syntax highlighting (only Reading mode)
- Built on CodeMirror 6
- Comments: `%%hidden text%%` visible only in editing modes
- Highlights: `==text==`
- Footnotes: `[^1]` inline with `[^1]: text` definitions

---

### 8. Properties / Frontmatter (YAML Metadata)

**Adding:** `Cmd+;`, Command Palette, or type `---` at file beginning

**7 property types:** Text, List, Number, Checkbox, Date, Date & time, Tags

**Type enforcement:** Once a property name gets a type anywhere in vault, that type is enforced globally.

**Default properties:** `tags`, `aliases` (alternative note names for link suggestions), `cssclasses`

**Publish properties:** `publish`, `permalink`, `description`, `image`, `cover`

**Limitations:**
- No nested properties
- No bulk editing in UI
- No Markdown in property values (intentional: "properties are meant for small, atomic bits of information")

---

### 9. Moving Content Between Notes

**Note Composer (core plugin)** is the native solution:

**Merge:** Combine one note into another, updating all references.
- `Enter` = append to end, `Shift+Enter` = prepend to start, `Ctrl+Enter` = new note
- "Merging notes adds a note to another and removes the first one"

**Extract/Split:** Select text, extract to a new or existing note.
- By default replaces extracted text with a link to the destination
- Configurable: leave an embed instead, or leave nothing

**Template for extracts:** Variables `{{content}}`, `{{fromTitle}}`, `{{newTitle}}`, `{{date:FORMAT}}`

**No native "move paragraph" or drag-paragraph-between-notes feature.** Note Composer (select + extract/merge) is the closest thing.

---

### 10. Graph View

- Global graph: all notes as nodes, links as edges
- Local graph: connections to active note, adjustable depth
- **Filters:** search, tag/attachment visibility, orphan display
- **Groups:** color-code by search criteria
- **Display:** arrows, text, node size, link appearance, animations
- **Forces:** center compactness, repulsion, tension, spacing
- **Time-lapse:** chronological animation by creation date

---

### 11. Templates

**Core Templates plugin:**
- Designate template folder in Settings
- Variables: `{{title}}`, `{{date}}`, `{{time}}`
- Custom formats: `{{date:YYYY-MM-DD}}` (Moment.js tokens)
- Template properties merge with existing note properties

**Templater** is a community plugin (not in official docs) with JavaScript execution, conditionals, cursor placement, etc.

**Unique Note Creator:** Zettelkasten-style timestamp naming (`202401010945`), optional template, auto-increments on collision.

---

### 12. Mobile Features and Limitations

- Available on iOS (App Store) and Android (Play Store/APK)
- Sync: iCloud or Obsidian Sync recommended for iOS; Google Drive/Sync/Syncthing for Android
- **Outgoing Links plugin NOT available on mobile**
- Local graph accessed differently: "More options" -> "Open local graph"
- Do NOT mix sync services on the same vault

---

### 13. Sync and Publish

**Obsidian Sync (paid):**
- All platforms, off-site remote vault, selective sync
- Version history, end-to-end encryption, multi-user collaboration
- CLI syncing, regional servers
- Not compatible with Apple Lockdown Mode

**Obsidian Publish (paid):**
- Publish notes as website at `publish.obsidian.md/your-site` or custom domain
- Multi-site, team collaboration, design customization, SEO, analytics
- help.obsidian.md itself runs on Publish

---

### 14. Block ID / Paragraph-Level Referencing (Summary)

See sections 3 and 4 for full detail. Key takeaway:

**Obsidian stores block IDs inline in the text** — `^my-id` appended to the end of a paragraph/block. This is a text-level convention, not a database-level feature. The ID lives in the Markdown source. When you reference `[[Note#^my-id]]` or embed `![[Note#^my-id]]`, Obsidian locates that `^my-id` suffix in the target note's text. If the user deletes or moves the `^my-id` text, the reference breaks.

---

### 15. Canvas

- `.canvas` files (open JSON Canvas format)
- Card types: text, notes, media, web pages, folder contents
- Connections: lines between cards with colors and labels
- Groups for organizing related cards
- Navigation: Space+drag to pan, Space+scroll to zoom
- Text cards convertible to files (enables backlinking)
- Infinite 2D space

---

## Additional Features

**Callouts:** `> [!type] Title` — 13 built-in types. Foldable with `+`/`-`. Nestable. Custom via CSS.

**Outline plugin:** Heading TOC, click to jump, drag to rearrange sections.

**Bases plugin (newer):** Database-like views on notes using their properties.

**29 core plugins total** (Audio recorder, Backlinks, Bases, Bookmarks, Canvas, Command palette, Daily notes, File explorer, File recovery, Format converter, Graph view, Note composer, Outgoing links, Outline, Page preview, Properties view, Publish, Quick switcher, Random note, Search, Slash commands, Slides, Sync, Tags view, Templates, Unique note creator, Web viewer, Word count, Workspaces).
