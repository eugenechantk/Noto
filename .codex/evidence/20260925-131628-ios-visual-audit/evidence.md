# iOS Visual Evidence Audit

Verdict: PARTIAL

Timestamp: 2026-09-25 13:20:24 HKT

Repository: `/Users/eugenechan/dev/personal/Noto`

Simulator: `cc-01a0d6ec-01a0d6fb` (iPhone 17 Pro, iOS 26.3; `C9BC9D53-0C37-4A8E-AE0C-E5E9DE72CE31`)

App: Noto 2 (`com.eugenechan.Noto2`), scheme `Noto2`, workspace `Noto.xcodeproj`

## Change Audited

Re-audit of the Noto 2 Browse directory create-actions feature after replacing the folder-name alert with a SwiftUI sheet and labeling the toolbar Menu trigger. The audit independently rechecked menu presentation, current-directory targeting, blank-name rejection, list refresh, new-note autofocus, and runtime accessibility identifier discovery.

## Success Criteria

| Criterion | Result | Evidence |
| --- | --- | --- |
| SC1: Every opened directory exposes a trailing More actions control | PASS | `02-projects-directory.jpg` shows the control in `Projects`; `08-child-directory-more-visible.jpg` shows it again one level deeper in the newly created `Audit Child` directory. |
| SC2: Menu offers New Note and New Folder with recognizable symbols | PASS | `03-more-menu.jpg` shows both commands and their native document-plus and folder-plus symbols. `03-more-menu-tree.json` exposes `browse_new_note_action` and `browse_new_folder_action`. |
| SC3: New Note creates in the displayed directory and navigates to a focused editor | PASS | `interaction.mov` records New Note from nested `Projects/Audit Child`, immediate editor navigation, and direct typing without an editor tap. `09-new-note-editor-autofocus.jpg` shows the insertion caret; `10-autofocus-direct-typing.jpg` shows the entered title; `11-note-in-audit-child.jpg` shows the note back in the same nested directory. |
| SC4: New Folder prompts, creates in the displayed directory, and refreshes | PASS | `04-folder-sheet-empty-disabled.jpg`, `06-valid-folder-name.jpg`, and `07-folder-created-in-projects.jpg` show the sheet, valid name, and refreshed `Projects` listing. `12-projects-with-child.jpg` and `13-root-projects-one-item.jpg` confirm the created folder remains scoped under `Projects`. |
| SC5: Empty or whitespace-only folder names cannot be submitted | PASS | In `interaction.mov`, Create is tapped while empty and again after three spaces; the sheet remains both times. `04-folder-sheet-empty-disabled.jpg` and `05-whitespace-rejected.jpg` show Create visually disabled and the sheet retained. |
| SC6: New controls expose stable accessibility identifiers | FAIL | Runtime discovery succeeds for `browse_new_note_action` and `browse_new_folder_action` in `03-more-menu-tree.json`. `browse_more_actions_menu` is absent from visible directory trees and `flowdeck ... find --by-id` returns `not_found`. In `04-folder-sheet-empty-disabled-tree.json`, every sheet child (title, TextField, Cancel, Create) is exposed with the container ID `browse_new_folder_sheet`; runtime queries for `browse_new_folder_name_field`, `browse_create_folder_button`, and `browse_cancel_folder_button` return `not_found`. |

## Artifacts

- `interaction.mov` — 176-second recording of folder creation validation, nested folder creation, nested New Note navigation, direct typing, and return to the scoped listings.
- `01-root-browse.jpg` / tree — seeded Browse root before mutation.
- `02-projects-directory.jpg` / tree — empty `Projects` directory with trailing More control visible.
- `03-more-menu.jpg` / tree — New Note and New Folder commands, symbols, and action IDs.
- `04-folder-sheet-empty-disabled.jpg` / tree — empty folder sheet; the tree demonstrates container-ID propagation over child IDs.
- `05-whitespace-rejected.jpg` / tree — sheet retained after whitespace-only Create attempt.
- `06-valid-folder-name.jpg` / tree — valid name with Create visibly enabled.
- `07-folder-created-in-projects.jpg` / tree — refreshed `Projects` directory containing `Audit Child`.
- `08-child-directory-more-visible.jpg` / tree — trailing More control on the deeper child directory.
- `09-new-note-editor-autofocus.jpg` / tree — new editor with insertion caret immediately after New Note.
- `10-autofocus-direct-typing.jpg` / tree — direct typed title without an intervening editor tap.
- `11-note-in-audit-child.jpg` / tree — created note inside `Projects/Audit Child`.
- `12-projects-with-child.jpg` / tree and `13-root-projects-one-item.jpg` / tree — directory-scope confirmation.

## Commands

- `flowdeck config get --json`
- `flowdeck apps --json`
- `flowdeck run -s Noto2 -S "C9BC9D53-0C37-4A8E-AE0C-E5E9DE72CE31" --json`
- `.maestro/seed-vault.sh C9BC9D53-0C37-4A8E-AE0C-E5E9DE72CE31 --bundle-id com.eugenechan.Noto2 --initial-tab browse`
- `flowdeck run --no-build -s Noto2 -S "C9BC9D53-0C37-4A8E-AE0C-E5E9DE72CE31" --json`
- `flowdeck ui simulator session start -S "C9BC9D53-0C37-4A8E-AE0C-E5E9DE72CE31" --json`
- `flowdeck ui simulator record -S "C9BC9D53-0C37-4A8E-AE0C-E5E9DE72CE31" --output .../interaction.mov --duration 180 --codec h264 --force`
- FlowDeck `find`, `tap`, and `type` commands, always against the isolated simulator UDID and using IDs where the runtime exposed them.
- `flowdeck ui simulator session stop -S "C9BC9D53-0C37-4A8E-AE0C-E5E9DE72CE31" --json`

## Notes

- The saved FlowDeck config targets `Noto-iOS`; the audit preserved it and used one-off `Noto2` and isolated-simulator overrides.
- Build and launch succeeded. The implementation agent reported a focused Explorer suite of 6/6 and a pre-presentation-adjustment full Noto 2 suite of 110/110; this audit did not rerun those tests.
- The intended sheet child identifiers are present in source but are not independently exposed by the runtime accessibility surface. The observed runtime result is that the parent `browse_new_folder_sheet` identifier replaces the child identifiers.
- The keyboard was not visually raised when New Note opened, but autofocus was proven by the visible insertion caret, editor keyboard-toolbar state, and successful direct typing without tapping the editor; the sequence is captured in `interaction.mov`.
- No application source, tests, project files, package files, or build settings were modified. Existing unrelated working-tree changes were preserved.
