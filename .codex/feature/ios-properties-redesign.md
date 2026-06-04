# Feature: iOS Properties sheet — v2 redesign

## User Story
From the editor More menu, "Properties" opens a bottom sheet showing the note's frontmatter
as an inset-grouped iOS list (v2 design `NotoPropertyList` / `noto-properties-hig.jsx`),
where the user can view, edit, add, and delete properties.

## Spec
`.claude/ios-redesign/component-breakdown.md` §5. Source JSX: `noto-properties-hig.jsx`
(NotoPropertyList, NotoTypeMenu, Row, Chip, Folder, Status, Value), sheet shell from
`noto-minimal-editor.jsx` (SheetCircleBtn) + `noto-sheet.jsx`. Render: http://localhost:8765/Noto%20System.html.

## Design (rendered)
- **Presentation**: `.sheet` over editor; detents `[.medium, .large]`; grabber (`.presentationDragIndicator(.visible)`); rounded top. Header row: glass circular ✕ (leading) / filled-accent ✓ (trailing) + centered "Properties" title (paired buttons per `[[project_sheet_header_hig]]`).
- **Surface**: grouped background `#111419`; one rounded (11) card `#1C2027` inset 16pt.
- **Row**: leading SF glyph (22 box, 13 gap, secondary color), label 16 (`rgba(235,235,245)` ink/white), trailing value (secondary, right-aligned). 44pt min. Hairline separator `rgba(84,84,88,0.55)` inset to label leading edge (16+22+13=51).
- **Rows** (in order): Folder (chevron + accent-dot 7×7 + name), Created (read-only, tertiary value, no chevron), Modified (read-only tertiary), Tags (horizontal-scroll chips + trailing fade + swipe→red trash), Source (editable value, caret when editing), Status (colored dot 9×9 + label + chevron), Author (value), **Add property** (accent `+` row, no separator).
- **Chip**: fill `rgba(118,118,128,0.24)`, 24pt tall, radius 7, label 13.5, white.
- **TypeMenu** (pull-down on Add): glass menu `rgba(44,44,48,0.72)` blur, 252 wide, radius 14; rows Text·Tags·Date & time, 44pt, leading checkmark (accent) on selected + trailing type glyph.
- **Adding row**: fixed 120px key column (horizontal scroll + trailing fade), value anchored right; keyboard up.

## Data — safe edit path (no data loss)
Frontmatter is part of the editor's markdown text. Reuse `EditableFrontmatterDocument`
(Noto/Editor): `parseFields(markdown)`, `updatingField`, `addingField`, `deletingField` —
all operate on the raw markdown via `MarkdownFrontmatter.range`, preserving every key.
Apply edits by: `session.content = newMarkdown; session.handleEditorChange(newMarkdown)`
(same persist path the TextKit editor uses on every keystroke).

- **Folder**: derived from note file URL parent relative to vault root (display only in v1; accent dot + name + decorative chevron, no move wiring yet).
- **Created/Modified**: from `created`/`modified` frontmatter fields (ISO date → "May 14, 2026" / "2h ago"); read-only.
- **Custom rows**: every frontmatter field except `id`/`created`/`modified`. Key "tags" (or list-shaped value) → chips (split on comma); URL-valued (e.g. source) → value with link affordance; "status" → colored dot + label; others → plain value.

## Scope (v1)
- Presentation + header + inset-grouped styling (faithful visual).
- View all rows from frontmatter.
- Edit a custom field's value (tap → inline/alert text edit → `updatingField`).
- Add property (Add row → TypeMenu Text/Tags/Date visual → key+value entry → `addingField`).
- Swipe-to-delete custom rows (`.swipeActions` → `deletingField`).
- Folder/Created/Modified read-only.

## Implementation
- New `Noto/Views/iOS/PropertiesSheet.swift` (iOS-only; sheet container + rows + type menu + add/edit flows).
- New `Noto/Views/Shared/SheetCircleButton.swift` (glass ✕ / accent ✓), reusable per `[[project_sheet_header_hig]]`.
- Optional small `PropertyTyping` helper (NotoVault) to classify a field (tagsList / url / plain) — pure logic, testable.
- Wire: add "Properties" item to the iOS editor More menu (`IOSEditorNavigationChrome.moreMenu`); `NoteEditorScreen` presents `PropertiesSheet(session:)` via `@State showProperties`.
- a11y ids: `properties_sheet`, `properties_close_button`, `properties_confirm_button`, `property_row_<key>`, `add_property_button`, `property_type_menu`, `property_type_<text|tags|date>`.

## Success Criteria
- SC1: Editor More menu → Properties opens the sheet (medium detent, grabber, ✕/✓ header, "Properties" title).
- SC2: Inset-grouped card shows Folder · Created · Modified · custom fields, NotoTheme grouped tokens, glyphs, hairline inset.
- SC3: Tags field renders as horizontally-scrolling chips; Source as value; Status with colored dot.
- SC4: Add property → type menu → entering a key/value adds it to the note's frontmatter (persisted).
- SC5: Swipe a custom row → delete removes the field from frontmatter (persisted); editing a value updates it.
- SC6: No data loss — id/created/modified and all untouched keys preserved (round-trip).

## Test Strategy
Add NotoVault tests for any `PropertyTyping` classification. Frontmatter round-trip already
covered by EditableFrontmatter usage; add a focused test if a new pure helper is introduced.
UI = simulator visual + verifier agent.

## Status: READ-ONLY shipped this pass; editing deferred to editor pass
- SC1 ✅ sheet presentation (medium/large detents, grabber, ✕/✓ header, "Properties" title) from More menu.
- SC2 ✅ inset-grouped card: Folder (accent dot + chevron) · Created · Modified · all custom frontmatter fields, NotoTheme grouped tokens, semantic glyphs (link/person/calendar/status/tag/textformat), hairline inset.
- SC3 ✅ Tags → horizontally-scrolling chips (handles inline + YAML block lists) + trailing fade; Source/URLs → value; Status → colored dot. (Verifier D1 fixed: status colored-dot value + chevron now keyed on `contains("status")` so `*_status` keys get the dot, matching the glyph mapping.)
- Verifier verdict: **PASS** (read-only scope).
- SC4/SC5 ⏸ DEFERRED: add/edit/delete write-back. Implemented (helpers retained in `PropertiesSheet`) and works in-memory, but does NOT persist: the open editor's `UITextView` owns the saved text and doesn't adopt external `session.content` changes while the sheet covers it (see improvement log 2026-06-04). Re-enable during the editor pass with an authoritative session write-back that updates the text view. The "Add property" row + swipe-delete + tap-to-edit are disabled until then.
- SC6 ✅ read path preserves all keys (no data loss; nothing written).
