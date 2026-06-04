# Feature: iOS note list (File view) — v2 redesign

## User Story
As a Noto user on iPhone, I see the vault file view (folders + notes) in the new
minimal v2 design (claude.ai/design "Noto System" → File view).

## User Flow
File view = one folder level per page. Large title (folder name) + count subtitle;
folders first (with chevron), then notes (with "Edited <when>"); bottom floating
dock (today/daily · search · new). Tap folder → push level; tap note → editor;
back returns. Navigation is unchanged (VaultWorkspaceView intents).

## Spec reference
`.claude/ios-redesign/component-breakdown.md` (main checkout) — §1 tokens, §3 File view,
§2 library (Top bar · Bottom bar · List view · List item). Source JSX:
`Design/v2/components/noto-notabs-screens.jsx · NoTabsNoteList/FolderRow/FileRow`.
Live render: http://localhost:8765/Noto%20System.html.

## Success Criteria
- SC1 ✅: `NotoTheme` exposes the v2 tokens (bg #0E1116, ink #ECECEE, head #FFF, accent #FF6A2E, muted/faint/hairline, grouped/card/separator/chip, amber, destructive) + type ramp.
- SC2 ✅: Folder list item = folder glyph + name (16/semibold) + count subtitle + trailing chevron, NotoTheme colors.
- SC3 ✅: Note list item = doc glyph + title (16/semibold) + "Edited <when>" subtitle (abbreviated via `NotoRelativeDate`), NotoTheme colors.
- SC4 ✅: Data unchanged — folders-first then notes (already from VaultDirectoryLoader); no regression in list behavior/navigation. Sort (Recent/Name) added on top.
- SC5 ✅: Large-title top bar ("Vault" at root / folder name nested), count subtitle row, dark list surface (#0E1116), accent toolbar tint, new-folder/sort/⋯ trailing toolbar.
- SC6 ✅: Nested level shows custom accent "‹ <ParentName>" back button (parent of vault root → "Vault").
- SC7 ✅: FloatingDock matches design — three capsules: calendar+day badge · full-width "Search" pill · accent-tinted new-note button.
- SC10 ✅: Bottom dock is scoped to file views ONLY (root + nested `FolderContentView`), not the editor — matching the chosen minimal-editor design ("No bottom dock"). Fix: moved `.notoAppBottomToolbar` off the whole `NavigationStack` (where it overlaid every pushed screen incl. the editor) and into `FolderContentView`.
- SC9 ✅: Dock capsules use real Liquid Glass (`.glassEffect(.regular.interactive(), in: .capsule)` inside `GlassEffectContainer`, iOS 26+; `.regularMaterial` fallback below). Dynamic blur is visible when list content scrolls behind the floating dock (requires a list longer than the viewport; the seeded vault is short, so the effect is subtle in current screenshots).

- SC8 ✅: Top bar is a custom BARE-icon bar (system nav bar hidden) per Eugene's call — leading accent "‹ <parent>" (nested), trailing bare icons, no Liquid Glass capsule. Trailing order: **New Note** (direct, primary) · Sort menu · ⋯ More menu (**New Folder** + **Settings**). Settings shows at EVERY level (canOpenSettings passed to nested FolderContentView), not root-only. Edge-swipe-back preserved via `InteractivePopGestureEnabler` (re-sets `interactivePopGestureRecognizer.delegate`, gated to stack depth > 1; runtime-confirmed).

## Resolved decision
- Top-bar chrome: Eugene chose the **custom bare-icon bar** over native iOS 26 Liquid Glass capsules. Implemented by hiding the system nav bar (`.toolbar(.hidden, for: .navigationBar)`) and rendering a flat `topBar` + in-content large title. Tradeoff (lost native swipe-back) was mitigated: the interactive pop gesture is re-enabled via a `UIViewControllerRepresentable` that re-installs the gesture delegate. Note: a synthetic simulator swipe can't validate a `UIScreenEdgePanGestureRecognizer`; the back button popping is the testable proof.

## Test Strategy
Data/ordering/counts already covered by `NotoVaultTests` (VaultDirectoryLoaderTests). Row
styling is UI — verified in Simulator + visual evidence audit. No new non-UI logic in this slice
(tokens are constants; relative-date uses SwiftUI Text).

## Tests
- Reuse `Packages/NotoVault/Tests/NotoVaultTests/VaultDirectoryLoaderTests.swift` (ordering/counts) — SC4.
- UI rows: simulator visual audit — SC2, SC3.

## Implementation Details
- New `Noto/Support/NotoTheme.swift` (tokens) — SC1.
- Restyle `FolderRow` + `MarkdownNoteRow` in `Noto/Views/NoteListView.swift` to NotoTheme — SC2, SC3. Add a11y ids.
- Navigation / data layer untouched — SC4.

## Residual Risks
- Final spacing/large-title/dock/selection not in this slice (SC5).
- Relative-date abbreviation ("2h" vs "2 hours ago") not matched yet.
- Simulator render is the only proof of row appearance.

## Bugs
_None yet._
