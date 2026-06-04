# iOS Redesign — Session Decisions & Status (2026-06-04)

Continuation of the v2 redesign (claude.ai/design "Noto System"). Spec:
`.claude/ios-redesign/component-breakdown.md`. Worktree: `worktrees/ios-redesign`.

## Done before this session
- §1 `NotoTheme` tokens.
- §3 File view (`NoteListView` restyle + nav + `NotoAppBottomToolbar` floating glass dock).

## This session — scope (user-confirmed)
Build **search → properties → editor** (low-risk first, then the risky editor).

### Decision 1 — sequence
**search → properties → editor** (not spec order). New self-contained screens first
(fast, low regression), the 8k-line `TextKit2EditorView` re-theme last.

### Decision 2 — editor depth (when we get there)
**Chrome + colors only, defer typography.** Re-theme nav chrome (bare back+more,
scroll scrim) + editor bg/caret/text colors to `NotoTheme`. Keep existing font ramp
(body 17 etc.); skip the 25/700 first-line-as-title special-case for now.

## Key architecture facts (verified)
- `Noto/` is a PBXFileSystemSynchronizedRootGroup → new `.swift` files under it auto-compile. No pbxproj edits needed.
- **Search backend already exists**: `Packages/NotoSearch` (`MarkdownSearchEngine`, `SearchScope.title/.titleAndContent`, `SearchResult{title,breadcrumb,snippet,updatedAt}`). An existing `NoteSearchSheet` (in `NoteListView.swift`) already wires query/scope/results/recentNotes/index. Search work = **restyle**, not new logic.
- Dock search pill (`NotoAppBottomToolbar.onSearch`) → `.openSearch` intent → presents `NoteSearchSheet`.
- Reusable glass: `dockGlass()` + `glassDockContainer` (GlassEffectContainer, iOS 26) in `NoteListView.swift`.
- Relative date: `NotoRelativeDate.editedString` (NotoVault).

## Verification
Per-screen: build → simulator visual check → spawn `claude-design-verifier` against the
local render (http://localhost:8765/Noto%20System.html). Sim: `iosredesign-redesign-a1b2c3`
(UDID 6687CFDF-0F60-41E8-9A3F-5927FA7825FE, iOS 26.2).

## Status
- [x] Search restyle — verifier PARTIAL→PASS (glyph delta fixed: uniform `doc.text`).
- [x] Properties sheet — READ-ONLY shipped (faithful list state). Editing (add/edit/delete) deferred to editor pass: write-back doesn't persist through the covered live editor's UITextView (see improvement log). Helpers retained in `PropertiesSheet.swift`.
- [x] Editor chrome + colors — verifier PASS (surface #0E1116, ink #ECECEE, accent caret, bare back+more, no breadcrumb). NotoVault 60 tests green.

## Deferred follow-ups (next pass)
- Editor typography: first-line note title 25/700, body 16 / h2 18 ramp, heading white #FFF, scroll-scrim top bar with centered title.
- Properties editing (add/edit/delete): re-enable with an authoritative `NoteEditorSession` write-back that updates the UITextView + persists (helpers already in `PropertiesSheet.swift`; align Status to `contains` — done).
- Optional: full bare-icon custom editor top bar (currently keeps system nav bar to preserve swipe-back).
