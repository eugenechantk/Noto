# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-06-11 00:08 (local)
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: iPhone 16 Pro "Noto-Test-tchtgt" (5B578975-0CC8-4794-BDF6-46E7F42D8780); iPad mini "Noto-Test-tchtgt-ipad" (6BB283F6-7DCC-48AB-B004-7010A804383D)
App: com.eugenechan.Noto (scheme Noto, launched with `--no-build` per caller instruction)

## Change Audited

1. **header-touch-targets** (`.codex/feature/header-touch-targets.md`): file-view top bar buttons (new_note_button, sort_menu, more_menu, back_button) and iPad sidebar header buttons (sidebar_back_button, sidebar_new_folder_button, sidebar_more_button) expanded to ≥44×44pt hit targets without visual change. Diff surface: `Noto/Views/NoteListView.swift`, `Noto/Views/Shared/NotoSidebarView.swift`.
2. **image-links-no-label** (`.codex/feature/image-links-no-label.md`): no-label image links `![](...)`, including vault-relative paths with spaces, render as image blocks. Diff surface: `Noto/Editor/TextKit2EditorView.swift`.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC1: iPhone new_note_button / sort_menu / more_menu accessibility frames ≥44×44pt | PASS | `iphone-header-tree.json` — new_note_button 44×44 @ (267,64); sort_menu 44×44 @ (311,64); more_menu 44×44 @ (355,64) |
| SC2: iPad sidebar_new_folder_button & sidebar_more_button ≥44×44pt; sidebar_back_button height ≥44pt | PASS | `ipad-sidebar-tree.json` — sidebar_back_button 52×44 @ (26,47); sidebar_new_folder_button 44×44 @ (237,47); sidebar_more_button 44×44 @ (281,47) |
| SC3: Off-center corner tap (~15pt diagonal from glyph center, outside old ~20pt glyph target) triggers buttons | PASS | iPhone: tap (348,101) on sort_menu (center 333,86) opened Recent/Name menu — `02-iphone-sortmenu-offcenter-tap.jpg`. iPad: tap (318,84) on sidebar_more_button (center 303,69) opened New Note/New Folder/AI Chat/Settings menu — `09-ipad-moremenu-offcenter-tap.jpg`. Both menus dismissed after. |
| SC4: Visual layout essentially unchanged (compact single-row header, trailing glyph near edge, no inflated buttons, sidebar title directly under nav row) | PASS | `01-iphone-launch.jpg` — single-row header, three small glyphs, ellipsis ~16pt from right edge (frame right edge at x=399 of 402pt screen). `08-ipad-sidebar-open.jpg` — sidebar nav row (‹ Vault · new-folder · ellipsis) with "Daily Notes" title directly beneath; no visible button inflation. |
| SC5: No raw `![](...)` markdown text visible scrolling Image Test top→bottom | PASS | `03-iphone-imagetest-top.jpg`, `04-iphone-imagetest-mid.jpg`, `05-iphone-imagetest-bottom.jpg`, `06-iphone-imagetest-placeholder.jpg` — full scroll coverage; only rendered image blocks/placeholder, zero raw markdown. Editor text never tapped; scrolled by swipe only; keyboard never appeared. |
| SC6: Blocks 1, 3, 4 show real image content; block 2 shows placeholder | PASS | Block 1 (remote picsum 300/200): road/tunnel photo in `03`. Block 2 (`xyz.png`, missing): gray rounded placeholder block in `03`/`06`. Block 3 (`attachments/Pasted image 20260610.png`, space in path): city-skyline image in `04`/`06` — verified identical to the actual on-disk vault file at `.../File Provider Storage/Noto/attachments/Pasted image 20260610.png`. Block 4 (remote picsum 300/201 with alt): forest-path photo in `04`/`05`. |

## Artifacts

All under `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260611-000049-ios-visual-audit/`:

- `01-iphone-launch.jpg` — iPhone file view baseline (SC4)
- `02-iphone-sortmenu-offcenter-tap.jpg` — sort menu opened from corner tap (SC3)
- `03-iphone-imagetest-top.jpg` — Image Test top: block 1 image + placeholder start (SC5/SC6)
- `04-iphone-imagetest-mid.jpg` — blocks 3 (vault attachment) and 4 (SC5/SC6)
- `05-iphone-imagetest-bottom.jpg` — bottom of note, no raw markdown (SC5)
- `06-iphone-imagetest-placeholder.jpg` — block 2 placeholder + block 3 in one frame (SC6)
- `07-ipad-launch.jpg` — iPad editor on launch
- `08-ipad-sidebar-open.jpg` — sidebar header inside Daily Notes (SC2/SC4)
- `09-ipad-moremenu-offcenter-tap.jpg` — sidebar more menu from corner tap (SC3)
- `10-ipad-final-dismissed.jpg` — final state after dismissing menu
- `iphone-header-tree.json` — accessibility frames for SC1
- `ipad-sidebar-tree.json` — accessibility frames for SC2

## Commands

- `flowdeck config get --json`
- `flowdeck run -S 5B578975-0CC8-4794-BDF6-46E7F42D8780 --no-build --json`
- `flowdeck run -S 6BB283F6-7DCC-48AB-B004-7010A804383D --no-build --json`
- `flowdeck ui simulator session start -S <udid> --json` (per simulator)
- `flowdeck ui simulator screen -S <udid> --json` (frame inspection)
- `flowdeck ui simulator tap --point <x,y> -S <udid> --json` (corner taps, navigation, dismissals)
- `flowdeck ui simulator swipe --from <x,y> --to <x,y> -S <udid>` (note scrolling)

## Notes

- Coordinates were used for the corner taps deliberately (the point of SC3 is hitting a spot outside the old glyph target); element identifiers were used for frame assertions.
- Block 3 proof is strong: the rendered city image was compared against the actual PNG read from the simulator vault on disk — pixel content matches, confirming the space-in-path vault-relative resolution fix.
- iPhone back_button (inside-folder file view) frame was not separately measured — the caller's SC1 scoped iPhone to the three trailing buttons; iPad sidebar_back_button (the analogous control) measured 52×44.
- No rebuild was performed per caller instruction; the audit assumes the installed build matches the working tree (consistent with timestamps and observed behavior).
- macOS rendering of vault-relative images remains unverified (out of scope, flagged in the feature doc as residual risk).
