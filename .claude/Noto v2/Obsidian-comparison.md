# Obsidian vs. Noto v2 — Feature Comparison & Feasibility Analysis

Can Noto v2's proposed features be built on top of Obsidian (as plugins), or does building a standalone app make sense?

---

## Feature-by-Feature Comparison

### 1. Markdown Files as Storage

| | Obsidian | Noto v2 |
|---|---|---|
| Notes as `.md` files | Yes | Yes |
| Folders as directories | Yes | Yes |
| YAML frontmatter | Yes | Yes |
| Sidecar metadata | `.obsidian/` (config, plugins) + IndexedDB cache | `.noto/` (SQLite index, HNSW) |
| File watching | Yes (auto-refreshes on external edits) | Planned (DispatchSource / NSFilePresenter) |

**Verdict: Same approach.** Both use the filesystem as source of truth with a sidecar cache. Noto v2's sidecar is more ambitious (paragraph identity, embeddings, HNSW) but the philosophy is identical.

---

### 2. Daily Notes

| | Obsidian | Noto v2 |
|---|---|---|
| Auto-create today's note | Yes (core plugin) | Yes |
| Custom date format | Yes (Moment.js tokens) | `YYYY-MM-DD.md` |
| Custom save location | Yes | `Daily Notes/` folder |
| Template on creation | Yes | Not yet |
| One-tap access | Ribbon icon, command palette, URI scheme | Today button |
| Navigate between days | No native prev/next day | Planned (swipe/arrows) |

**Verdict: Obsidian covers this well.** The Today button and day-to-day navigation are minor UX improvements, not fundamental differentiators. Obsidian plugins like "Calendar" and "Periodic Notes" already add prev/next day navigation.

---

### 3. Per-Paragraph Moving

| | Obsidian | Noto v2 |
|---|---|---|
| Move paragraph to another note | **No native feature.** Note Composer can extract selected text to a new/existing note, but it's manual select → extract, not paragraph-aware. | Core feature. Long-press paragraph → "Move to..." + cut/paste across notes preserves paragraph UUID. |
| Paragraph-level selection | No — text selection only | Paragraph is a first-class selectable unit |
| Bulk paragraph move | No | Yes (multi-select, same destination) |
| Undo move | No (Note Composer is destructive) | Cmd+Z reverses the move |
| Mention tracking on move | N/A | Index updates paragraph's `note_id`, all mentions re-resolve |

**Verdict: This is Noto v2's biggest differentiator.** Obsidian has no concept of "paragraph as a moveable unit." Note Composer is the closest thing but it's text-level, not paragraph-level. No UUID tracking, no mention preservation across moves.

**Could a plugin do this?** Partially. A plugin could:
- Use CM6 decorations to add paragraph-level selection UI
- Use `Vault.process()` to read/write files
- Move text between files programmatically

But it **cannot**:
- Track paragraph identity across moves (no UUID system — would need to invent one)
- Update backlinks automatically (Obsidian's link updater only handles file renames, not block-level moves)
- Integrate with Obsidian's undo system (CM6 undo is per-editor, not cross-file)

A plugin would essentially need to build the entire sidecar index that Noto v2 proposes. At that point, you're building an app inside an app.

---

### 4. Per-Line / Sentence Mentioning

| | Obsidian | Noto v2 |
|---|---|---|
| Note-level links | `[[Note]]` | `@[[Note]]` |
| Heading-level links | `[[Note#Heading]]` | Not planned (paragraphs are the unit) |
| Block/paragraph links | `[[Note#^block-id]]` | `@[[Note#paragraphId]]` |
| Sentence-level links | **No** | `@[[Note#paragraphId:sentenceHash]]` (paragraph ID + sentence hash in index) |
| Block ID storage | **Inline in the text:** `^block-id` appended to paragraph | **Sidecar index:** UUID assigned by index, files stay clean |
| Auto-generate block ID | Yes (random hex on first reference) | Yes (UUID assigned when paragraph is created) |
| Live cascade (content updates) | **No.** Link displays a static reference. Embeds show current content but only in reading/preview mode. | **Yes.** Mention chip always shows live current text of the referenced paragraph. |
| Backlinks | Yes (linked + unlinked mentions) | Yes (sidecar index query) |
| Mention survives paragraph edit | Only if `^block-id` text is preserved | Yes — UUID is in the index, not the text |

**Key difference: Block ID approach.**

Obsidian's `^block-id` lives in the markdown text itself. This means:
- The ID is visible in raw markdown (clutters the text)
- If the user deletes or edits the `^id` suffix, the reference breaks
- External editors can accidentally break references
- IDs are per-note unique, not globally unique

Noto v2's paragraph UUID lives in the sidecar index:
- Markdown files stay completely clean
- Identity survives content edits (index tracks by content hash + position)
- Trade-off: if the index is lost, paragraph-level references may not re-resolve

**Could a plugin do live cascade mentions?** Partially:
- CM6 widget decorations could render inline chips
- `MetadataCache.getFileCache()` provides block positions
- Plugin could resolve `^block-id` and fetch current content for display

But:
- This would be a custom rendering layer on top of Obsidian's editor — fighting the editor rather than working with it
- Live cascade requires re-rendering mentions whenever the target changes. Obsidian has no built-in pub/sub for "block X in note Y changed" — the plugin would need to poll or watch files
- Sentence-level granularity (`paragraph + sentence hash`) has no foundation in Obsidian's model

---

### 5. Hybrid Search (Keyword + Semantic)

| | Obsidian | Noto v2 |
|---|---|---|
| Keyword search | Yes — built-in, fast, good operators (`line:`, `block:`, `section:`, `tag:`, regex) | FTS5 with BM25 ranking, porter stemming |
| Semantic search | **No.** Keyword only. No embeddings, no vector search, no "search by meaning." | CoreML bge-small-en-v1.5 embeddings + HNSW (usearch) for cosine similarity |
| Hybrid ranking | No | α-weighted combination of BM25 + cosine similarity |
| Natural language date filters | No (manual operator syntax like `path:Daily`) | Yes — "things about food from January" parsed automatically |
| Dual-level results (note + paragraph) | Search returns matches grouped by file, with context. `block:` operator scopes to blocks. | Note-level and paragraph-level results interleaved in a flat ranked list |
| Offline | Yes | Yes |

**Verdict: Semantic search is Noto v2's second biggest differentiator.** Obsidian's search is powerful for keyword queries but cannot find conceptually related content when the words don't match. The query "something related to taste" will never find a paragraph about "aesthetic judgement" in Obsidian.

**Could a plugin do this?** Theoretically yes, but extremely difficult on mobile:
- A plugin could build an embedding index and HNSW search
- But **iOS Obsidian runs in a WebKit WebView** — no access to CoreML, no Neural Engine, no native Swift frameworks
- The plugin would need to either:
  - Run a WASM-based embedding model in the browser (very slow, large bundle)
  - Call an external API (not offline)
  - Use Obsidian's desktop-only Electron APIs (Node.js) for local inference — but then it doesn't work on mobile
- FTS5 via SQLite C API is not available in the plugin sandbox — would need to use a JS-based search library

This is the feature that most strongly argues for a native app. CoreML on the Neural Engine generates embeddings in ~30ms per paragraph. A JS-based model in a WebView would be 10-100x slower.

---

### 6. Editor Experience

| | Obsidian | Noto v2 |
|---|---|---|
| Engine | CodeMirror 6 (web) | TBD — likely UIKit TextKit or custom SwiftUI editor |
| Live preview | Yes (CM6 decorations — syntax hidden except at cursor) | Planned (markdown rendered inline) |
| Source mode | Yes (raw markdown) | Not planned for v1 |
| Reading mode | Yes (fully rendered HTML) | Not planned for v1 |
| Platform | Web (Electron desktop, WebKit/WebView mobile) | Native iOS/macOS (Swift, UIKit/SwiftUI) |

**Verdict: Obsidian's editor is mature and feature-rich.** Building a comparable markdown editor from scratch is significant work. However, a native editor can do things a web editor can't — like integrate with iOS text input, haptics, native context menus, and CoreML.

---

## Summary: Build vs. Plugin

### What Obsidian already does well (no need to reinvent)
- Markdown files as storage with filesystem watching
- Daily notes with templates
- Wikilinks and backlinks
- Block references (with `^block-id` in the text)
- Embeds/transclusions
- Keyword search with good operators
- Graph view
- Mature editor with three modes
- Large plugin ecosystem

### What Noto v2 adds that Obsidian can't do (or can't do well)

| Feature | Why Obsidian can't match it | Plugin feasibility |
|---|---|---|
| **Per-paragraph moving with UUID tracking** | No paragraph identity model. Note Composer is text-level, not paragraph-level. No cross-file undo. | Would need to build entire sidecar index inside a plugin — app-in-an-app problem |
| **Live cascade mentions** | Embeds show current content but only in preview. No real-time chip rendering that updates across notes. | Partially possible with CM6 widgets but would fight the editor |
| **Sentence-level mentions** | No concept of sentences. Block IDs are the finest granularity. | No foundation in the model |
| **Semantic search (offline, on-device)** | No embedding/vector infrastructure. iOS runs in WebView, no CoreML access. | Infeasible on mobile. Desktop-only with JS-based models would be very slow. |
| **Hybrid ranking (keyword + semantic)** | Keyword-only search. | Same as above — semantic component blocks it |
| **Clean markdown files (no `^block-id` clutter)** | Block IDs live in the text. It's a design choice, not a limitation — but it means files aren't "clean" markdown. | Can't change this — it's core to how Obsidian works |

### Recommendation

**Build the standalone app.** The three differentiators that matter most — paragraph mobility with identity tracking, live cascade mentions, and hybrid semantic search — all require architectural foundations that Obsidian's plugin system cannot provide:

1. **Paragraph identity** needs a sidecar index with UUID tracking, content hashing, and position matching. Obsidian's `^block-id` is text-level, not index-level.
2. **Live cascade** needs real-time cross-note content resolution. Obsidian's embed system renders at view time, not as a live updating chip.
3. **Semantic search on iOS** needs CoreML and the Neural Engine. Obsidian's iOS app runs in a WebView with no native framework access.

Building these as Obsidian plugins would mean building the entire Noto v2 backend inside a constrained plugin sandbox, fighting the host editor at every integration point. The result would be fragile, slow on mobile, and limited by Obsidian's architectural assumptions.

The one thing you'd lose by not building on Obsidian is the **ecosystem** — community plugins, themes, sync, publish, and the existing user base. That's a real cost, but it's a distribution problem, not a technical one.
