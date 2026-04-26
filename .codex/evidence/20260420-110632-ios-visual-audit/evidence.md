# iOS Visual Evidence Audit

Verdict: PASS

Timestamp: 2026-04-20 11:10:31 HKT

Repository: /Users/eugenechan/dev/personal/Noto

Simulator: Noto-AppBars-20260420 / iPhone 16 Pro, iOS 26.2, A191DEF2-4816-48D4-B59F-DED26FFAD8A6

App: com.eugenechan.Noto

## Change Audited

The Noto iOS bottom bar was changed from a Today button plus search field into one centered pill-shaped bottom container with three icon actions: Today's Note, Search, and New Note. Search is intentionally inert. New Note should create a new note at the root of the vault and open its editor. The editor top bar should remain visible with back, breadcrumb/title, and more actions.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| 1. Note list shows one pill-shaped bottom container with exactly three visible actions: Today's Note, Search, New Note. | PASS | `01-note-list-initial.jpg` shows one centered bottom pill with calendar, magnifying glass, and compose icons. `01-note-list-initial-tree.json` captures the list state and bottom toolbar group. |
| 2. Search action is inert: tapping it does not navigate away, show a keyboard, or change list contents. | PASS | Tapped center action at `(201,816)`. `02-after-search-tap.jpg` remains on the note list with the same visible rows and no keyboard. `02-after-search-tap-tree.json` remains a Notes heading/list state with no keyboard node. |
| 3. Tapping New Note from the note list creates a root-vault note and opens the note editor for that new note. | PASS | Tapped right action at `(256,816)`. `03-new-note-editor-screen-command.jpg` shows the newly opened blank editor. After tapping back, `04-list-after-new-note-back.jpg` and `04-list-after-new-note-back-tree.json` show a new UUID-titled note row at the root list alongside root folders and seeded notes. |
| 4. In the new note editor, the same bottom pill remains visible when keyboard is not shown. | PASS | `03-new-note-editor-screen-command.jpg` shows the editor with no keyboard and the same three-icon bottom pill. |
| 5. Editor top bar shows back button, breadcrumb/title area, and more options button. | PASS | `03-new-note-editor-screen-command.jpg` shows the top bar with a back chevron on the left, root breadcrumb/title `Noto` centered, and an ellipsis button on the right. |
| 6. Tapping Today's Note from the bottom pill opens today's note. | PASS | Tapped left action at `(146,816)`. `05-today-note-editor.jpg` shows the editor opened to `Noto > Daily Notes` with title `20 Apr, 26 (Mon)`, matching the local audit date in `local-timestamp.txt`. |

## Artifacts

- `01-note-list-initial.jpg`
- `01-note-list-initial-tree.json`
- `02-after-search-tap.jpg`
- `02-after-search-tap-tree.json`
- `03-new-note-editor.jpg`
- `03-new-note-editor-tree.json`
- `03-new-note-editor-screen-command.jpg`
- `03-new-note-editor-screen-command.json`
- `04-list-after-new-note-back.jpg`
- `04-list-after-new-note-back-tree.json`
- `05-today-note-editor.jpg`
- `05-today-note-editor-tree.json`
- `flowdeck-apps.json`
- `local-timestamp.txt`
- `seed-vault.log`
- `session-start.json`

## Commands

- `flowdeck config get --json`
- `flowdeck simulator list --json`
- `flowdeck run -S A191DEF2-4816-48D4-B59F-DED26FFAD8A6 --json`
- `.maestro/seed-vault.sh A191DEF2-4816-48D4-B59F-DED26FFAD8A6`
- `flowdeck run -S A191DEF2-4816-48D4-B59F-DED26FFAD8A6 --no-build --json`
- `flowdeck ui simulator session start -S A191DEF2-4816-48D4-B59F-DED26FFAD8A6 --json`
- `flowdeck ui simulator tap --point 201,816 --geometry points -S A191DEF2-4816-48D4-B59F-DED26FFAD8A6 --json`
- `flowdeck ui simulator tap --point 256,816 --geometry points -S A191DEF2-4816-48D4-B59F-DED26FFAD8A6 --json`
- `flowdeck ui simulator screen -S A191DEF2-4816-48D4-B59F-DED26FFAD8A6 --output .codex/evidence/20260420-110632-ios-visual-audit/03-new-note-editor-screen-command.jpg --json`
- `flowdeck ui simulator tap --point 40,84 --geometry points -S A191DEF2-4816-48D4-B59F-DED26FFAD8A6 --json`
- `flowdeck ui simulator tap --point 146,816 --geometry points -S A191DEF2-4816-48D4-B59F-DED26FFAD8A6 --json`
- `flowdeck apps --json`

## Notes

- FlowDeck accessibility snapshots exposed the bottom bar as a top-level `Toolbar` group but did not expose the three bottom pill buttons as separate accessibility nodes, despite the implementation identifiers. The audit therefore used point taps based on the visible centered pill and saved screenshots for visual proof.
- The editor navigation bar controls were also not surfaced as separate accessibility nodes in the FlowDeck tree; visual proof is in the editor screenshots.
- No application source code, tests, project files, package files, or build settings were edited.
