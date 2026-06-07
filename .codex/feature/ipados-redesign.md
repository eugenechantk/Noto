# Feature: iPadOS — v2 redesign (NavigationSplitView)

## Source
Design `NotoIPad` in `Design/v2/components/noto-platforms.jsx` (states: reading · editing ·
properties · portrait-reading · portrait-files · portrait-properties). Entry section
`sys-ipad`: "Regular size class → NavigationSplitView: a persistent translucent file-system
sidebar + editor detail. Properties as a centered form sheet, not a bottom sheet."

## Design spec (rendered)
**Landscape (1194×834)**
- **Floating translucent Liquid-Glass sidebar** — `IPadSidebar`: a rounded-20 panel inset from
  the leading edge (top 42, left 12, bottom 12, ~300w), bg `rgba(34,38,46,0.55)` + blur(50)
  saturate(180), inset hairline. The detail/background extends full-bleed BEHIND it.
  Content = `VaultSidebarContent`: explorer nav row (accent `‹ Vault` back · new-folder · ⋯),
  large folder title + "N folders · M notes", then SidebarFolderRow (glyph · name · "N items" ·
  chevron) and SidebarFileRow (glyph · title · "Edited <when>", active = accent-tint bg).
- **Detail pane** (editor): bare-icon toolbar — LEADING sidebar-toggle + back, TRAILING search +
  more (`PlainBtn`, 22pt SF, no glass circle). Article body maxW 600.
- **Bottom floating dock** over the detail (today · search · new, glass capsules). Hidden when editing.
- **Editing**: iPad keyboard + the iPhone `NotoToolbarArticle` accessory; dock hidden.
- **Properties** = centered **FORM SHEET** (`PropsCard`): a 540w rounded-16 card over a dimmed
  split, circular ✕/✓ header + "Properties" title + inset-grouped `NotoPropertyList`. NOT a bottom sheet.

**Portrait (834×1194)**
- Content-first: full-width editor, sidebar collapsed; toolbar LEADING sidebar-toggle + back.
- **Sidebar** = leading-edge **overlay** (same glass panel) over a dimmed editor.
- **Properties** = same centered form sheet.

## Current implementation (baseline)
- `NoteListView` regular size class → `NotoSplitView` (a native `NavigationSplitView`,
  `.prominentDetail`, `.regularMaterial` toolbar bg) with `NotoSidebarView` sidebar + editor detail.
- The floating dock (`.notoAppBottomToolbar`) is already wired on the detail.
- Portrait already shows: collapsed sidebar, editor, leading sidebar-toggle (glass circle) + back,
  bottom dock. So the structure matches; the gaps are visual + a few behaviors.

## Gap → plan (build order)
1. **Detail toolbar → bare icons.** Strip the iOS 26 glass container from the sidebar-toggle / back /
   more (reuse the editor's `sharedBackgroundVisibility(.hidden)` pattern). Add the search icon to the
   trailing group (currently search is dock-only). Applies to the split editor chrome (`splitClean`/
   `EditorLeadingChromeControls`).
2. **Sidebar → floating translucent glass panel.** Style the `NavigationSplitView` sidebar column
   with the glass material + rounded inset so it reads as the floating `IPadSidebar` over the dark bg
   (vs the current flush material column). Restyle `NotoSidebarView` rows to `VaultSidebarContent`
   (folder/file rows, large title + counts, accent back).
3. **Properties → form sheet.** Wire a "Properties" item into the iPad editor's More menu and present
   `PropertiesSheet` with `.presentationDetents`/`.formSheet`-style centered sizing (`presentationSizing(.form)`
   on iOS 18+, or a sheet sized ~540 centered) instead of the bottom sheet. Reuse the existing
   `PropertiesSheet` (already read-only + editable).
4. **Portrait sidebar overlay polish.** Ensure the collapsed→overlay sidebar uses the glass panel.

## Scope decision (sidebar)
Two ways to get the "floating glass sidebar over full-bleed bg":
- (A) Keep `NavigationSplitView`, style the sidebar column glass + inset (less code, native behavior). **Recommended.**
- (B) Replace with a custom ZStack (full-bleed detail + glass sidebar overlay) for the literal
  background-extension look. More control, more rework + loses native split conveniences.

## Success Criteria
- SC1: Landscape — floating glass sidebar (rounded, translucent) over the dark editor; detail = bare-icon toolbar.
- SC2: Sidebar rows match the design (folder/file rows, large title + counts, accent active note).
- SC3: Bottom dock present on the detail; hides when the keyboard is up.
- SC4: Properties opens as a centered form sheet (✕/✓ header + grouped list), not a bottom sheet.
- SC5: Portrait — sidebar collapses to a leading glass overlay + dim; editor full-width.
- SC6: No regression to navigation, selection, or editing.

## Test/verify
iPad mini sim `ipadredesign-a1b2c3` (UDID E2706BF2-8DBD-4129-9C0F-18F83F96EE63, iOS 26.2).
Visual verification per slice + `claude-design-verifier` against `NotoIPad` artboards.

## Key finding — shared chrome (must handle before re-skin)
The iPad detail editor renders `NoteEditorScreen` with `chromeMode =
.compactNavigation(showsInlineBackButton: false)` and `leadingChromeControls = .none` (iOS).
So it reuses the SAME `EditorNavigationChrome` compact path as the iPhone editor. Consequences:
- The recent iPhone editor work (bare back/•••, `sharedBackgroundVisibility`, scrolled-title,
  and the in-`NoteEditorScreen` dock gated by `isCompactChrome`) ALREADY applies to the iPad detail.
- The visible glass toggle on the iPad is the NATIVE `NavigationSplitView` sidebar button, not chrome.
- RISK: `NotoSplitView` already adds `.notoAppBottomToolbar` on the detail, AND `NoteEditorScreen`
  now adds one too (isCompactChrome) → potential DOUBLE dock on iPad. Verify + gate so only one shows
  (likely suppress the NoteEditorScreen dock when inside the split / regular size class).
- Decide a distinct iPad chrome story: bare back may not suit the split detail (no stack to pop at the
  root); scrolled-title + InteractivePopGestureEnabler may be iPhone-only. Consider a dedicated
  `.splitClean` chrome path rather than overloading `.compactNavigation`.

## Status: core implemented + verified on the iPad mini sim.
- SC1 ✅ native `NavigationSplitView`; detail toolbar now matches the design — LEADING sidebar-toggle +
  back, TRAILING **search + more** (two buttons each side). The standalone trailing search button is
  gated to regular width (`horizontalSizeClass == .regular`) so the iPhone minimal editor stays
  `back · more` (search in the ••• menu). Native split sidebar-toggle still uses the system glass
  button (acceptable native treatment) vs the design's bare PlainBtn.
- SC2 ✅ sidebar header rebuilt to `VaultSidebarContent` (accent `‹ Vault` back · new-folder + ⋯ more ·
  24/700 folder title · "N folders · M notes" counts) and `SidebarDirectoryRow` (iOS) restyled to
  `SidebarFolderRow`/`SidebarFileRow` (glyph · title 15 · subtitle 12/muted · folder chevron; active
  file = accent-tint bg + accent glyph + white title; 0.5pt hairlines; folder glyph ink@0.80).
- SC3 ✅ single bottom dock, centered compact group; search pill fixed **220** on regular width
  (matches design `searchW=220`), full-width on compact. Verified centered (dock center = screen center).
- SC4 ✅ Properties = centered **form sheet** on iPad (`presentationSizing(.form)`), bottom sheet on iPhone.
- SC5 ✅ portrait: sidebar collapses to a translucent glass leading overlay + dim.
- SC6 ✅ no regression — NotoVault 67 tests pass; builds clean; landscape re-lays out (native split).

Changes: `NotoSidebarView` (translucent `.ultraThinMaterial` glass bg, hidden trailing rule, clear header),
`NoteEditorScreen` (`showsEditorDock` gate + `propertiesSheetPresentation` form-sheet on regular width).

## Verification (claude-design-verifier vs NotoIPad frames)
Ran 2026-06-05. Returned PARTIAL → fixed both deltas → matches:
- SC3 search pill was 320 vs design 220 → set to **220**.
- SC2 folder glyph was muted@0.62 vs design ink@0.80 → set to **ink@0.80**.
- PASS: header, row structure, active-row accent tint, hairlines, glass translucency, properties form sheet.
- Minor accepted gap: zero-item folder subtitle shows "Empty" (shared `contentsSummary`) vs design "{n} items".

## Remaining polish (follow-up)
- Bare native split sidebar-toggle (system glass button) if a bare look is wanted.
- Landscape visual spot-check (flowdeck doesn't auto-rotate framebuffer cleanly).
- Floating rounded-20 *detached* sidebar panel (`IPadSidebar` literal) — currently a themed glass
  NavigationSplitView column (option A); detached card would need a custom ZStack (option B).
