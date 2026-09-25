# iOS Visual Evidence Audit

Verdict: PARTIAL

Timestamp: 2026-09-25 12:59 HKT

Repository: `/Users/eugenechan/dev/personal/Noto`

Simulator: `cc-01a0d6dd-01a0d6e8` — iPhone 17 Pro-class, iOS 26.3, UDID `801FA72D-661F-4AC6-AE66-909D480E8725`

App: Noto (`com.eugenechan.Noto`), scheme `Noto-iOS`, project `Noto.xcodeproj`

## Change Audited

Native note-row context actions in `DirectoryContentListView`: long-press exposes Move and destructive Delete; Move presents `MoveNoteDestinationPicker`; Delete requires confirmation; ordinary note taps and folder behavior remain distinct.

## Success Criteria

| Criterion | Result | Evidence |
| --- | --- | --- |
| SC1: Long-press opens a native context menu without opening the note. | PASS on compact iPhone | `03-long-press-move-sheet.mov` and `03-context-menu.jpg` show the menu over the Vault list while Project Plan remains a row, not an open editor. `03-context-menu-tree.json` exposes the native menu actions and dismissal region. |
| SC2: Menu contains Move and Delete with familiar symbols. | PASS | `03-context-menu.jpg` visibly shows Move with a folder symbol and red Delete with a trash symbol. The accessibility tree identifies `note_context_move_action` and `note_context_delete_action`. |
| SC3: Move opens the destination picker and moves the pressed note through the workspace path. | PASS on compact iPhone | `04-move-picker.jpg` / tree show the existing Move Note picker. After selecting Archive, `05-after-move-root.jpg` shows the root note count drop from four to three and Archive increase to one item; `06-moved-note-in-archive.jpg` shows Project Plan inside Archive. Source inspection confirms the picker callback emits `VaultWorkspaceIntent.moveNote`. |
| SC4: Delete is destructive, requires confirmation, and deletes the pressed note through the workspace path. | PASS on compact iPhone | `07-long-press-delete-confirmation.mov`, `07-archive-context-menu.jpg`, and `08-delete-confirmation.jpg` show red destructive Delete followed by “Delete this note?” / red “Delete Note”. After confirmation, `09-after-delete-empty-archive.jpg` shows Archive empty. Source inspection confirms the list callback emits the existing delete workspace intent. |
| SC5: Normal taps still open notes; folders do not gain note-only actions. | PASS on compact iPhone | `02-tap-opens-note.mov` and `02-tap-opened-project-plan.jpg` show an ordinary tap opening Project Plan. `10-folder-long-press-no-note-actions.mov` and `10-after-folder-long-press-tree.json` show the same held gesture on Archive produces no note action identifiers; because the folder has no context menu, the synthetic hold resolves as normal folder activation. Source inspection confirms only `noteButton` owns the note context menu. |
| SC6: Works in compact iPhone lists and regular-width iPad sidebar lists. | PARTIAL | Compact iPhone behavior passed all runtime checks above. Regular-width iPad could not be run: the repository FlowDeck isolation hook bound this session to the dedicated iPhone simulator and blocked `-S "iPad mini (A17 Pro)"`, requiring every subsequent FlowDeck command to use UDID `801FA72D-661F-4AC6-AE66-909D480E8725`. |

## Artifacts

- `01-launch.jpg`, `01-launch-tree.json` — seeded Vault list before actions.
- `02-tap-opens-note.mov`, `02-tap-opened-project-plan.jpg`, `02-tap-opened-project-plan-tree.json` — ordinary tap opens Project Plan.
- `03-long-press-move-sheet.mov`, `03-context-menu.jpg`, `03-context-menu-tree.json` — long-press and native Move/Delete menu.
- `04-move-picker.jpg`, `04-move-picker-tree.json` — existing Move Note destination picker.
- `05-after-move-root.jpg`, `05-after-move-root-tree.json` — Project Plan removed from root and Archive count becomes one.
- `06-moved-note-in-archive.jpg`, `06-moved-note-in-archive-tree.json` — Project Plan present in Archive.
- `07-long-press-delete-confirmation.mov`, `07-archive-context-menu.jpg`, `07-archive-context-menu-tree.json` — second long-press and destructive Delete selection.
- `08-delete-confirmation.jpg`, `08-delete-confirmation-tree.json` — destructive confirmation UI.
- `09-after-delete-empty-archive.jpg`, `09-after-delete-empty-archive-tree.json` — confirmed deletion mutation.
- `10-folder-long-press-no-note-actions.mov`, `10-after-folder-long-press.jpg`, `10-after-folder-long-press-tree.json` — folder does not expose note-only actions.

## Commands

- `flowdeck config get --json`
- `flowdeck context --json`
- `flowdeck run -S "iPad mini (A17 Pro)" --json` — blocked by per-session isolation before launch.
- `flowdeck run -S "801FA72D-661F-4AC6-AE66-909D480E8725" --json`
- `.maestro/seed-vault.sh 801FA72D-661F-4AC6-AE66-909D480E8725`
- `flowdeck ui simulator session start -S "801FA72D-661F-4AC6-AE66-909D480E8725" --json`
- FlowDeck `tap --duration 1.2`, element taps by accessibility identifier, and `record` commands for the interactions above.

## Notes

- Overall verdict is PARTIAL solely because the requested regular-width iPad runtime could not be targeted under this session's enforced simulator binding. No iPad claim is inferred from the source or from the existing caller-provided iPhone evidence.
- The compact iPhone runtime independently verified both actual mutations, not just menu presentation: Project Plan moved from Vault Root to Archive and was then deleted from Archive.
- FlowDeck's accessibility session intermittently flattened the ordinary app tree to the application root, but native context menus, sheets, and confirmation UI exposed stable identifiers. Static screenshots were captured after each action as the visual source of truth.
- Product source, tests, project files, and build settings were not modified by this audit.
