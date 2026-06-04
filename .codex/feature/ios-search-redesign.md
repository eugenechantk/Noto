# Feature: iOS Search — v2 redesign (restyle)

## User Story
Tapping the file-view dock search pill opens a full-screen dark search surface matching
the v2 design (`Exp03ArticleV3Search`, `noto-explorations-v3-3-search.jsx`).

## Spec
`.claude/ios-redesign/component-breakdown.md` §6. Canonical render = Body + (results)
Segmented + bottom glass SearchDock + keyboard. The JSX `Header` is **dead code** (not in
return) → omit. Live render: http://localhost:8765/Noto%20System.html.

## Design (rendered)
- Dark `#0E1116`, status-bar reserve at top.
- **Body** (scrollable): section title (uppercase 11/600, +0.6 tracking, muted) —
  "Last edited" (empty) / "Search results" (results). Rows: file glyph (muted) + title
  (15/500 head) + sub "in <Folder> · <when>" (12/muted) + [results] 2-line snippet (12.5/ink
  0.85) with matched term highlighted amber `rgba(230,182,42,0.32)`. Hairline `rgba(255,255,255,0.06)` row separators.
- **Segmented** (results only, above dock): "Title + body" / "Title only", glass pill, full width, 34pt.
- **SearchDock** (bottom): glass pill (magnifier 17 muted + focused TextField "Search or ask AI" + filter chip icon) + separate glass ✕ close circle (46) outside the pill.
- Keyboard.

## Reuse (no new logic)
Keep all `NoteSearchSheet` data plumbing: `query`, `scope` (`SearchScope.titleAndContent`↔"Title + body",
`.title`↔"Title only"), `results`, `recentNotes`, `scheduleSearch`, `loadRecentNotes`,
`prepareIndex`, `appResult`, `onSelect`. Reuse `dockGlass()`/glass container.

## Implementation
- Restyle the **iOS branch only** of `NoteSearchSheet` (`NoteListView.swift`): replace the
  `.searchable`/nav-title/`List` layout with a custom VStack: results/recent list → (results) segmented → bottom glass dock with embedded focused `TextField` + ✕ close. macOS branch untouched.
- New iOS `NotoSearchResultRow` styling (glyph + title + "in folder · when" + highlighted snippet). Folder = last path component of breadcrumb; when = `NotoRelativeDate.compactString(modifiedDate)`.
- Add `NotoRelativeDate.compactString(from:)` (NotoVault) → "2h ago" form (editedString minus "Edited ").
- Snippet highlight: client-side — highlight query tokens in snippet with amber background via AttributedString.
- Keep accessibility ids: `note_search_sheet`, `note_search_query_field`, `note_search_result_<i>`, scope ids, `note_search_cancel_button`. Add `search_segmented_control`.

## Success Criteria
- SC1: Dock search pill opens the restyled dark search surface (no top searchable bar, no nav title).
- SC2: Empty state shows "LAST EDITED" section + recent note rows (title + "in folder · when", no snippet).
- SC3: Typing shows "SEARCH RESULTS" + rows with 2-line snippet, matched term highlighted amber.
- SC4: Segmented control (results only) flips `scope`; "Title only" re-queries title-only.
- SC5: Bottom glass dock: focused field "Search or ask AI" + filter chip + outside ✕ close; tapping ✕ dismisses.
- SC6: Tapping a row opens that note (existing `onSelect`). No regression to search backend.

## Test Strategy
Backend covered by NotoSearchTests. UI = simulator visual + verifier agent. Add a unit
test for `NotoRelativeDate.compactString`.

## Status: DONE — verifier PASS (all 5 criteria; uniform `doc.text` glyph delta fixed).
