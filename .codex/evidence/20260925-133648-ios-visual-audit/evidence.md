# iOS Visual Evidence Audit

Verdict: PASS

Timestamp: 2026-09-25 13:42 HKT

Repository: /Users/eugenechan/dev/personal/Noto

Simulator: cc-01a0d6ec-01a0d70e / iPhone 17, iOS 26.3 (E2B9E990-3445-448E-BFF6-9DC3C1A3EF4A)

App: Noto2 / com.eugenechan.Noto2

## Change Audited

Noto 2 Browse directory creation actions implemented in a custom native SwiftUI top bar: centered directory title, root Settings, nested Back, and a trailing More actions menu containing New Note and New Folder.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC1: Every opened directory exposes trailing More actions | PASS | `01-root-top-bar.png`, `03-projects-top-bar.png`, and `15-second-level-directory.png` show the control on root, first-level, and second-level directories. Matching trees resolve `browse_more_actions_menu` as an enabled `PopUpButton` centered at x=372. |
| SC2: Menu offers New Note and New Folder with native symbols | PASS | `02-root-menu.png` and `16-second-level-menu.png` visibly show the document-plus and folder-plus symbols beside the two labels. Both action IDs resolve as enabled buttons. |
| SC3: New Note targets the displayed directory and opens its editor | PASS | `10-new-note-autofocus.mov` records creation from Projects. `11-new-note-editor-autofocused.png` shows the insertion caret before any editor tap; direct typing produced `12-direct-typing-autofocus.png`. Returning to Projects shows `Scoped Note From Projects` in `13-projects-scoped-note.png`. |
| SC4: New Folder prompts, creates in displayed directory, and refreshes | PASS | `04-new-folder-empty.png` shows the compact naming sheet. Creating `Clean Subfolder` from Projects immediately refreshed that same list in `19-clean-folder-created.png`; `19-clean-folder-created-tree.json` resolves `Clean Subfolder, Empty`. |
| SC5: Empty and whitespace-only names cannot be submitted | PASS | In `04-new-folder-empty.png`, Create is visibly disabled. Tapping it left the sheet present in `05-empty-create-rejected.png`. FlowDeck then typed three spaces; another Create tap again left the sheet present in `07-whitespace-create-rejected.png`. |
| SC6: Stable accessibility identifiers | PASS | Fresh runtime queries resolved `browse_more_actions_menu`, `browse_new_note_action`, `browse_new_folder_action`, `browse_new_folder_name_field`, `browse_create_folder_button`, and `browse_cancel_folder_button`. Relevant tree snapshots are `02-root-menu-tree.json`, `04-new-folder-empty-tree.json`, and `16-second-level-menu-tree.json`. |

## Artifacts

- Top-bar and navigation layout: `01-root-top-bar.png`, `03-projects-top-bar.png`, `14-custom-back-to-root.png`, `15-second-level-directory.png`, `17-second-level-back-to-projects.png`
- Native menus and symbols: `02-root-menu.png`, `16-second-level-menu.png`
- Folder validation and refresh: `04-new-folder-empty.png` through `09-folder-created-refresh.png`, plus `19-clean-folder-created.png`
- Directory-scoped note and autofocus: `10-new-note-autofocus.mov`, `11-new-note-editor-autofocused.png`, `12-direct-typing-autofocus.png`, `13-projects-scoped-note.png`
- Root Settings interaction: `18-root-settings-open.png`
- Accessibility trees: matching `*-tree.json` files beside the screenshots

## Commands

- `flowdeck config get --json`
- `flowdeck run -s Noto2 -S "E2B9E990-3445-448E-BFF6-9DC3C1A3EF4A" --json`
- `.maestro/seed-vault.sh E2B9E990-3445-448E-BFF6-9DC3C1A3EF4A --bundle-id com.eugenechan.Noto2 --initial-tab browse`
- `flowdeck run --no-build -s Noto2 -S "E2B9E990-3445-448E-BFF6-9DC3C1A3EF4A" --json`
- `flowdeck ui simulator session start -S "E2B9E990-3445-448E-BFF6-9DC3C1A3EF4A" --json`
- FlowDeck `find`, `tap`, `type`, `erase`, and `record` commands against the explicit isolated simulator
- `flowdeck ui simulator session stop -S "E2B9E990-3445-448E-BFF6-9DC3C1A3EF4A"`

## Notes

- The custom bar remained visually balanced: directory-title centers were x=201, nested Back x=30, root Settings x=328, and More actions x=372. The root Settings button opened its sheet (`18-root-settings-open.png`), and nested Back returned through both directory levels.
- The simulator had a hardware keyboard connected, so the editor's software keyboard was not visible. Autofocus was proven by the visible insertion caret and successful direct FlowDeck typing without tapping the editor first.
- SwiftUI's accessibility tree reported the visually disabled empty-name Create button as `enabled: true`. Functional verification still passed: empty and whitespace taps were no-ops and the sheet remained open. This is a residual accessibility-state mismatch, not a submission failure.
- The implementation agent's reported focused run (6/6) and earlier full Noto2 run (110/110) were not rerun; this audit independently covered the simulator acceptance checks.
