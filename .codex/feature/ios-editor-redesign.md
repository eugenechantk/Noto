# Feature: iOS Editor — v2 redesign (chrome + colors, typography deferred)

## User Story
The note editor adopts the v2 visual system: dark `#0E1116` surface, `#ECECEE` body ink,
accent `#FF6A2E` caret, and a minimal top bar (bare back + more, no breadcrumb) per
`NotoMinimalEditor` (`noto-minimal-editor.jsx`).

## Spec
`.claude/ios-redesign/component-breakdown.md` §4. Render: http://localhost:8765/Noto%20System.html.

## Scope decision (user-confirmed)
**Chrome + colors only; typography deferred.** Keep the existing markdown font ramp
(body 17, h1 28, h2 22 …) and do NOT special-case the first line as a 25/700 note title
this pass. Scroll-scrim title also deferred.

## Changes (this pass)
- **Surface**: editor `view`/`textView` background `AppTheme.uiBackground (#0A0A0A)` →
  `NotoTheme.uiBackground (#0E1116)` (`TextKit2EditorView.viewDidLoad`). `NoteEditorScreen`
  `.background` → `NotoTheme.background` (iOS only). macOS unchanged.
- **Body ink**: `MarkdownTheme.bodyColor` (iOS) `#E5E5E5` → `NotoTheme.uiInk (#ECECEE)`.
- **Caret/selection**: `textView.tintColor = NotoTheme.uiAccent (#FF6A2E)` (was default blue).
- **Chrome**: removed the `BreadcrumbBar` principal toolbar item — the v2 editor bar carries
  no breadcrumb/title, just bare back (leading) + ••• more (trailing). Properties item already
  added to the More menu (Properties pass).

## Deferred (follow-up)
- Typography: note title 25/700 first-line special-case, body 16 / h2 18 ramp, heading white (#FFF).
- Scroll-scrim top bar carrying the centered note title.
- Full bare-icon custom top bar (like file view) — kept the system nav bar this pass to preserve swipe-back (low risk).
- **Re-enable Properties editing** (add/edit/delete) with an authoritative `NoteEditorSession`
  write-back that updates the UITextView text + persists (the current sheet edit only mutates
  `session.content`, which the covered editor's text view ignores — see improvement log).

## Success Criteria
- SC1 ✅: editor surface renders `#0E1116`; body text `#ECECEE`.
- SC2 ✅: caret + selection are accent orange `#FF6A2E`.
- SC3 ✅: top bar shows bare back + ••• more, no breadcrumb/title.
- SC4: no regression — editing, autosave, find, frontmatter block, todo, images still work.

## Test Strategy
Editor logic unchanged (colors/chrome only). Simulator visual verification + verifier agent.
Confirm typing/caret + back navigation still work.

## Status: DONE (chrome + colors) — verifier PASS on SC1–SC3 (surface #0E1116, ink #ECECEE, caret #FF6A2E, bare back+more no breadcrumb). Typography + editing re-enable deferred per scope.

## Revision round 2 (user feedback 2026-06-04) — DONE
- **Keyboard toolbar** redesigned to `NotoToolbarArticle`: full-width `#1A1C22` bar + top hairline, horizontally-scrolling icon rail [todo · indent± · strike · link · image] (idle gray 36×36), and a pinned Done (keyboard-dismiss) on the trailing edge behind a vertical hairline divider. (`TextKit2EditorView.makeInputAccessoryView`.)
- **Inline "Metadata" frontmatter block removed** from the editor (gated by `rendersInlineFrontmatterBlock = false`; `refreshFrontmatterControls` clears + returns, `frontmatterReservedHeight = 0`). Frontmatter text stays collapsed (~0 height); editor opens straight to the title. Legacy block code retained behind the flag.
- **More menu → Properties with count subtitle**: shows "Properties" + "N properties" (two-Text menu-button subtitle), `propertyCount` = frontmatter field count, opens the medium-detent Properties sheet.
- **Scrolled top bar**: note title (`MarkdownNote.titleFrom`) rises into the nav-bar center when scrolled past the title (`showsScrolledTitle`, threshold offsetY > 48, driven by `persistEditorContentOffsetY`). a11y id `editor_scrolled_title`.
- All visually verified in the simulator. Build clean.
