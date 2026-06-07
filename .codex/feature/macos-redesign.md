# Feature: macOS — v2 redesign (sidebar + editor; tabs deferred)

## Source
Design `NotoMac` in `Design/v2/components/noto-platforms.jsx` (lines 449–512, states
`reading | editing | inspector`). Tabs (`NotoMacTabs`, 514+) are **explicitly deferred** —
they need a multi-open-note view architecture change (separate pass).

## Design spec (rendered)
**Window** (1280×800, radius 12, bg `#0E1116`, **padding 8, gap 8**) = two floating panels:
- **Sidebar panel** — width **230**, full height, **floating glass**: rounded **14**,
  `rgba(34,38,46,0.55)` + `blur(50) saturate(180)`, inset shadows
  (`inset -0.5px 0 0 rgba(0,0,0,0.30), inset 0 0.5px 0 rgba(255,255,255,0.10)`).
  - **44px top row** holding the **traffic lights** (they ride INSIDE the sidebar's top-left).
  - then `VaultSidebarContent` (the SAME explorer body as iPhone/iPad: accent `‹ Vault` back ·
    new-folder + ⋯ more · large folder title + "N folders · M notes" counts · `SidebarFolderRow`
    / `SidebarFileRow` with active-note accent tint).
- **Detail panel** — flex 1:
  - **44px toolbar**, bare SF symbols (`MacBtn` 36×36, 20pt, HEAD color, no glass/border):
    LEADING `sidebar + back` · TRAILING `search + more`. **Two buttons each side.**
  - the **Article** editor (markdown body), padding ~8.
- **Properties** = the same iPad-style **centered form sheet** (`PropsCard`, 540w) over a dimmed
  window — for the `inspector` state.

## Scope (this pass) — USER CHOSE FULL DESIGN incl. floating panel
In: floating glass sidebar panel + traffic-lights-inside, `VaultSidebarContent` sidebar, bare
two-each-side detail toolbar, editor body colors, properties form sheet.
Out: tabs (multi-open-note architecture) — deferred.

## Current implementation (baseline)
- `NotoApp` already: `.windowStyle(.hiddenTitleBar)` + `.windowToolbarStyle(.unified)`, NSWindow config.
- macOS shell = `NotoSplitView.macOSSplitView` → `NavigationSplitView(.prominentDetail)` with
  `NotoSidebarView` (legacy centered-title header + compact rounded rows, solid `sidebarBackground`)
  + detail = `splitDetailView` → `NoteEditorScreen` with `.macToolbar` chrome (native window toolbar:
  nav back/forward + breadcrumb principal + ellipsis.circle More menu).
- `MacEditorNavigationChrome` renders into the NATIVE window toolbar (`ToolbarItemGroup`).

## Architecture decision
The floating-inset rounded glass panels + traffic-lights-inside **cannot** be expressed with
`NavigationSplitView` (it owns the column chrome + flush backgrounds). Replace the macOS shell with
a **custom layout**: a root `ZStack(bg #0E1116)` → `HStack(spacing: 8)` of a fixed-width glass
**sidebar panel** + a flex **detail panel**, inside `.padding(8)`. Traffic lights are left to the
system (hiddenTitleBar already overlays them at window top-left) and the sidebar's 44px top row
reserves space so they land inside it. iPad/iOS keep `NavigationSplitView` untouched.

Sidebar collapse, in-app search overlay, and window-scoped commands (toggle sidebar / show search)
must keep working in the custom layout.

## Build order (slices, build between each)
1. **Shared `VaultSidebarContent` on macOS.** Make `iosSidebarHeader` + the design `SidebarDirectoryRow`
   rows compile/render on macOS (currently `#if os(iOS)`); rename to platform-neutral. Keep macOS
   drag/drop + context menus.
2. **Custom macOS window layout.** New `MacWindowLayout` (or rework `NotoSplitView.macOSSplitView`):
   padded `HStack` of glass sidebar panel (230, rounded 14, slate glass, 44px traffic-light row) +
   detail panel. Wire collapse + search overlay + commands. Glass = uniform (clear the List's opaque
   bg so no two-tone seam — lesson from the iPad pass).
3. **Detail panel custom toolbar.** Bare SF buttons two-each-side (sidebar+back / search+more), 20pt
   HEAD, inside a 44px row in the detail panel (NOT the native window toolbar). Retire `.macToolbar`'s
   window-toolbar rendering for this screen (or switch chrome mode).
4. **Editor body colors.** macOS NSTextView background/ink/accent = `NotoTheme` (match the dark editor),
   as the iOS editor already does.
5. **Properties form sheet.** Present `PropertiesSheet` centered (~540) over a dimmed window for macOS,
   reusing the shared sheet (already cross-platform-ish).

## Success Criteria
- SC1: Window = dark bg with TWO floating rounded glass panels (sidebar + detail), inset + gapped.
- SC2: Traffic lights sit inside the sidebar panel's top-left 44px row.
- SC3: Sidebar = `VaultSidebarContent` (accent back, new-folder + ⋯, large title + counts, folder/file
  rows, active-note accent tint), uniform glass (no two-tone seam).
- SC4: Detail toolbar = bare SF symbols, two buttons each side (sidebar+back / search+more).
- SC5: Editor body uses NotoTheme dark colors; markdown rendering intact.
- SC6: Properties = centered form sheet over a dimmed window.
- SC7: No regression — sidebar collapse, search overlay, open/select note, window commands all work;
  iPad/iOS shells unchanged; NotoVault tests pass.

## Verify
macOS build/run (`/flowdeck`, `My Mac`). Then `claude-design-verifier` against `NotoMac` — verify the
FULL component inventory (window shell, traffic-light placement, sidebar panel glass+rounding+inset,
sidebar header, folder/file rows, detail toolbar BOTH groups, editor body, properties sheet), blind
(no expected values in the spawn prompt).

## Status: slice 1 done + macOS build fixed.
- **Slice 1 ✅** `VaultSidebarContent` now renders on macOS (made `vaultSidebarHeader` + the v2
  `SidebarDirectoryRow` rows + sidebar list insets/separator-hide cross-platform: `os(iOS) || os(macOS)`).
  Verified visually (large title + counts, folder/file rows, active-note accent tint, new-folder + ⋯).
- **Build fix ✅** macOS scheme was broken since the iOS-redesign search dock + `SheetCircleButton`
  used `#available(iOS 26, *)` (no `macOS 26`) → `glassEffect`/`GlassEffectContainer` failed against the
  macOS 15 target. Patched 4 sites → `#available(iOS 26, macOS 26, *)` with the material fallback.
- **Slice 2 ✅** custom macOS window layout: replaced `NavigationSplitView` with a `ZStack(bg) →
  padded HStack(spacing 8)` of a floating glass sidebar panel (`macSidebarGlassPanel()`: ultraThin +
  `NotoTheme.sidebarGlass`, rounded 14, inset stroke + shadow, width 230) + plain detail. Sidebar
  internal backgrounds cleared (glass shows uniformly); 30px top reserve for traffic lights.
- **Slice 3 ✅** detail toolbar rewritten to an IN-PANEL 44px bare-SF-symbol row (LEADING sidebar +
  back · TRAILING search + more); native window toolbar retired.
- **Slice 4 ✅** macOS editor "Metadata" block suppressed (`rendersInlineFrontmatterBlock = false` +
  guarded reserved-inset / block-view); editor body already NotoTheme dark.
- **Slice 5 ◻ (deferred)** Properties centered form sheet — needs the iOS-only `PropertiesSheet`
  ported to macOS (form-sheet presentation + AppKit-compatible inline editing). Follow-up.

## Verification (claude-design-verifier vs NotoMac, blind, component-by-component)
Ran 2026-06-05. PARTIAL → fixed all 5 measured deltas → matches:
1. Sidebar more button showed a native macOS `Menu` disclosure chevron → added `.menuIndicator(.hidden)`.
2. Editor body bg was `AppTheme.nsBackground` (#0A0A0A) vs design #0E1116 → added `NotoTheme.nsBackground`
   (#0E1116) + `drawsBackground = true`.
3. Detail toolbar glyphs 18pt → 20pt (design `MacBtn` size 20).
4. Sidebar traffic-light top reserve 30 → 34px (≈ design's 44px row with the header's 10pt top padding).
5. Sidebar panel right-edge inner hairline added (design `inset -0.5px 0 0 rgba(0,0,0,0.30)`).
PASS (blind): window shell (canvas #0E1116, padding/gap 8), traffic-lights-inside-sidebar, sidebar glass
(rgba(34,38,46,0.55)+blur, rounded 14, uniform — no two-tone seam), `VaultSidebarContent` (accent back,
24/700 title, counts, folder/file rows, active accent tint), detail toolbar 2+2 bare SF, editor body
(no metadata block). Regression check: sidebar collapse (⌘⇧B) works in the custom layout; editor fills
full width, toolbar intact.

## Architecture correction (2026-06-06) — use the NATIVE sidebar, don't rebuild it
User feedback: the more button should be minimal/icon-only; the sidebar must be WIDER + RESIZABLE;
the traffic lights were missing from the sidebar — and "these should all come with the native sidebar
+ Liquid Glass, like Apple apps." Correct. Per Apple docs (TN3154; WWDC25 "Build a SwiftUI app with
the new design" #323; `navigationSplitViewColumnWidth(min:ideal:max:)`): on macOS 26 (Tahoe)
`NavigationSplitView` provides the **floating Liquid Glass sidebar, resizable column, and correct
traffic-light placement natively** — the glass adapts to content beneath; `backgroundExtensionEffect`
lets the detail extend behind it.

**Reverted Slice 2's custom HStack layout** back to `NavigationSplitView`:
- `NavigationSplitView` + `.navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)` → wider +
  drag-resizable; native Liquid Glass sidebar; traffic lights restored (the custom glass panel had been
  drawing OVER them).
- Sidebar keeps the v2 content (`VaultSidebarContent`) with CLEAR backgrounds so the native glass shows.
- More button → `.menuStyle(.borderlessButton)` + `.menuIndicator(.hidden)` (minimal icon-only).
- `macSidebarGlassPanel()` helper removed (native provides the glass).
Kept: in-panel bare detail toolbar (slice 3), editor Metadata suppression (slice 4), 34px sidebar
top reserve for the traffic lights.

## Top-bar correction (2026-06-06) — native TOOLBARS give the full-height sidebar + traffic lights + alignment
User (with a Notes screenshot as reference): sidebar must span the FULL window height (no top gap),
traffic lights inset INTO the sidebar, and the sidebar buttons aligned with the editor's top bar.
Root cause: removing the native window toolbar (slice 3's in-panel bare toolbar) made Tahoe render the
sidebar as a FLOATING panel with a top gap, and left the traffic lights stranded in the margin above it.
A native window toolbar is what anchors the top bar across the window → full-height sidebar, native
traffic-light placement inside it, and system-aligned toolbar items (exactly how Notes/Mail look).

Fix:
- `MacEditorNavigationChrome` → reverted to a NATIVE `.toolbar` (back · search · more; native split
  provides the sidebar-toggle). No more in-panel bar.
- Sidebar new-folder + more → moved into a NATIVE sidebar `.toolbar` (`MacSidebarToolbar`,
  `.primaryAction`), removed from the content header on macOS (kept in the header on iOS).
- Deleted all manual hacks: traffic-light repositioning (NSWindow), `ignoresSafeArea(.top)`, and the
  34px sidebar top reserve — the native toolbar handles all of it.
- `.menuIndicator(.hidden)` on both toolbar more-menus (no disclosure chevron).
Result matches the Notes reference: full-height sidebar, traffic lights inside the top-left, all top-bar
buttons aligned. Trade-off accepted: native toolbar buttons get Tahoe's glass treatment (vs the Claude
mock's bare icons) — the user explicitly chose the native macOS behavior.

## Detail top bar → match the iPad editor chrome (2026-06-06)
User: the macOS detail top bar should look + function like iPadOS — content fades into the top on
scroll, the note title rises into the top bar on scroll, LEFT = sidebar + back, RIGHT = search + more.
Done on the NATIVE toolbar:
- `MacEditorNavigationChrome`: LEADING group = sidebar-toggle (from `leadingControls`) + back;
  `.principal` = the note title, faded in via `showsScrolledTitle`; TRAILING = search + more.
- Ported the scrolled-title state cross-platform in `NoteEditorScreen` (`showsScrolledTitle` + the
  `offsetY > 48` logic now run on macOS too; passed `scrolledTitle`/`showsScrolledTitle` to the chrome).
- **Bug fixed:** `EditorContentView` wired `onContentOffsetYChange` to the iOS `TextKit2EditorView` but
  NOT the macOS one, so the macOS editor never reported scroll offset → the title never appeared.
  Added the missing `onContentOffsetYChange:` to the macOS editor call. (Content-fade is the native
  macOS toolbar scroll-edge material — automatic once content scrolls under the toolbar.)

## Status: slices 1,3,4 complete; slice 2 = native NavigationSplitView + native toolbars (full-height
sidebar, traffic lights inside, aligned top bar — matches Notes); detail top bar matches the iPad editor
chrome (scroll-fade + scrolled title + sidebar/back · search/more). Slice 5 (properties) deferred. Tabs deferred.

Files touched (slice 1 + build fix): `Noto/Views/Shared/NotoSidebarView.swift` (shared `vaultSidebarHeader`),
`Noto/Views/NoteListView.swift` (`SidebarDirectoryRow` + insets/separator cross-platform; glass `#available`),
`Noto/Views/Shared/SheetCircleButton.swift` (glass `#available`).

## Detail top bar tint must EXACTLY match the editor body (2026-06-06)
User: "the top bar is still in a darker shade than the editor background — make it the same tint."
Root cause (found by pixel-sampling): with `.toolbarBackground(.hidden, for: .windowToolbar)` the
unified toolbar is transparent. Over the SIDEBAR it shows native Liquid Glass (good); over the DETAIL
it showed the detail column's backing = `#0A0A0A` (10,10,10) — darker + untinted vs the editor's
`#0E1116` (15,17,22). A red-toolbar experiment confirmed `.toolbarBackground(color)` paints the WHOLE
unified toolbar (both columns) → a solid color would kill the sidebar glass, so the fix had to be
detail-scoped.

Fix (native, detail-only — keeps sidebar glass, no scrolled-text smear):
- `NotoSplitView` macOS detail: `detail(...).frame(maxWidth/Height: .infinity).background(NotoTheme.background).ignoresSafeArea(.container, edges: .top)` — the editor's NSView extends UNDER the toolbar so its backing fills the top-bar strip; `.top` only (not all edges, else the detail slides under the floating sidebar and clips the title).
- macOS `TextKit2EditorViewController.loadView`: `view.wantsLayer = true; view.layer.backgroundColor = NotoTheme.nsBackground.cgColor` — the view backing IS the strip.
- Pinned `scrollView.topAnchor` to `view.safeAreaLayoutGuide.topAnchor` (was `view.topAnchor`) + `scrollView.automaticallyAdjustsContentInsets = false` — text still CLIPS below the toolbar (no smear behind buttons on scroll) even though the view extends under it.
- `MacEditorNavigationChrome`: kept `.toolbarBackground(.hidden, for: .windowToolbar)`.
- `NotoApp`: `window.titlebarAppearsTransparent = true`; macOS root bg → `NotoTheme.background`.
Verified by pixel sample (strip = 15,17,22 = editor) + screenshots at-rest / scrolled / collapsed:
uniform #0E1116 bar, title rises into bar on scroll, content clips below toolbar, sidebar glass intact.

## Sidebar new-folder/more → content header row (same line as back), matching iPad (2026-06-06)
User: "on the sidebar, the new folder and more action button should be on the same line as the back
button — same as iPad." Previously these lived in the NATIVE macOS sidebar toolbar (traffic-light
line), a different line from the in-sidebar `‹ back` button (which is in the content header nav row).
Fix: removed the `#if os(iOS)` guard so the new-folder + ⋯ menu render in `vaultSidebarHeader`'s nav
HStack on macOS too (same row as the `‹ back` button), and deleted the `MacSidebarToolbar` modifier +
struct. Top toolbar line now shows only traffic lights on the sidebar side. `notoSidebarVisible` env
value is now unused (still set in NotoSplitView) — harmless. Verified visually on macOS.

## Slice 5: Properties sheet on macOS (2026-06-06)
User: "implement the properties sheet for macOS as well — use the sheet for macOS to hold the
properties view." Done by making the existing iOS view cross-platform (no rewrite):
- Moved `Noto/Views/iOS/PropertiesSheet.swift` → `Noto/Views/Shared/PropertiesSheet.swift` and
  removed the `#if os(iOS)` wrapper. The project uses filesystem-synchronized groups, so the move is
  picked up automatically (no pbxproj edit). The data layer (`EditableFrontmatterDocument`,
  `NotePropertyClassifier`, `NotoRelativeDate`) already lives in the cross-platform NotoVault package.
- Bridged the 3 iOS-only APIs: `propertiesListStyle()` (`.insetGrouped` iOS / `.inset` macOS),
  `propertiesNoAutocap()` (`.textInputAutocapitalization` iOS / no-op macOS), and `DeletePropertyAction`
  (swipe-to-delete iOS / right-click context-menu delete macOS).
- `MacEditorNavigationChrome`: added `onShowProperties` + `propertyCount`, with a "Properties" item
  (title + "N properties" subtitle) at the top of the More menu.
- `NoteEditorScreen`: moved `showProperties` / `pendingMoveAfterProperties` / `propertyCount` out of
  `#if os(iOS)` to share them; added the macOS `.sheet(isPresented: $showProperties)` presenting
  `PropertiesSheet` in a 460–560 × 520–720 frame, with the same move-after-properties hand-off as iOS.
Verified on macOS: sheet presents centered with the ✕/✓ header, Folder/Created/Modified/Updated rows,
Add-property pull-down (Text/Tags/Date & time) works. Both Noto-macOS and Noto (iOS) build clean.

## Slice 5b: native macOS Properties controls (2026-06-06)
User: "is there no native implementation of lists and date pickers for macOS? the iOS-like versions
look awkward." Replaced the shared iOS sheet on macOS with a native `MacPropertiesForm`
(`Noto/Views/macOS/MacPropertiesForm.swift`):
- Native grouped `Form` (`.formStyle(.grouped)`) instead of the iOS inset-grouped card list.
- Native inline field-and-stepper `DatePicker` per editable date field — replaces the iOS modal
  graphical date overlay. Created/Modified shown as read-only `LabeledContent`.
- Native plain `TextField` rows for text/url/tags (tags as comma-separated), commit on submit/close;
  right-click context-menu delete; native pull-down "Add property" (alert for name+value).
- Reuses the SAME shared data layer (`EditableFrontmatterDocument` + `session.applyExternalContentEdit`).
- Kept the app's ✕/✓ sheet header for cross-app consistency.
`PropertiesSheet` reverted to iOS-only (moved back to `Views/iOS/`, re-wrapped `#if os(iOS)`).
`NoteEditorScreen` macOS sheet now presents `MacPropertiesForm`. Both targets build; native form +
inline date picker verified visually.

## Properties: tap-outside-to-dismiss on macOS + iPad (2026-06-07)
User: "when I click outside of the properties sheet, it should close — both macOS and iPadOS."
Root cause: SwiftUI `.sheet` never dismisses on an outside/background tap (only swipe on iPhone,
or programmatic); macOS sheets are fully modal. Fix: present the panel as a dimmed OVERLAY whose
backdrop closes it, on macOS and iPad (regular width). iPhone (compact) keeps the native bottom sheet.
- `NoteEditorScreen`: macOS `.sheet` removed; iPhone sheet gated to `horizontalSizeClass != .regular`;
  added a cross-platform `.overlay` shown when `showsPropertiesPanel` (macOS always / iOS regular).
  `propertiesPanelOverlay`: full-bleed `Rectangle().opacity(0.4)` backdrop with `.onTapGesture { dismissProperties() }`
  + a centered 520×580 clipped card. Open/close wrapped in `withAnimation` + `.transition(.opacity)`.
  Folder row → `dismissPropertiesThenMove()`.
- `MacPropertiesForm` + `PropertiesSheet`: added `.onDisappear { commit* }` so backdrop dismissal
  still commits in-progress edits.
Verified on macOS (click dimmed area → closes) and iPad sim (tap outside card → closes); both build.
