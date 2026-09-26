# iOS Visual Evidence Audit

Verdict: PASS

Timestamp: 2026-09-26 00:03 HKT

Repository: `/Users/eugenechan/dev/personal/Noto`

Simulator: `cc-01a0d6ec-01a0d939` (iPhone 17 Pro, iOS 26.3), `1B60D302-3F59-4E9A-883E-2E43468D1C72`

App: Noto 2 (`com.eugenechan.Noto2`), scheme `Noto2`

## Change Audited

Noto 2 Browse root and nested-folder chrome now use system navigation toolbar controls and the editor-style soft top fade. The shared note editor More menu adds Copy Path and copies the current note's vault-relative Markdown path.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| Browse root uses system-sized Liquid Glass toolbar controls consistent with editor chrome, without a hard rectangular top-bar boundary | PASS | `01-browse-root-native-toolbar.png`; root Settings and More are rendered in the system's shared 44-point-height glass grouping and the content/background transitions continuously below it. |
| Nested Browse uses native Back and More controls matching the editor's geometry and has the same soft, borderless top transition | PASS | `03-browse-nested-native-toolbar.png` compared with `04-editor-native-toolbar-reference.png`; Back/More positions, circle sizes, title baseline, and the seam-free background transition match. |
| Root More menu still contains New Note and New Folder | PASS | `02-browse-root-more-menu.png`; both actions are visible. The FlowDeck tree reported `browse_new_note_action` and `browse_new_folder_action`. |
| Note editor More menu contains Copy Path with identifier `copy_note_path_menu_item` | PASS | `05-editor-copy-path-menu.png` and `05-editor-copy-path-tree.json`; the tree records a visible Button labeled `Copy Path` with the required identifier. |
| Copy Path can be invoked and copies the note's vault-relative path | PASS | Invoked by identifier with FlowDeck. `06-copy-path-invoked.png` shows the menu dismissed after invocation; `07-copy-path-paste-result.png` proves the clipboard value by pasting `Projects/Roadmap.md` into the note. |

## Artifacts

- `01-browse-root-native-toolbar.png`
- `02-browse-root-more-menu.png`
- `03-browse-nested-native-toolbar.png`
- `04-editor-native-toolbar-reference.png`
- `05-editor-copy-path-menu.png`
- `05-editor-copy-path-tree.json`
- `06-copy-path-invoked.png`
- `07-copy-path-paste-result.png`

## Commands

- `flowdeck config get --json`
- `flowdeck run -s Noto2 -S "1B60D302-3F59-4E9A-883E-2E43468D1C72" --json`
- `flowdeck simulator boot 1B60D302-3F59-4E9A-883E-2E43468D1C72 --json`
- `flowdeck run -s Noto2 -S "1B60D302-3F59-4E9A-883E-2E43468D1C72" --no-build --json`
- `flowdeck ui simulator session start -S "1B60D302-3F59-4E9A-883E-2E43468D1C72" --json`
- FlowDeck UI `tap`, `type`, `key`, `wait`, and `screen` commands on the same simulator.

## Notes

- The root's adjacent Settings and More items are intentionally merged by iOS 26 into one native Liquid Glass group; nested Browse and the editor each show the same native 44-point circular treatment for their individual Back/More controls.
- The isolated simulator began without vault data. The audit created a vault through the public onboarding UI, created `Projects`, created and renamed a note to `Roadmap`, then used only normal app interactions to prove the flow.
- Clipboard contents were proven through the system Paste action rather than inferred from source code.
- No source, test, package, project, or build-setting file was changed by this audit.
