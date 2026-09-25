# iOS Visual Evidence Audit

Verdict: PARTIAL

Timestamp: 2026-09-25 13:30:55 HKT

Repository: `/Users/eugenechan/dev/personal/Noto`

Simulator: `cc-01a0d6ec-01a0d704` (iPhone 17 Pro, iOS 26.3; `3C2EE419-CC61-4F7A-A89D-9CFC7045B612`)

App: Noto 2 (`com.eugenechan.Noto2`), scheme `Noto2`, workspace `Noto.xcodeproj`

## Change Audited

Third independent runtime audit of Noto 2 Browse directory create actions after replacing the trailing toolbar trigger with a UIKit `UIButton` and removing the parent identifier from the New Folder sheet. The audit covered every SC1-SC6 criterion, all six requested accessibility-ID queries, empty/whitespace rejection, nested folder creation and refresh, and directory-scoped New Note/autofocus.

## Success Criteria

| Criterion | Result | Evidence |
| --- | --- | --- |
| SC1: Every opened directory exposes a trailing More actions control | PASS | The ellipsis control is visibly present at Browse root (`01-root-browse.jpg`), in `Projects` (`02-projects-directory.jpg`), and one level deeper in `Projects/Audit Child` (`08-child-directory.jpg`). |
| SC2: Menu offers New Note and New Folder with recognizable symbols | FAIL | `03-more-menu.jpg` shows both correctly labeled commands, and `03-more-menu-tree.json` proves both actions semantically. However, no document-plus or folder-plus symbols are rendered in the live confirmation dialog; only centered text labels are visible. |
| SC3: New Note creates in the displayed directory and navigates to a focused editor | PASS | `interaction.mov` records New Note from `Projects/Audit Child`, immediate editor navigation, and direct typing without an editor tap. `09-new-note-editor-autofocus.jpg` shows the insertion caret, `10-autofocus-direct-typing.jpg` shows `Audit Nested Note`, and `11-note-in-audit-child.jpg` shows the saved note in that same child directory. |
| SC4: New Folder prompts, creates in the displayed directory, and refreshes | PASS | `04-folder-sheet-empty.jpg` shows the prompt; `06-folder-sheet-valid.jpg` shows the valid name; `07-folder-created-in-projects.jpg` shows the refreshed `Projects` list containing `Audit Child`. `12-projects-with-child.jpg` and `13-root-projects-scoped.jpg` confirm the folder and note remain scoped under `Projects`. |
| SC5: Empty or whitespace-only folder names cannot be submitted | PASS | In `interaction.mov`, Create is tapped with an empty field and again after typing three spaces; the sheet remains both times. `04-folder-sheet-empty.jpg` and `05-folder-sheet-whitespace.jpg` show Create visually disabled in both states. |
| SC6: New controls expose stable accessibility identifiers | FAIL | Explicit runtime queries resolve 5/6 IDs: `browse_new_note_action`, `browse_new_folder_action`, `browse_new_folder_name_field`, `browse_create_folder_button`, and `browse_cancel_folder_button`. `browse_more_actions_menu` remains `not_found` while the UIKit-backed ellipsis is visible in both `Projects` and `Audit Child`, including after restarting the FlowDeck UI session. See `runtime-id-queries.md`, `03-more-menu-tree.json`, and `04-folder-sheet-empty-tree.json`. |

## Artifacts

- `interaction.mov` — complete create-folder validation, nested folder creation, nested New Note, direct typing, and return-to-list sequence.
- `01-root-browse.jpg` / tree — seeded Browse root with trailing More control.
- `02-projects-directory.jpg` / tree — empty `Projects` directory with trailing More control.
- `03-more-menu.jpg` / tree — New Note and New Folder actions; labels and IDs are present, symbols are visually absent.
- `04-folder-sheet-empty.jpg` / tree — empty sheet and independent field/Create/Cancel IDs.
- `05-folder-sheet-whitespace.jpg` / tree — whitespace-only state retained with Create disabled.
- `06-folder-sheet-valid.jpg` / tree — valid folder name and enabled Create.
- `07-folder-created-in-projects.jpg` / tree — refreshed `Projects` list containing `Audit Child`.
- `08-child-directory.jpg` / tree — deeper directory also exposes the trailing More control.
- `09-new-note-editor-autofocus.jpg` / tree — new editor with insertion caret immediately after navigation.
- `10-autofocus-direct-typing.jpg` / tree — title entered without an intervening editor tap.
- `11-note-in-audit-child.jpg` / tree — created note in `Projects/Audit Child`.
- `12-projects-with-child.jpg` / tree and `13-root-projects-scoped.jpg` / tree — nested scope confirmation.
- `runtime-id-queries.md` — requested six-ID runtime query matrix.

## Commands

- `flowdeck config get --json`
- `flowdeck apps --json`
- `flowdeck run -s Noto2 -S "3C2EE419-CC61-4F7A-A89D-9CFC7045B612" --json`
- `.maestro/seed-vault.sh 3C2EE419-CC61-4F7A-A89D-9CFC7045B612 --bundle-id com.eugenechan.Noto2 --initial-tab browse`
- `flowdeck run --no-build -s Noto2 -S "3C2EE419-CC61-4F7A-A89D-9CFC7045B612" --json`
- `flowdeck ui simulator session start -S "3C2EE419-CC61-4F7A-A89D-9CFC7045B612" --json` (restarted once after the first tree read appeared sparse)
- `flowdeck ui simulator record -S "3C2EE419-CC61-4F7A-A89D-9CFC7045B612" --output .../interaction.mov --duration 240 --codec h264 --force`
- FlowDeck `find --by-id`, `tap`, and `type` commands, always against the isolated simulator UDID.
- `flowdeck ui simulator session stop -S "3C2EE419-CC61-4F7A-A89D-9CFC7045B612" --json`

## Notes

- The saved FlowDeck config targets `Noto-iOS`; it was preserved. This audit used one-off `Noto2` and isolated-simulator overrides.
- Build and launch succeeded. The implementation agent reported a focused Explorer run of 6/6 and an earlier full Noto 2 suite of 110/110; this visual audit did not rerun those tests.
- The New Folder sheet fix is successful: the field, Create, and Cancel IDs now survive independently at runtime.
- The trailing control works visually and opens the menu, but its requested runtime ID still does not survive the navigation-toolbar bridge. Coordinate tapping was used only because that control was not addressable by ID.
- The software keyboard was not visually raised when the new note opened, but autofocus is proven by the visible caret, editor keyboard-toolbar state, and successful direct typing without tapping the editor.
- No application source, tests, project files, package files, or build settings were modified. Existing unrelated working-tree changes were preserved.
