# iOS Visual Evidence Audit

Verdict: PARTIAL

Timestamp: 2026-09-25 13:11:47 HKT

Repository: `/Users/eugenechan/dev/personal/Noto`

Simulator: `cc-01a0d6ec-01a0d6f2` (iPhone 17 Pro, iOS 26.3; `AE2FF25F-6C50-49D7-BF74-5FBC58217066`)

App: Noto 2 (`com.eugenechan.Noto2`), scheme `Noto2`, workspace `Noto.xcodeproj`

## Change Audited

Noto 2 Browse directory screens add a trailing More actions menu for creating a note or subfolder in the currently displayed directory. The audit covered menu presentation, directory targeting, blank-name rejection, list refresh, editor navigation/autofocus, and runtime accessibility identifiers.

## Success Criteria

| Criterion | Result | Evidence |
| --- | --- | --- |
| SC1: Every opened directory exposes trailing More actions | PASS | `01-projects-directory.jpg` shows the control in nested `Projects`; `02-more-menu.jpg` shows it opening there. Root Browse also shows the same control in `10-root-projects-two-items.jpg`. |
| SC2: Menu offers New Note and New Folder with recognizable symbols | PASS | `02-more-menu.jpg`; semantic labels and IDs are recorded in `02-more-menu-tree.json`. |
| SC3: New Note creates in the displayed directory and navigates to a focused editor | PASS | `interaction.mov` records New Note from `Projects`, immediate editor navigation, and direct typing without an intervening editor tap. `07-new-note-editor-autofocus.jpg` shows the initial caret; `08-autofocus-direct-typing.jpg` shows the entered title; `09-note-and-folder-in-projects.jpg` shows `Audit Nested Note` back in `Projects`. |
| SC4: New Folder prompts, creates in the displayed directory, and refreshes | PASS | `03-folder-alert-empty-disabled.jpg`, `05-folder-name-valid.jpg`, and `06-folder-created-in-projects.jpg`. `09-note-and-folder-in-projects.jpg` shows both created items in `Projects`; `10-root-projects-two-items.jpg` shows `Projects` updated to 2 items. |
| SC5: Empty or whitespace-only names cannot be submitted | PASS | In `interaction.mov`, Create is tapped with an empty field and again after three spaces; the alert remains both times. `03-folder-alert-empty-disabled.jpg` shows the disabled visual state and `04-whitespace-rejected.jpg` shows the alert still present after the whitespace submission attempt. |
| SC6: New controls expose stable accessibility identifiers | FAIL | Runtime UI queries found `browse_new_note_action`, `browse_new_folder_action`, and `browse_create_folder_button` (`02-more-menu-tree.json`, `03-folder-alert-empty-disabled-tree.json`). FlowDeck could not discover `browse_more_actions_menu` while the toolbar control was visible or `browse_new_folder_name_field` while the alert field was visible; those IDs are absent from `01-projects-directory-tree.json` and `03-folder-alert-empty-disabled-tree.json`. |

## Artifacts

- `interaction.mov` — full 150-second multi-step interaction recording.
- `01-projects-directory.jpg` — nested directory before mutation.
- `02-more-menu.jpg` / `02-more-menu-tree.json` — menu contents, symbols, and action IDs.
- `03-folder-alert-empty-disabled.jpg` / tree — empty alert state and Create ID.
- `04-whitespace-rejected.jpg` / tree — alert retained after whitespace-only Create attempt.
- `05-folder-name-valid.jpg` — valid folder name before submission.
- `06-folder-created-in-projects.jpg` / tree — refreshed nested directory with new folder.
- `07-new-note-editor-autofocus.jpg` / tree — new editor with insertion caret immediately after navigation.
- `08-autofocus-direct-typing.jpg` — title entered without tapping the editor.
- `09-note-and-folder-in-projects.jpg` / tree — created note and folder in the same nested directory.
- `10-root-projects-two-items.jpg` / tree — root count confirms both items are scoped to `Projects`.

## Commands

- `flowdeck config get --json`
- `flowdeck apps --json`
- `flowdeck run -s Noto2 -S "AE2FF25F-6C50-49D7-BF74-5FBC58217066" --json`
- `.maestro/seed-vault.sh AE2FF25F-6C50-49D7-BF74-5FBC58217066 --bundle-id com.eugenechan.Noto2 --initial-tab browse`
- `flowdeck ui simulator session start -S "AE2FF25F-6C50-49D7-BF74-5FBC58217066" --json`
- `flowdeck ui simulator record -S "AE2FF25F-6C50-49D7-BF74-5FBC58217066" --output .../interaction.mov --duration 150 --codec h264 --force`
- FlowDeck `tap`, `find`, `type`, `hide-keyboard`, and `open-url` commands, always with the isolated simulator UDID.
- `flowdeck ui simulator session stop -S "AE2FF25F-6C50-49D7-BF74-5FBC58217066" --json`

## Notes

- Build and launch succeeded. The existing saved FlowDeck config targets `Noto-iOS`; the audit used a one-off `Noto2` scheme override and did not change the saved config.
- The software keyboard did not reappear after it had been hidden during navigation setup. Autofocus was instead proven by the visible insertion caret and successful direct typing immediately after New Note, without any editor tap; this sequence is recorded in `interaction.mov`.
- The two missing runtime accessibility IDs are the only failed criterion. Their SwiftUI modifiers exist in source, but this audit evaluates the runtime accessibility surface, where those identifiers were not exposed.
- No application source, tests, project files, or build settings were modified. Existing unrelated working-tree changes were preserved.
