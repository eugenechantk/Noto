# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-06-11 00:28 (local)
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: Noto-Test-tchtgt-ipad (6BB283F6-7DCC-48AB-B004-7010A804383D, iPad mini), Noto-Test-tchtgt (5B578975-0CC8-4794-BDF6-46E7F42D8780, iPhone 16 Pro — regression only)
App: com.eugenechan.Noto

## Change Audited

Feature doc: `.codex/feature/sidebar-trio-and-ipad-dock-scroll.md`

1. **Sidebar header trio (iPad):** sidebar header replaced new-folder + ellipsis with the file-view trio: new-note (`square.and.pencil`), sort (`line.3.horizontal.decrease`), more (ellipsis), with menu contents reshuffled (New Folder moved into more menu, New Note removed from it).
2. **iPad dock hides on scroll:** scroll-driven dock hide/show plumbed from `NoteEditorScreen` through `VaultWorkspaceView` to `NotoSplitView`'s floating dock.

App was pre-built and installed per caller instruction; launched with `flowdeck run --no-build` only (no rebuild performed).

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC1: Sidebar header shows back (when in a folder) + new-note + sort + more, ids `sidebar_new_note_button` / `sidebar_sort_menu` / `sidebar_more_button`, all 44×44pt, correct left-to-right order | PASS | `tree-sidebar-header.json` — frames 44×44 at x=193/237/281 (correct order); `sidebar_back_button` (52×44) appears at x=26 when inside Daily Notes (`tree-after-new-note.json`); screenshots `05`, `08` |
| SC2: Sort menu shows exactly Recent and Name | PASS | `06-sidebar-sort-menu.jpg` + `tree-sidebar-sort-menu.json` — only "Recent" (checked) and "Name"; dismissed after |
| SC3: More menu shows New Folder, AI Chat, Settings; no "New Note" | PASS | `07-sidebar-more-menu.jpg` + `tree-sidebar-more-menu.json` — exactly `sidebar_new_folder_button` (New Folder), `sidebar_chat_button` (AI Chat), Settings; no New Note item; dismissed after |
| SC4: New-note button inside a folder creates + opens an untitled note in that folder | PASS | Navigated into Daily Notes (2 notes), tapped `sidebar_new_note_button` → `note_Untitled` row appeared & selected, count became "0 folders · 3 notes", editor opened (keyboard + editor toolbar `toggle_todo_button` etc. in tree). `09-after-new-note-tap.jpg`, `tree-after-new-note.json`. Cleanup: deleted via row swipe → Delete; back to 2 notes (`10-untitled-deleted.jpg`) |
| SC5: Header compact — single nav row above large folder title, matching file-view styling | PASS | `05-sidebar-open.jpg` (vault root), `10-untitled-deleted.jpg` (folder: "‹ Vault" + trio in one row above large "Daily Notes" title); layout matches iPhone file-view bar (`11-iphone-file-view-regression.png`) |
| SC6: iPad dock hides on scroll-down, reappears on scroll-up in "Long Scroll Test" | PASS | Before: dock visible, ids `today_button`/`search_button`/`new_root_note_button` present (`02-dock-visible-before-scroll.jpg`, `tree-dock-before-scroll.json`). After swipe-up (content scrolled down): all 3 ids absent, no dock in screenshot (`03-dock-hidden-after-scroll-down.jpg`, `tree-dock-after-scroll-down.json`). After swipe-down (scroll up): all 3 ids back, dock visible (`04-dock-restored-after-scroll-up.jpg`, `tree-dock-after-scroll-up.json`) |
| SC7: iPhone regression — file-view top bar `new_note_button`/`sort_menu`/`more_menu` at 44×44, list renders normally | PASS | `tree-iphone-topbar.json` — all three 44×44 at x=267/311/355; vault list + dock render normally (`11-iphone-file-view-regression.png`) |

## Artifacts

All under `.codex/evidence/20260611-002207-ios-visual-audit/`:

- `01-ipad-launch.jpg` — app launch (opened into Long Scroll Test, dock visible)
- `02-dock-visible-before-scroll.jpg`, `03-dock-hidden-after-scroll-down.jpg`, `04-dock-restored-after-scroll-up.jpg` — SC6 before/during/after
- `05-sidebar-open.jpg` — sidebar at vault root with trio (SC1/SC5)
- `06-sidebar-sort-menu.jpg` — SC2
- `07-sidebar-more-menu.jpg` — SC3
- `08-sidebar-daily-notes-before-create.jpg`, `09-after-new-note-tap.jpg`, `10-untitled-deleted.jpg` — SC4 + cleanup
- `11-iphone-file-view-regression.png` — SC7
- `tree-*.json` — accessibility tree snapshots backing each frame/id assertion

## Commands

- `flowdeck run -S "Noto-Test-tchtgt-ipad" --no-build --json` (and same for `Noto-Test-tchtgt`)
- `flowdeck ui simulator session start -S "Noto-Test-tchtgt-ipad" --json`
- `flowdeck ui simulator screen -S <sim> --json` (tree + frame assertions)
- `flowdeck ui simulator tap <id> --by-id` / `--point x,y` / `--duration 1.0`
- `flowdeck ui simulator swipe --from … --to …` (scroll + row swipe-delete)

## Notes

- No rebuild performed per caller instruction; audited the installed build.
- Menu dismissal via tap on the full-screen "Dismiss context menu" layer; taps issued in the same shell invocation as the dismiss occasionally raced the animation and needed one retry (no app misbehavior).
- Long-pressing a sidebar row shows the list-background context menu (New Note / New Folder), not a row delete menu; cleanup used swipe-to-delete instead, which worked. Not a success criterion — informational only.
- SC6 proven with before/during/after screenshots + accessibility-tree presence/absence rather than a recording; the state change is unambiguous in stills.
- macOS sidebar trio not audited (out of scope for this audit; feature doc notes it compiles but is visually unverified).
