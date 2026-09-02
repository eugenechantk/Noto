# Tag System — Implementation Plan

Status: DRAFT for review · Tier: Product · Date: 2026-07-25

## 1. What the user asked for

1. Add & edit tags in the note view.
2. Search by tags — typing `#` in the search bar shows a live list of matching
   tags (dash-delimited names) above the search bar; picking one filters notes.
3. Edit tag *properties* — every tag has a **name** (dash-delimited) and a
   **content template** that is appended to the **end** of the document.

This aligns exactly with Eugene's own note in `README.md`: tags exist mainly as
"a categorization tool for applying different templates or presets."

## 2. What already exists (do NOT rebuild)

Note-level tag *membership* is already implemented via frontmatter:

- **`NotePropertyClassifier`** (`Packages/NotoVault/.../NoteProperty.swift`) —
  `parseTags` / `serializeTags` (inline flow list `[a, b, c]`), classifies a
  `tags:` / `keywords:` field as `.tags`.
- **`EditableFrontmatterDocument`** (`Noto/Editor/EditableFrontmatter.swift`) —
  loss-preserving frontmatter read / `updatingField` / `addingField` /
  `deletingField`.
- **`PropertiesSheet`** (iOS, `Noto/Views/iOS/PropertiesSheet.swift`) &
  **`MacPropertiesForm`** (macOS) — already render + inline-edit a `tags:` field
  with `TagChip` chips, add via `+`, remove by clearing. Writes through
  `session.applyExternalContentEdit`.
- **`TagChip`** view already exists.
- **Page-mention autocomplete** in `TextKit2EditorView` (`page_mention_*`, a
  `PageMentionDocument` provider from `NoteEditorScreen`) — a reusable inline
  suggestion-menu pattern we can mirror for `#` autocomplete.
- **Search** — `NoteSearchSheet` (`Noto/Views/NoteListView.swift:2122`) with
  `query` + `scope`, backed by `MarkdownSearchEngine`/FTS5 with a vault-scan
  fallback. The FTS index lives in Application Support (a rebuildable cache).

So requirement #1 is ~70% done. The genuinely new work is the **tag registry**
(names + templates), **`#tag` search**, and **template application**.

> ⚠️ Legacy vs. active code (confirmed): `NotoVault/Frontmatter.swift`,
> `NoteFile.swift`, `VaultManager.swift`, and `Noto/Storage/NoteTemplate.swift`
> are **dead** — the app never imports them. The live read/write path is
> `MarkdownNoteStore` → `VaultMarkdown` (frontmatter keys today: `id`, `created`,
> `updated`) + `EditableFrontmatterDocument` (surgical, order-preserving editor),
> and the live template system is `DailyNoteService`. All new work builds on the
> live path only.

## 3. The core new concept: two levels of "tag"

- **Membership** (which notes have a tag) — already the per-note frontmatter
  `tags:` list. Stays the source of truth for filtering.
- **Definition** (a tag's name + template + future properties) — NEW. Needs a
  persistent, vault-resident, agent-editable store: the **Tag Registry**.

## 4. Proposed architecture

### 4.1 New package target: `NotoTags` (in `Packages/`)

Per project principle #1 (non-UI logic lives in a package, testable via
`swift test`). Responsibilities:

- **`TagName`** — value type enforcing the dash-delimited rule. Normalizes on
  init: lowercase, spaces/underscores → `-`, strip leading `#`, collapse repeat
  dashes, allowed charset `[a-z0-9-]`. `podcast script` → `podcast-script`.
- **`TagDefinition`** — `{ name: TagName, template: String, createdAt, modifiedAt }`.
  Extensible for future per-tag properties (metadata template, color, icon).
- **`TagRegistry`** — the collection of definitions. Codable.
- **`TagRegistryStore`** — load/save the registry as JSON at a fixed vault path
  (see Fork A). Coordinated file I/O consistent with the vault. Auto-creates
  missing entries (lazy registration) when a note uses a new tag.
- **`TagMembershipIndex`** — builds a `tag → [note URLs]` map by scanning
  frontmatter `tags:` across the vault (cheap for personal vaults; refreshed via
  the existing file watcher). Powers both the `#` suggestion list (all known tag
  names) and tag-filtered search (notes for a tag). Avoids touching the FTS
  schema in v1.
- **`TagTemplateApplier`** — pure function: given note content + a tag's
  template, append the template to the end of the body (after a blank line),
  idempotently (skip if a stable marker for that tag's template is already
  present). Mirrors the `body` + `marker` idempotency pattern in the **live**
  template system, `DailyNoteService.DailyNoteTemplate` (`Packages/NotoVault/
  .../DailyNoteService.swift`) — NOT the dead `Noto/Storage/NoteTemplate.swift`.
  Note: DailyNote injects *after the title*; tag templates instead append at the
  **end** of the body. There is no existing "append to end" helper, so this
  operates on the markdown string and is persisted via
  `session.applyExternalContentEdit`.

All of the above are UI-free and unit-tested.

### 4.2 App-target glue

- **`TagController`** (app-facing facade, mirrors `VaultController` /
  `SearchIndexController`) — owns the loaded `TagRegistry`, exposes
  `allTags()`, `suggestions(matching:)`, `definition(for:)`, `save(definition:)`,
  `notes(withTag:)`, and `applyTemplate(for:to:)`. Refreshes the membership index
  on `.vaultDidChange` / file-watcher notifications.
- Injected into the environment alongside the existing stores.

## 5. Feature-by-feature implementation

### 5.1 Add & edit tags in the note view (req #1)

Keep tags in frontmatter (already working). Enhancements:

- **Registry-backed autocomplete** in the existing tags chip editor: as the user
  types a tag member in `PropertiesSheet` / `MacPropertiesForm`, show suggestions
  from `TagController.suggestions(matching:)`. Reuse the mention-menu list styling.
- **Auto-normalize** the typed value through `TagName` before writing (so
  "Podcast Script" persists as `podcast-script`).
- **Lazy registration**: committing a brand-new tag creates a `TagDefinition`
  with an empty template in the registry.
- **Template application on add** (see Fork C): when a tag is newly added to a
  note and its definition has a non-empty template, append the template to the
  end of the note body via `TagTemplateApplier` (idempotent).

### 5.2 Search by tags (req #2)

In `NoteSearchSheet`:

- **`#` detection**: when the trimmed query starts with `#` (or the active token
  is `#…`), switch into "tag mode". Parse the fragment after `#`.
- **Suggestion strip** above the search dock: `TagController.suggestions(matching:
  fragment)` → tappable `TagChip`s. Mirrors the existing bottom-controls inset
  layout (`iosBottomControls`) and the page-mention suggestion list.
- **Selecting a tag** sets an active tag filter (shown as a chip in the field)
  and lists notes from `TagController.notes(withTag:)`, ordered by recency,
  reusing `NotoSearchRowV2`. Remaining free-text after the tag further filters by
  title/body.
- Works on both iOS sheet and the macOS search panel (shared query-state layer,
  thin platform presentation).

### 5.3 Edit tag properties (req #3)

- **Tag management surface**: a "Tags" section in `SettingsView` → a list of all
  `TagDefinition`s. Row = tag name + note count. Tap → **Tag Detail** editor:
  - Edit **name** (dash-delimited, live-normalized; renaming rewrites frontmatter
    across member notes — see Edge Cases).
  - Edit **content template** (multiline text editor).
  - Delete tag (removes definition; optionally strips from member notes — confirm).
- Reuse the paired circular ✕/✓ sheet header convention
  (`SheetCircleButton`, per `project_sheet_header_hig`).

## 6. Decisions (LOCKED — signed off 2026-07-25)

- **Storage (Fork A) → A1.** Tag definitions live in one JSON file at
  `<vault>/.noto/tags.json`. Vault-resident, syncs via iCloud, agent- and
  human-editable, invisible to the note list. Membership stays in each note's
  frontmatter `tags:`.
- **Note-view editing (Fork D) → D1, Properties sheet only.** Enhance the
  existing frontmatter tags chip UI in the Properties sheet (iOS) /
  `MacPropertiesForm` (macOS) with `#` autocomplete from the registry. **No**
  inline tag bar under the title, and **no** inline-body `#tag` tokens in v1.
- **Template timing (Fork C) → apply-on-add, idempotent.** When a tag with a
  non-empty template is newly added to a note, append the template at the end of
  the body, once. Editing a template later does NOT retro-apply; an explicit
  "apply to existing notes" action is a future follow-up.
- **Template scope → content only for v1.** A tag template is markdown appended
  to the body. `TagDefinition` is designed to extend to metadata/frontmatter
  templates later.

## 7. Edge cases & decisions

- **Name normalization**: `TagName` is the single chokepoint; all writes go
  through it. `#`-prefix stripped, spaces→dashes, lowercased.
- **Tag rename**: rewrites the tag in every member note's frontmatter (batch,
  coordinated writes) + updates the registry. Membership index rebuilt after.
- **Template idempotency**: `TagTemplateApplier` uses a stable per-tag marker so
  re-adding a tag or reopening a note never duplicates the template.
- **Multiple tags with templates** on one note: append each once, in add order.
- **Deleting a tag definition**: confirm; choose to keep or strip from notes.
- **Registry vs reality drift**: membership index is derived from frontmatter
  (source of truth); registry only stores *settings*. Unknown tags found in
  notes are lazily registered with empty templates.

## 8. Testing

- **`swift test` (NotoTags)**: `TagName` normalization, registry
  load/save/round-trip, membership index scan, template applier idempotency,
  rename rewrite.
- **`swift test` (NotoVault)**: extend `NotePropertyTests` for dash normalization
  interplay if `serializeTags` changes.
- **App tests**: search `#` mode filtering; Properties autocomplete + template
  application on add; tag detail edit → registry persistence.
- **Simulator visual verification** (required for UI): search `#` suggestion
  strip, Properties autocomplete, Settings tag list + detail editor, template
  appended after adding a tag. iPhone + iPad + macOS.

## 9. Rough sequencing

1. `NotoTags` package (TagName, TagDefinition, TagRegistry, store, membership
   index, template applier) + unit tests. *(Codex-delegated per routing.)*
2. `TagController` app glue + environment wiring.
3. Properties autocomplete + normalization + template-on-add (req #1).
4. `#` search mode + suggestion strip + tag filtering (req #2).
5. Settings tag list + tag detail editor + rename/delete (req #3).
6. Full test pass + simulator visual verification on iPhone/iPad/macOS.

## 10. Status

All design forks resolved (§6). Plan is ready for final sign-off before
implementation begins. Implementation of the `NotoTags` package and app glue
will be delegated to Codex per the cross-harness routing policy; Claude frames
the spec, reviews the diffs, and runs verification (unit tests + simulator).
