# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-10-18 22:17–22:23 HKT
Repository: /Users/eugenechan/dev/personal/Noto (uncommitted changes on main)
Simulator: FA1047D4-3B58-4A9E-983E-8571E43BB15B (iPhone, 402x874 pt, iOS 26)
App: com.eugenechan.Noto2 (scheme Noto2), already installed and seeded; not rebuilt or reinstalled

## Change Audited

- Library shows the `inbox` folder (it was hidden before).
- Library's Recent section and Search's "recently edited" list still leave out raw captures in `inbox/`.
- Folder pages: "N folders · N notes" moved into the title bar as a subtitle; sorting moved from the in-list "Recent ⌄" row to a title-bar sort button (arrow.up.arrow.down) beside New note.

Diff checked: `Noto2/Browse/BrowseScreen.swift`, `Noto2/Search/SearchModel.swift`,
`Packages/NotoVault/Sources/NotoVault/LibraryCatalog.swift`, `NotePinning.swift`.

## Success Criteria

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | Library's Folders section lists `inbox` with count 3 | PASS | `02-library-folders-inbox-3.png`; tree `02-library-folders-inbox-3.json` has `Button 'inbox, 3'` id `libraryFolder_inbox` |
| 2 | Opening `inbox` lists its 3 captures; tapping one opens the editor; Back returns to the folder | PASS | sim-navigate run (Library > inbox > capture two), `04-capture-open-in-editor.png` (editor shows "Audit inbox capture two: read the Liquid Glass HIG"; trace shows `note_editor` value starting with id `01f544b9…`, which is `inbox/2026-10-18-audit001.md`), `05-back-to-inbox-folder.png` (back on inbox page, 3 captures listed) |
| 3 | Library Recent and Search recently edited show no "Audit inbox capture" note | PASS | `01-library-recent-top.png` (Recent: 7 notes, no capture), `13-search-recently-edited.png` + `.json` (7 notes, no capture). `vault-mtimes.txt` shows why the result is meaningful: the captures (15:32:01) are newer than four notes that appear in both lists (15:31:50), so they would be in both lists if the filter did not work. |
| 4 | Folder page shows the name with counts under it in the title bar; the list starts with content | PASS | inbox: `03-inbox-folder-header-recent.png` ("inbox" / "0 folders · 3 notes"; first row is the "THIS WEEK" section). Bulk: `10-bulk-folder-header.png` (collapsed title "Bulk" / "0 folders · 8001 notes") and `11-bulk-folder-header-scrolled-to-top.png` (large title with counts under it). The list starts with "THIS WEEK". No summary or sort row in either list. Baseline for comparison: `../20261018-153051-ios-visual-audit/10-L4-bulk-folder-instant.png` shows the old in-list "0 folders · 8000 notes … Recent ⌄" row. |
| 5 | Sort button opens Recent / Name / Oldest, marks the current choice, and re-sorts | PASS | `06-sort-menu-recent-checked.png` (checkmark on Recent), `07-sorted-by-name.png` (order: one, three, two; header NOTES), `08-sort-menu-name-checked.png` (checkmark moved to Name), `09-sorted-by-oldest.png` (order: one, two, three). Recent order was three, two, one under "THIS WEEK" (`03`). Second folder: `12-bulk-sorted-by-name.png` (Bulk Note 0000, 0001, …). |

## Artifacts

- `01-library-recent-top.png` / `.json`: Library top, with Pinned (Bulk note 1234) and Recent (7 notes, no captures)
- `02-library-folders-inbox-3.png` / `.json`: Folders section: Archive 0, Bulk 8,001, Captures 2, inbox 3, Projects 0
- `03-inbox-folder-header-recent.png`: inbox page header, default Recent sort
- `04-capture-open-in-editor.png` / `.json`: capture two open in the editor
- `05-back-to-inbox-folder.png` / `.json`: after Back, the inbox page shows again
- `06-sort-menu-recent-checked.png` / `.json`: sort menu, with Recent checked
- `07-sorted-by-name.png` / `.json`: inbox sorted by Name
- `08-sort-menu-name-checked.png` / `.json`: sort menu, with Name checked
- `09-sorted-by-oldest.png` / `.json`: inbox sorted by Oldest
- `10-bulk-folder-header.png` / `.json`: Bulk page on entry (collapsed title with subtitle)
- `11-bulk-folder-header-scrolled-to-top.png` / `.json`: Bulk page after a scroll up (large title with subtitle)
- `12-bulk-sorted-by-name.png` / `.json`: Bulk sorted by Name
- `13-search-recently-edited.png` / `.json`: Search recently edited (7 notes, no captures)
- `14-inbox-tab-still-has-captures.png` / `.json`: the Inbox tab still shows the 3 captures for review
- `vault-mtimes.txt`: read-only `stat` of the vault file mtimes
- `sim-navigate/20261018-221920-in-the-library-tab-open-the-inbox-folder/`: `final.png`, `trace.jsonl`, `replay.sh`

## Commands

- `flowdeck config get --json`: saved config is Noto-iOS on another simulator, so every command passed `-S "FA1047D4-3B58-4A9E-983E-8571E43BB15B"`. The config was not changed.
- `flowdeck ui simulator session start -S "FA1047D4-…" --json`: session `32281BFC`
- `flowdeck ui simulator screen -S "FA1047D4-…" -o <file>.png --json`: every screenshot and its tree
- `flowdeck ui simulator tap "libraryFolder_Bulk" --by-id`, `tap "libraryNoteBack" --by-id`, `tap "Name"`, `tap "Oldest"`
- `flowdeck ui simulator tap -p "302,84"`: the sort button (coordinates; see Notes). `tap -p "37,84"`: folder Back. `tap -p "349,821"` / `"200,821"`: Search and Inbox tabs.
- `flowdeck ui simulator scroll -d UP|DOWN`
- `sim_navigate.py -S FA1047D4-… --goal "In the Library tab, open the 'inbox' folder from the Folders section, then open the note 'Audit inbox capture two: read the Liquid Glass HIG'" --check "A note editor is open showing the text '…'"`. Outcome: Jev reached `done` in 4 steps. The `--check` scored 0.02 (`checks_failed`) because the tree only exposes the raw TextArea value, which starts with frontmatter. The final screenshot shows the capture text in the editor. Judged PASS from `final.png` / `04`. Replay: `sim-navigate/20261018-221920-in-the-library-tab-open-the-inbox-folder/replay.sh`
- `flowdeck ui simulator session stop -S "FA1047D4-…"`

## Notes

- The title-bar sort and New note buttons are not in the FlowDeck/AXe tree. Only a nav-bar `Group` with id = folder name appears. So the sort button was tapped by coordinates (302,84). Its accessibility label "Sort notes" could not be checked from the tree. The menu items (Recent/Name/Oldest) are in the tree.
- A folder page opens with the large title collapsed: a centered small name with the subtitle. The large leading title shows after a scroll up. Both states show the counts under the name. This behavior already existed: the pre-change baseline `../20261018-153051-ios-visual-audit/10-L4-bulk-folder-instant.png` also opens collapsed. It is not a regression.
- The sort choice does not persist. Leaving and re-entering a folder resets it to Recent. The implementer's session left inbox on Oldest, and it was Recent after re-entry. This is not in the criteria.
- No folder in the seeded vault has subfolders, so "N folders" was only seen as 0. A page whose first section is Folders was not exercised. The vault was not modified to seed one.
- No capture is pinned, so the "pinned captures show in Pinned" decision was not checked visually.
- Screen recording was not used. Every criterion is static or step-wise, and screenshots prove each one.
